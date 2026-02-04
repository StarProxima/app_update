import 'package:app_update/app_update.dart';

import 'in_app_update_installer.dart';
import 'in_app_update_type.dart';

const installerName = 'in_app_update';

/// Configuration for [InAppUpdateInstaller].
class InAppUpdateInstallerConfig extends UpdateInstallerConfig {
  final InAppUpdateType? updateType;
  final bool? requireUserConfirm;
  final bool? canChangeUpdateType;

  const InAppUpdateInstallerConfig({
    this.updateType,
    this.requireUserConfirm,
    this.canChangeUpdateType,
  }) : super(name: installerName);

  @override
  InAppUpdateInstallerConfig merge(covariant InAppUpdateInstallerConfig other) {
    return InAppUpdateInstallerConfig(
      updateType: other.updateType ?? updateType,
      requireUserConfirm: other.requireUserConfirm ?? requireUserConfirm,
      canChangeUpdateType: other.canChangeUpdateType ?? canChangeUpdateType,
    );
  }

  @override
  InAppUpdateInstallerData toData() => InAppUpdateInstallerData(
    updateType: updateType,
    requireUserConfirm: requireUserConfirm,
    canChangeUpdateType: canChangeUpdateType,
  );
}

class InAppUpdateInstallerData extends UpdateInstallerData {
  /// Preferred update type. If null, installer chooses the best available.
  final InAppUpdateType? updateType;

  /// If true, flexible update waits for user confirmation before installation.
  final bool? requireUserConfirm;

  /// If true, installer can change update type if updateType from settings is not allowed.
  final bool? canChangeUpdateType;

  InAppUpdateInstallerData({
    this.updateType,
    this.requireUserConfirm,
    this.canChangeUpdateType,
  }) : super(name: installerName);
}
