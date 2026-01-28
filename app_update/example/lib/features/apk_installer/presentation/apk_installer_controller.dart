import 'dart:async';
import 'dart:io';

import 'package:app_update/app_update.dart';
import 'package:app_update_apk_installer/app_update_apk_installer.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

// UI state
class ApkInstallerState {
  const ApkInstallerState({
    required this.requireConfirm,
    required this.logs,
    this.lastProgress,
  });

  final bool requireConfirm;
  final List<String> logs;
  final UpdateInstallationProgress? lastProgress;

  ApkInstallerState copyWith({
    bool? requireConfirm,
    List<String>? logs,
    UpdateInstallationProgress? lastProgress,
  }) {
    return ApkInstallerState(
      requireConfirm: requireConfirm ?? this.requireConfirm,
      logs: logs ?? this.logs,
      lastProgress: lastProgress ?? this.lastProgress,
    );
  }
}

class ApkInstallerController extends ValueNotifier<ApkInstallerState> {
  ApkInstallerController()
      : super(const ApkInstallerState(requireConfirm: true, logs: <String>[]));

  ApkUpdateInstaller? _installer;
  StreamSubscription<UpdateInstallationProgress>? _sub;

  /// Полностью пересоздает installer (new instance).
  /// Также отменяет текущую подписку на progress stream и сбрасывает lastProgress.
  Future<void> reloadInstaller() async {
    await _sub?.cancel();
    _sub = null;
    value = value.copyWith(lastProgress: null);

    _installer = ApkUpdateInstaller();
    _log('Installer reloaded');
  }

  void setRequireConfirm(bool requireConfirm) {
    value = value.copyWith(requireConfirm: requireConfirm);
  }

  Future<void> start({
    required String url,
    String? fileName,
    String? sha256,
  }) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      _log('URL is empty');
      return;
    }

    await _sub?.cancel();
    _sub = null;
    value = value.copyWith(lastProgress: null);

    _installer = _installer ?? ApkUpdateInstaller();

    final update = _buildFakeUpdate(normalizedUrl);
    final config = ApkUpdateInstallerConfig(
      apkUrl: Uri.parse(normalizedUrl),
      fileName: (fileName == null || fileName.isEmpty) ? null : fileName,
      sha256: (sha256 == null || sha256.isEmpty) ? null : sha256,
      requireUserConfirm: value.requireConfirm,
    );

    _log(
      'Starting install. url=$normalizedUrl requireConfirm=${value.requireConfirm}',
    );

    final stream = _installer!.install(update, config);
    _sub = stream.listen(
      (p) {
        value = value.copyWith(lastProgress: p);
        _log(p.runtimeType.toString());
        if (p is UpdateInstallationDownloading) {
          _log(
            'Downloading: ${(p.progress * 100).toStringAsFixed(1)}% '
            '${p.bytesDownloaded}/${p.totalBytes ?? '?'}',
          );
        } else if (p is UpdateInstallationDownloaded) {
          _log(
            'Downloaded: filePath=${p.downloadedUpdate.filePath} '
            'needConfirm=${p.isNeedConfirm}',
          );
        } else if (p is UpdateInstallationExecuting) {
          _log('Executing: ${((p.progress ?? 0) * 100).toStringAsFixed(1)}%');
        } else if (p is UpdateInstallationFailed) {
          _log(
            'Failed: ${p.message}, with error=${p.error} and stackTrace=${p.stackTrace}',
          );
        }
      },
      onError: (e, s) {
        _log('Stream error: $e');
        _log('$s');
      },
      onDone: () {
        _log('Stream done');
      },
    );
  }

  Future<void> confirm() async {
    final installer = _installer;
    if (installer == null) {
      _log('No active installer');
      return;
    }
    try {
      await installer.confirmInstallation();
      _log('confirmInstallation() called');
    } catch (e) {
      _log('confirmInstallation() error: $e');
    }
  }

  Future<void> cancel() async {
    final installer = _installer;
    if (installer == null) {
      _log('No active installer');
      return;
    }
    try {
      await installer.cancelInstallation();
      _log('cancelInstallation() called');
    } catch (e) {
      _log('cancelInstallation() error: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _log(String message) {
    final next = <String>[
      '[${DateTime.now().toIso8601String()}] $message',
      ...value.logs,
    ];
    value = value.copyWith(logs: next);
  }

  Update _buildFakeUpdate(String url) {
    const emptyCustom = <String, dynamic>{};

    final content = UpdateContentData(
      updateUrl: url,
      title: 'APK Installer Test',
      description: 'Manual installer test screen',
      releaseNotesTitle: 'Release notes',
      releaseNotes: null,
      skipButton: 'Skip',
      postponeButton: 'Later',
      updateButton: 'Install',
      customParams: emptyCustom,
    );

    const settings = UpdateSettingsData(
      shouldShow: true,
      canSkip: true,
      canPostpone: true,
      skipReleaseDelay: Duration(hours: 1),
      skipAllReleasesDelay: Duration(hours: 1),
      postponeReleaseDelay: Duration(minutes: 10),
      postponeAllReleasesDelay: Duration(minutes: 10),
      customParams: emptyCustom,
    );

    const appSettings = UpdateAppSettingsData(
      appStatus: AppStatus.outdated,
      customParams: emptyCustom,
    );

    return Update(
      version: Version.parse('999.0.0'),
      date: DateTime.now(),
      sourceName: UpdateSourceName.gitHub,
      platform: UpdatePlatform.android,
      rawContent: content,
      content: content,
      settings: settings,
      appSettings: appSettings,
      customParams: emptyCustom,
    );
  }

  /// Deletes backup file if it exists.
  ///
  /// Backup file name is the same as inside `ApkUpdateInstaller`:
  /// `$tmpDirPath$fileName.$updateName.app_update.backup`
  Future<void> clearBackup({
    required String url,
    String? fileName,
  }) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      _log('URL is empty');
      return;
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) {
      _log('Invalid URL: $normalizedUrl');
      return;
    }

    final update = _buildFakeUpdate(normalizedUrl);
    final inferFileName = (uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : 'update_${update.version}.apk';
    final effectiveFileName =
        (fileName == null || fileName.isEmpty) ? inferFileName : fileName;

    try {
      final tmpDir = await getTemporaryDirectory();
      final tmpDirPath = tmpDir.path + Platform.pathSeparator;
      final backupFile = File(
          '$tmpDirPath$effectiveFileName.${update.updateName}.app_update.backup');

      final exists = await backupFile.exists();
      if (!exists) {
        _log('Backup not found: ${backupFile.path}');
        return;
      }

      await backupFile.delete();
      _log('Backup deleted: ${backupFile.path}');
    } catch (e) {
      _log('Clear backup error: $e');
    }
  }
}
