// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:io';

import 'package:app_update/app_update.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';

import 'in_app_update_installer_config.dart';
import 'in_app_update_installer_config_parser.dart';
import 'in_app_update_type.dart';

/// Installer that uses Google Play In-App Updates on Android.
///
/// Supports immediate or flexible update flows.
final class InAppUpdateInstaller implements UpdateInstaller {
  final bool requireUserConfirm;
  final InAppUpdateType updateType;
  final bool canChangeUpdateType;

  InAppUpdateInstaller({
    this.requireUserConfirm = true,
    this.updateType = InAppUpdateType.flexible,
    this.canChangeUpdateType = true,
  });

  StreamController<UpdateInstallationProgress>? _controller;
  StreamSubscription<InstallStatus>? _installStatusSub;
  Completer<void>? _confirmCompleter;
  Completer<void>? _installedCompleter;
  bool _cancelRequested = false;

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

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateNotAvailable) {
        controller.add(
          const UpdateInstallationFailed('No update available via Google Play'),
        );
        await _cleanup();
        return;
      }

      final updateType = _resolveUpdateType(info, parsedConfig);
      if (updateType == InAppUpdateType.immediate) {
        await _runImmediateUpdate(controller, info);
      } else {
        await _runFlexibleUpdate(controller, info, parsedConfig);
      }
    } on PlatformException catch (e, s) {
      controller.add(
        UpdateInstallationFailed(
          'In-app update failed: ${e.code}${e.message != null ? ': ${e.message}' : ''}',
          e,
          s,
        ),
      );
    } catch (e, s) {
      controller.add(UpdateInstallationFailed('In-app update failed', e, s));
    } finally {
      await _cleanup();
    }
  }

  InAppUpdateType _resolveUpdateType(
    AppUpdateInfo info,
    InAppUpdateInstallerConfig config,
  ) {
    final requestedType = config.updateType ?? updateType;
    final otherType = requestedType.other;
    final canChangeUpdateType =
        config.canChangeUpdateType ?? this.canChangeUpdateType;

    final typeAllowed = {
      InAppUpdateType.immediate: info.immediateUpdateAllowed,
      InAppUpdateType.flexible: info.flexibleUpdateAllowed,
    };

    if (typeAllowed[requestedType]!) {
      return requestedType;
    } else if (canChangeUpdateType && typeAllowed[otherType]!) {
      return otherType;
    }

    throw StateError(
      'No allowed in-app update type with '
      'immediateAllowedPreconditions: ${info.immediateAllowedPreconditions?.join(', ')} '
      'and flexibleAllowedPreconditions: ${info.flexibleAllowedPreconditions?.join(', ')}',
    );
  }

  Future<void> _runImmediateUpdate(
    StreamController<UpdateInstallationProgress> controller,
    AppUpdateInfo info,
  ) async {
    if (_cancelRequested) {
      controller.add(const UpdateInstallationCancelled());
      return;
    }

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
    _installedCompleter = Completer<void>();
    final isNeedConfirm = config.requireUserConfirm ?? requireUserConfirm;

    if (_cancelRequested) {
      controller.add(const UpdateInstallationCancelled());
      return;
    }

    _installStatusSub = InAppUpdate.installUpdateListener.listen(
      (status) => _handleInstallStatus(controller, status, info, isNeedConfirm),
      onError: (error, stackTrace) {
        // TODO ошибку норм обработать
        var completer = _installedCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

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

    if (isNeedConfirm) {
      _confirmCompleter = Completer<void>();
      await _confirmCompleter!.future;
      _confirmCompleter = null;
    }

    if (_cancelRequested) {
      controller.add(const UpdateInstallationCancelled());
      return;
    }
    // TODO нужно ли ждать Downloaded? или можно дёрнуть заранее?
    await InAppUpdate.completeFlexibleUpdate();

    await _installedCompleter!.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () {
        controller.add(
          const UpdateInstallationFailed('In-app update timed out'),
        );
      },
    );
  }

  void _handleInstallStatus(
    StreamController<UpdateInstallationProgress> controller,
    InstallStatus status,
    AppUpdateInfo info,
    bool isNeedConfirm,
  ) {
    switch (status) {
      case InstallStatus.pending:
      case InstallStatus.downloading:
        controller.add(const UpdateInstallationDownloading());
      case InstallStatus.downloaded:
        controller.add(_createDownloadedStatus(info, isNeedConfirm));
      case InstallStatus.installing:
        controller.add(const UpdateInstallationExecuting());
      case InstallStatus.installed:
        controller.add(const UpdateInstallationCompleted());
      case InstallStatus.failed:
        controller.add(const UpdateInstallationFailed('In-app update failed'));
        // TODO ошибку норм обработать
        final completer = _installedCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(StateError('In-app update failed'));
        }
      case InstallStatus.canceled:
        controller.add(const UpdateInstallationCancelled());
        // TODO ошибку норм обработать
        final completer = _installedCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      case InstallStatus.unknown:
        break;
    }
  }

  UpdateInstallationDownloaded _createDownloadedStatus(
    AppUpdateInfo info,
    bool isNeedConfirm,
  ) => UpdateInstallationDownloaded(
    downloadedUpdate: DownloadedUpdate(
      isBackup: false,
      metadata: {
        'packageName': info.packageName,
        'availableVersionCode': info.availableVersionCode,
        'clientVersionStalenessDays': info.clientVersionStalenessDays,
        'updatePriority': info.updatePriority,
      },
    ),
    isNeedConfirm: isNeedConfirm,
  );

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
