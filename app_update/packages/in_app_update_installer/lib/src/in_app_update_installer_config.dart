import 'package:app_update/app_update.dart';

import 'in_app_update_installer.dart';
import 'in_app_update_type.dart';

/// Configuration for [InAppUpdateInstaller].
final class InAppUpdateInstallerConfig extends UpdateInstallerConfig {
  static const installerName = 'in_app_update';

  /// Preferred update type. If null, installer chooses the best available.
  final InAppUpdateType? updateType;

  /// If true, flexible update waits for user confirmation before installation.
  final bool? requireUserConfirm;

  /// If true, installer can change update type if updateType from settings is not allowed.
  final bool? canChangeUpdateType;

  const InAppUpdateInstallerConfig({
    this.updateType,
    this.requireUserConfirm,
    this.canChangeUpdateType,
  }) : super(name: installerName);
}
