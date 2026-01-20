// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:io';

import 'package:app_update/app_update.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';

import 'in_app_update_installer_config.dart';
import 'in_app_update_installer_config_parser.dart';

/// Installer that uses Google Play In-App Updates on Android.
///
/// Supports immediate or flexible update flows.
final class InAppUpdateInstaller implements UpdateInstaller {
  final bool requireUserConfirm;

  InAppUpdateInstaller({
    this.requireUserConfirm = true,
  });

  StreamController<UpdateInstallationProgress>? _controller;
  StreamSubscription<InstallStatus>? _installStatusSub;
  Completer<void>? _confirmCompleter;
  Completer<void>? _downloadedCompleter;
  Completer<void>? _installedCompleter;

  bool _cancelRequested = false;
  bool _downloadedEmitted = false;
  bool _executingEmitted = false;
  bool _completedEmitted = false;

  @override
  UpdateInstallerName get name => UpdateInstallerName.inAppUpdate;

  @override
  UpdateInstallerConfigParser createConfigParser() =>
      const InAppUpdateInstallerConfigParser();

  @override
  bool supports(Update update) {
    if (!Platform.isAndroid) return false;
    if (update.platform != UpdatePlatform.android &&
        update.platform != UpdatePlatform.any) {
      return false;
    }
    return update.sourceName == UpdateSourceName.googlePlay;
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
    _downloadedEmitted = false;
    _executingEmitted = false;
    _completedEmitted = false;

    unawaited(Future(() => _run(update, config)));
    return _controller!.stream;
  }

