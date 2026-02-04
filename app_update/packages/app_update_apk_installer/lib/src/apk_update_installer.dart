// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:io';

import 'package:app_update/app_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'apk/apk_file_validator.dart';
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
  final ApkFileValidator _apkFileValidator = const ApkFileValidator();
  UpdateInstallationProgress _state = const UpdateInstallationInitialized();

  ApkUpdateInstaller({
    Dio? dio,
    this.requireUserConfirm = true,
    int apkDownloadRetryCount = 3,
  }) : dio = dio ?? Dio(),
       _apkDownloadRetryCount = apkDownloadRetryCount;

  StreamController<UpdateInstallationProgress>? _controller;
  StreamSubscription<UpdateInstallationProgress>? _stateSubscription;
  Completer<void>? _confirmCompleter;
  StreamSubscription<dynamic>? _nativeSub;
  CancelToken? _downloadCancelToken;
  bool _cancelRequested = false;
  final int _apkDownloadRetryCount;

  @override
  UpdateInstallerName get name => UpdateInstallerName.apkInstall;

  @override
  UpdateInstallationProgress get lastState => _state;

  @override
  UpdateInstallerConfigParser createConfigParser() =>
      const ApkUpdateInstallerConfigParser();

  @override
  bool canLaunch(UpdateData update) {
    // We only support Android runtime + android updates.
    if (!Platform.isAndroid) return false;
    if (update.platform != UpdatePlatform.android) return false;

    return true;
  }

  @override
  bool isHighestPriority(Update update) {
    // In app installer has higher priority than apk.
    if (update.sourceName == UpdateSourceName.googlePlay) return false;

    return true;
  }

  @override
  Stream<UpdateInstallationProgress> install(
    Update update,
    covariant ApkUpdateInstallerData data,
  ) {
    if (_controller != null) {
      return _controller!.stream;
    }

    final controller = StreamController<UpdateInstallationProgress>.broadcast();
    _controller = controller;
    _cancelRequested = false;

    _stateSubscription = controller.stream.listen((event) => _state = event);

    Future(() => _runPrepareApk(update, data));
    return controller.stream;
  }

  Future<void> _runPrepareApk(
    Update update,
    covariant ApkUpdateInstallerData data,
  ) async {
    final controller = _controller!;
    controller.add(const UpdateInstallationInitialized());

    final uri = data.apkUrl;
    if (!uri.toString().trim().endsWith('.apk')) {
      controller.add(
        const UpdateInstallationFailed('APK URL is not a valid APK URL'),
      );
      return;
    }

    try {
      final fileName =
          data.fileName ?? _inferFileName(uri: uri, update: update);
      final filePath = await _apkFilePath(fileName);
      final updateName = update.updateName;

      final file = File(filePath);
      final cacheFile = File('$filePath.$updateName.app_update.cache');
      var isCached = false;

      if (file.existsSync()) {
        await file.delete();
      }

      if (cacheFile.existsSync()) {
        // Use cache file
        await cacheFile.copy(file.path);
        isCached = true;
      } else {
        // Download apk file
        await _download(
          uri: uri,
          file: file,
          retryCount: _apkDownloadRetryCount,
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
      }

      if (_cancelRequested) {
        controller.add(const UpdateInstallationCancelled());
        await _cleanup();
        return;
      }

      // Validate that the downloaded file is an APK
      await _apkFileValidator.validateFormat(file);

      // Validate sha256 checksum
      final sha256 = data.sha256;
      if (sha256 != null) {
        await _apkFileValidator.validateSha256(file, sha256);
      }

      // Save cached file and delete old cache
      unawaited(_deleteOldCache(cacheFile.path));
      await file.copy(cacheFile.path);

      final isNeedConfirm = data.requireUserConfirm ?? requireUserConfirm;
      final size = await file.length();
      controller.add(
        UpdateInstallationDownloaded(
          downloadedUpdate: DownloadedUpdate(
            filePath: file.path,
            fileSize: size,
            metadata: {'url': uri.toString()},
            isCached: isCached,
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
      await _runInstallApk(controller: controller, filePath: file.path);
    } catch (e, s) {
      final message = switch (e) {
        DioException() => 'Download failed: ${e.message ?? e.error ?? e.type}',
        FileSystemException() => 'File error: ${e.message}',
        PlatformException() =>
          'Installation failed: ${e.code}${e.message != null ? ': ${e.message}' : ''}',
        FormatException() => 'APK file validation failed: ${e.message}',
        _ => 'APK installation failed',
      };
      controller.add(UpdateInstallationFailed(message, e, s));
    } finally {
      await _cleanup();
    }
  }

  String _inferFileName({required Uri uri, required Update update}) {
    if (uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return 'update_${update.updateName}.apk';
  }

  Future<String> _apkFilePath(String fileName) async {
    final tmpDir = await getTemporaryDirectory();
    final tmpDirPath = tmpDir.path + Platform.pathSeparator;

    return '$tmpDirPath$fileName';
  }

  /// Deletes all old cache files in background (fire-and-forget),
  Future<void> _deleteOldCache(String currentCacheFilePath) async {
    try {
      final current = File(currentCacheFilePath);
      final dir = current.parent;
      if (!dir.existsSync()) return;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;

        // Keep current cache, delete other installer caches.
        if (path == currentCacheFilePath) continue;
        if (!path.endsWith('.app_update.cache')) continue;

        try {
          await entity.delete();
        } catch (_) {
          // Ignore deletion errors, do not affect installation.
        }
      }
    } catch (_) {
      // Ignore any errors, do not affect installation.
    }
  }

  Future<void> _download({
    required Uri uri,
    required File file,
    required int retryCount,
    required void Function(int bytesDownloaded, int? totalBytes) onProgress,
  }) async {
    final cancelToken = CancelToken();
    _downloadCancelToken = cancelToken;

    const baseDelay = Duration(milliseconds: 500);

    try {
      for (var attempt = 1; attempt <= retryCount; attempt++) {
        if (_cancelRequested) return;

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
          return; // success
        } on DioException catch (e) {
          if (CancelToken.isCancel(e) || _cancelRequested) return;
          if (attempt == retryCount) rethrow;

          final statusCode = e.response?.statusCode;
          final isRetryable =
              statusCode == 408 ||
              statusCode == 429 ||
              (statusCode != null && statusCode >= 500);
          if (!isRetryable) rethrow;

          try {
            if (file.existsSync()) {
              await file.delete();
            }
          } catch (_) {}

          // Exponential backoff: 0.5s, 1s, 2s ...
          final delay = baseDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || _cancelRequested) return;
      rethrow;
    } finally {
      _downloadCancelToken = null;
    }
  }

  Future<void> _runInstallApk({
    required StreamController<UpdateInstallationProgress> controller,
    required String filePath,
  }) async {
    final installationStreamCompleter = Completer<void>();
    controller.add(const UpdateInstallationExecuting());

    _nativeSub = _native.installEvents.listen((event) {
      if (event is! Map) return;
      final map = Map<Object?, Object?>.from(event);
      final type = map['event'];
      if (type is! String) return;

      if (type == 'installing') {
        final p = map['progress'];
        if (p is num) {
          final progress = p.toDouble().clamp(0.0, 1.0);
          controller.add(UpdateInstallationExecuting(progress: progress));
        }
        return;
      } else if (type == 'completed') {
        installationStreamCompleter.complete();
        controller.add(const UpdateInstallationCompleted());
      } else if (type == 'cancelled') {
        installationStreamCompleter.complete();
        controller.add(const UpdateInstallationCancelled());
      } else if (type == 'failed') {
        final message =
            map['message']?.toString() ?? 'Native installation failed';
        final status = map['status']?.toString() ?? 'unknown';
        installationStreamCompleter.completeError(
          PlatformException(code: status, message: message),
        );
      }
    });

    // Start installation
    await _native.installApk(filePath: filePath);

    // Wait for installation to complete
    await installationStreamCompleter.future.timeout(
      const Duration(minutes: 5),
    );
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
    final cancelToken = _downloadCancelToken;
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('cleanup');
    }
    _downloadCancelToken = null;

    await _nativeSub?.cancel();
    _nativeSub = null;
    _confirmCompleter = null;
    _cancelRequested = false;

    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await _stateSubscription?.cancel();
      await controller.close();
    }
    _stateSubscription = null;
    _controller = null;
  }

  @override
  void dispose() {
    _cleanup();
    _native.cancelInstall();
    _nativeSub?.cancel();
    _nativeSub = null;
  }
}
