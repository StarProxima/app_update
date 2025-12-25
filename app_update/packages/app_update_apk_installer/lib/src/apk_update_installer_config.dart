import 'package:app_update/app_update.dart';

/// Configuration for ApkUpdateInstaller.
///
/// This config is optional and can be provided later via YAML integration
/// (when UpdateController.installUpdate() starts passing installer configs).
final class ApkUpdateInstallerConfig extends UpdateInstallerConfig {
  static const installerName = 'apk_install';

  /// Optional filename override (without directories).
  final String? fileName;

  /// Optional SHA-256 checksum (hex) to validate downloaded APK.
  final String? sha256;

  /// If true, ApkUpdateInstaller will emit [UpdateInstallationDownloaded]
  /// with [UpdateInstallationDownloaded.isNeedConfirm] = true and wait for
  /// UpdateController.confirmUpdateInstallation().
  final bool? requireUserConfirm;

  const ApkUpdateInstallerConfig({
    this.fileName,
    this.sha256,
    this.requireUserConfirm,
  }) : super(name: installerName);
}