  Future<void> _run(Update update, UpdateInstallerConfig? config) async {
    final controller = _controller!;
    controller.add(const UpdateInstallationStarted());

    final parsedConfig = switch (config) {
      null => const InAppUpdateInstallerConfig(),
      InAppUpdateInstallerConfig() => config,
      _ => throw ArgumentError('Config is not InAppUpdateInstallerConfig'),
    };

    if (!Platform.isAndroid) {
      controller.add(
        const UpdateInstallationFailed('In-app update is Android-only'),
      );
      await _cleanup();
      return;
    }

    if (update.platform != UpdatePlatform.android &&
        update.platform != UpdatePlatform.any) {
      controller.add(
        const UpdateInstallationFailed('Update platform is not Android'),
      );
      await _cleanup();
      return;
    }

    if (update.sourceName != UpdateSourceName.googlePlay) {
      controller.add(
        const UpdateInstallationFailed(
          'In-app update requires Google Play source',
        ),
      );
      await _cleanup();
      return;
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateNotAvailable) {
        controller.add(
          const UpdateInstallationFailed(
            'No update available via Google Play',
          ),
        );
        await _cleanup();
        return;
      }

      final updateType = _resolveUpdateType(info, parsedConfig);
      if (updateType == InAppUpdateType.immediate) {
        await _runImmediateUpdate(controller, info);
        await _cleanup();
        return;
      }

      await _runFlexibleUpdate(controller, info, parsedConfig);
      await _cleanup();
    } on PlatformException catch (e, s) {
      controller.add(
        UpdateInstallationFailed(
          'In-app update failed: ${e.code}${e.message != null ? ': ${e.message}' : ''}',
          e,
          s,
        ),
      );
      await _cleanup();
    } catch (e, s) {
      controller.add(
        UpdateInstallationFailed('In-app update failed', e, s),
      );
      await _cleanup();
    }
  }

  InAppUpdateType _resolveUpdateType(
    AppUpdateInfo info,
    InAppUpdateInstallerConfig config,
  ) {
    final requested = config.updateType;
    if (requested == InAppUpdateType.immediate) {
      if (!info.immediateUpdateAllowed) {
        throw StateError('Immediate update is not allowed');
      }
      return InAppUpdateType.immediate;
    }

    if (requested == InAppUpdateType.flexible) {
      if (!info.flexibleUpdateAllowed) {
        throw StateError('Flexible update is not allowed');
      }
      return InAppUpdateType.flexible;
    }

    if (info.flexibleUpdateAllowed) return InAppUpdateType.flexible;
    if (info.immediateUpdateAllowed) return InAppUpdateType.immediate;

    throw StateError('No allowed in-app update type');
  }

  Future<void> _runImmediateUpdate(
    StreamController<UpdateInstallationProgress> controller,
    AppUpdateInfo info,
  ) async {
    controller.add(const UpdateInstallationExecuting());
    final result = await InAppUpdate.performImmediateUpdate();
    switch (result) {
      case AppUpdateResult.success:
        controller.add(const UpdateInstallationCompleted());
      case AppUpdateResult.userDeniedUpdate:
        controller.add(const UpdateInstallationCancelled());
      case AppUpdateResult.inAppUpdateFailed:
        controller.add(
          const UpdateInstallationFailed('In-app immediate update failed'),
        );
    }
  }

  Future<void> _runFlexibleUpdate(
    StreamController<UpdateInstallationProgress> controller,
    AppUpdateInfo info,
    InAppUpdateInstallerConfig config,
  ) async {
    _downloadedCompleter = Completer<void>();
    _installedCompleter = Completer<void>();

    _installStatusSub = InAppUpdate.installUpdateListener.listen(
      (status) {
        _handleInstallStatus(controller, status, info, config);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_completedEmitted) return;
        controller.add(
          UpdateInstallationFailed('In-app update status error', error),
        );
        final completer = _installedCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    if (info.installStatus == InstallStatus.downloaded) {
      _emitDownloaded(controller, info, config);
      final completer = _downloadedCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }

    final startResult = await InAppUpdate.startFlexibleUpdate();
    switch (startResult) {
      case AppUpdateResult.success:
        break;
      case AppUpdateResult.userDeniedUpdate:
        controller.add(const UpdateInstallationCancelled());
        return;
      case AppUpdateResult.inAppUpdateFailed:
        controller.add(
          const UpdateInstallationFailed('In-app flexible update failed'),
        );
        return;
    }

    await _downloadedCompleter!.future;
    if (_cancelRequested) {
      controller.add(const UpdateInstallationCancelled());
      return;
    }

    final isNeedConfirm = config.requireUserConfirm ?? requireUserConfirm;
    if (isNeedConfirm) {
      _confirmCompleter = Completer<void>();
      await _confirmCompleter!.future;
      _confirmCompleter = null;
    }

    if (_cancelRequested) {
      controller.add(const UpdateInstallationCancelled());
      return;
    }

    if (!_executingEmitted) {
      controller.add(const UpdateInstallationExecuting());
      _executingEmitted = true;
    }

    await InAppUpdate.completeFlexibleUpdate();

    await _installedCompleter!.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () {
        if (!_completedEmitted) {
          controller.add(
            const UpdateInstallationFailed('In-app update timed out'),
          );
          _completedEmitted = true;
        }
      },
    );
  }

  void _handleInstallStatus(
    StreamController<UpdateInstallationProgress> controller,
    InstallStatus status,
    AppUpdateInfo info,
    InAppUpdateInstallerConfig config,
  ) {
    if (_completedEmitted) return;

    switch (status) {
      case InstallStatus.pending:
      case InstallStatus.downloading:
        controller.add(
          const UpdateInstallationDownloading(
            progress: 0.0,
            bytesDownloaded: 0,
            totalBytes: null,
          ),
        );
      case InstallStatus.downloaded:
        _emitDownloaded(controller, info, config);
        final completer = _downloadedCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      case InstallStatus.installing:
        if (!_executingEmitted) {
          controller.add(const UpdateInstallationExecuting());
          _executingEmitted = true;
        }
      case InstallStatus.installed:
        if (!_completedEmitted) {
          controller.add(const UpdateInstallationCompleted());
          _completedEmitted = true;
        }
        final completer = _installedCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      case InstallStatus.failed:
        if (!_completedEmitted) {
          controller.add(
            const UpdateInstallationFailed('In-app update failed'),
          );
          _completedEmitted = true;
        }
        final completer = _installedCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(StateError('In-app update failed'));
        }
      case InstallStatus.canceled:
        if (!_completedEmitted) {
          controller.add(const UpdateInstallationCancelled());
          _completedEmitted = true;
        }
        final completer = _installedCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      case InstallStatus.unknown:
        break;
    }
  }

  void _emitDownloaded(
    StreamController<UpdateInstallationProgress> controller,
    AppUpdateInfo info,
    InAppUpdateInstallerConfig config,
  ) {
    if (_downloadedEmitted) return;
    _downloadedEmitted = true;

    final isNeedConfirm = config.requireUserConfirm ?? requireUserConfirm;
    controller.add(
      UpdateInstallationDownloaded(
        downloadedUpdate: DownloadedUpdate(
          isBackup: false,
          metadata: {
            'packageName': info.packageName,
            'availableVersionCode': info.availableVersionCode,
            'updatePriority': info.updatePriority,
          },
        ),
        isNeedConfirm: isNeedConfirm,
      ),
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
    _confirmCompleter?.complete();
  }

  Future<void> _cleanup() async {
    await _installStatusSub?.cancel();
    _installStatusSub = null;

    _confirmCompleter = null;
    _downloadedCompleter = null;
    _installedCompleter = null;
    _cancelRequested = false;

    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _controller = null;
  }

  @override
  void dispose() {
    _cleanup();
  }
}
