import 'package:app_update/app_update.dart';

enum InAppUpdateType {
  immediate,
  flexible,
}

/// Configuration for [InAppUpdateInstaller].
final class InAppUpdateInstallerConfig extends UpdateInstallerConfig {
  static const installerName = 'in_app_update';

  /// Preferred update type. If null, installer chooses the best available.
  final InAppUpdateType? updateType;

  /// If true, flexible update waits for user confirmation before installation.
  final bool? requireUserConfirm;

  const InAppUpdateInstallerConfig({
    this.updateType,
    this.requireUserConfirm,
  }) : super(name: installerName);
}
