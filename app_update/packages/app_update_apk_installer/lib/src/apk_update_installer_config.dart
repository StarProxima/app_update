import 'package:app_update/app_update.dart';

/// Configuration for ApkUpdateInstaller.
///
/// This config is optional and can be provided later via YAML integration
/// (when UpdateController.installUpdate() starts passing installer configs).
final class ApkUpdateInstallerConfig extends UpdateInstallerConfig {
  static const installerName = 'apk_install';

  /// APK URL to download.
  final Uri apkUrl;

  /// Optional filename override.
  final String? fileName;

  /// Optional SHA-256 checksum (hex) to validate downloaded APK.
  final String? sha256;

  /// If true, ApkUpdateInstaller will emit [UpdateInstallationDownloaded]
  /// with [UpdateInstallationDownloaded.isNeedConfirm] = true and wait for
  /// UpdateController.confirmUpdateInstallation().
  final bool? requireUserConfirm;

  const ApkUpdateInstallerConfig({
    required this.apkUrl,
    this.fileName,
    this.sha256,
    this.requireUserConfirm,
  }) : super(name: installerName);

  @override
  ApkUpdateInstallerConfig merge(covariant ApkUpdateInstallerConfig other) =>
      ApkUpdateInstallerConfig(
        apkUrl: other.apkUrl,
        fileName: other.fileName ?? fileName,
        sha256: other.sha256 ?? sha256,
        requireUserConfirm: other.requireUserConfirm ?? requireUserConfirm,
      );
}
