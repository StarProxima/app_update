// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:io';

import 'package:app_update/app_update.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'apk_update_installer_config.dart';
import 'apk_update_installer_config_parser.dart';
import 'native/apk_installer_native.dart';

/// Installer that downloads an APK on Dart side and triggers installation on Android.
///
/// - Download emits [UpdateInstallationDownloading]
/// - After download emits [UpdateInstallationDownloaded]
/// - If [ApkUpdateInstallerConfig.requireUserConfirm] is true, waits for
///   [confirmInstallation] before calling native install.
final class ApkUpdateInstaller implements UpdateInstaller {
  final Dio dio;
  final bool requireUserConfirm;
  final ApkInstallerNative _native = ApkInstallerNative();

  ApkUpdateInstaller({Dio? dio, this.requireUserConfirm = true})
    : dio = dio ?? Dio();

  StreamController<UpdateInstallationProgress>? _controller;
  Completer<void>? _confirmCompleter;
  StreamSubscription<dynamic>? _nativeSub;
  CancelToken? _downloadCancelToken;
  bool _cancelRequested = false;

  @override
  UpdateInstallerName get name => UpdateInstallerName.apkInstall;

  @override
  UpdateInstallerConfigParser createConfigParser() =>
      const ApkUpdateInstallerConfigParser();

  @override
  bool supports(Update update) {
    // We only support Android runtime + android updates.
    if (!Platform.isAndroid) return false;
    if (update.platform != UpdatePlatform.android &&
        update.platform != UpdatePlatform.any) {
      return false;
    }

    return true;
  }

  @override
  Stream<UpdateInstallationProgress> install(
    Update update,
    UpdateInstallerConfig? config,
  ) {
    if (_controller != null) {
      return _controller!.stream;
    }

    _controller = StreamController<UpdateInstallationProgress>.broadcast();
    _cancelRequested = false;

    unawaited(_run(update, config));
    return _controller!.stream;
  }

  Future<void> _run(Update update, UpdateInstallerConfig? config) async {
    final controller = _controller!;
    controller.add(const UpdateInstallationStarted());

    final parsedConfig =
        config is ApkUpdateInstallerConfig
            ? config
            : throw ArgumentError('Config is not ApkUpdateInstallerConfig');

    final urlString = update.content.updateUrl.trim();
    final uri = Uri.tryParse(urlString);
    if (uri == null) {
      controller.add(UpdateInstallationFailed('Invalid updateUrl: $urlString'));
      await _cleanup();
      return;
    }

    final fileName =
        parsedConfig.fileName ?? _inferFileName(uri: uri, update: update);

    try {
      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}$fileName');
      if (await file.exists()) {
        await file.delete();
      }

      // Download apk file
      await _download(
        uri: uri,
        file: file,
        onProgress: (bytes, total) {
          final progress = total == null || total <= 0 ? 0.0 : bytes / total;
          controller.add(
            UpdateInstallationDownloading(
              progress: progress.clamp(0.0, 1.0),
              bytesDownloaded: bytes,
              totalBytes: total,
            ),
          );
        },
      );

      if (_cancelRequested) {
        controller.add(const UpdateInstallationCancelled());
        await _cleanup();
        return;
      }

      // Validate sha256 checksum
      final sha256 = parsedConfig.sha256;
      if (sha256 != null) {
        final ok = await _validateSha256(file, sha256);
        if (!ok) {
          controller.add(
            const UpdateInstallationFailed(
              'SHA-256 checksum validation failed',
            ),
          );
          await _cleanup();
          return;
        }
      }

      final isNeedConfirm =
          parsedConfig.requireUserConfirm ?? requireUserConfirm;
      final size = await file.length();
      controller.add(
        UpdateInstallationDownloaded(
          downloadedUpdate: DownloadedUpdate(
            filePath: file.path,
            fileSize: size,
            metadata: {'url': uri.toString()},
          ),
          isNeedConfirm: isNeedConfirm,
        ),
      );

      if (isNeedConfirm) {
        _confirmCompleter = Completer<void>();
        // Wait for user confirm
        await _confirmCompleter!.future;
        _confirmCompleter = null;
      }

      if (_cancelRequested) {
        controller.add(const UpdateInstallationCancelled());
        await _cleanup();
        return;
      }

      // Install apk file
      controller.add(const UpdateInstallationExecuting());
      await _installNative(filePath: file.path);

      if (_cancelRequested) {
        controller.add(const UpdateInstallationCancelled());
        await _cleanup();
        return;
      }

      controller.add(const UpdateInstallationCompleted());
      await _cleanup();
    } catch (e, s) {
      controller.add(UpdateInstallationFailed('APK installation failed', e, s));
      await _cleanup();
    }
  }

  static String _inferFileName({required Uri uri, required Update update}) {
    if (uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return 'update_${update.version}.apk';
  }

  Future<void> _download({
    required Uri uri,
    required File file,
    required void Function(int bytesDownloaded, int? totalBytes) onProgress,
  }) async {
    final cancelToken = CancelToken();
    _downloadCancelToken = cancelToken;

    try {
      await dio.download(
        uri.toString(),
        file.path,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
        onReceiveProgress: (count, total) {
          if (_cancelRequested) return;
          onProgress(count, total > 0 ? total : null);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      rethrow;
    } finally {
      _downloadCancelToken = null;
    }

    if (_cancelRequested) return;

    final len = await file.length();
    if (len <= 0) throw Exception('Downloaded apk file is empty');
  }

  Future<bool> _validateSha256(File file, String expectedHex) async {
    final normalized = expectedHex.toLowerCase();
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == normalized;
  }

  Future<void> _installNative({required String filePath}) async {
    await _nativeSub?.cancel();
    // Listen native events and parse them to installation progress
    _nativeSub = _native.installEvents.listen((event) {
      final controller = _controller;
      if (controller == null) return;
      if (event is Map) {
        final type = event['event'];
        if (type == 'failed') {
          controller.add(
            UpdateInstallationFailed(
              '${event['message'] ?? 'Native installation failed'}',
            ),
          );
        }
        // TODO обработать type installing с прогрессом
      }
    });

    await _native.installApk(filePath: filePath);
  }

  @override
  Future<void> confirmInstallation() async {
    if (_confirmCompleter == null) {
      throw Exception('No confirm completer to complete');
    }
    _confirmCompleter!.complete();
  }

  @override
  Future<void> cancelInstallation() async {
    _cancelRequested = true;
    _downloadCancelToken?.cancel('cancelledByUser');
    _confirmCompleter?.complete();
    await _native.cancelInstall();
  }

  Future<void> _cleanup() async {
    _downloadCancelToken?.cancel('cleanup');
    _downloadCancelToken = null;

    final controller = _controller;
    _controller = null;
    _confirmCompleter = null;
    _cancelRequested = false;

    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }
}
