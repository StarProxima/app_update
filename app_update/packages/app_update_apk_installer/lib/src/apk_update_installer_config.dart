import 'package:app_update/app_update.dart';

const installerName = 'apk_install';

/// Configuration for ApkUpdateInstaller.
final class ApkUpdateInstallerConfig extends UpdateInstallerConfig {
  final Uri? apkUrl;
  final String? fileName;
  final String? sha256;
  final bool? requireUserConfirm;

  const ApkUpdateInstallerConfig({
    this.apkUrl,
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

  @override
  ApkUpdateInstallerData toData() => ApkUpdateInstallerData(
    apkUrl: apkUrl ?? (throw ArgumentError('apkUrl is required')),
    fileName: fileName,
    sha256: sha256,
    requireUserConfirm: requireUserConfirm,
  );
}

/// Data for ApkUpdateInstaller.
final class ApkUpdateInstallerData extends UpdateInstallerData {
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

  ApkUpdateInstallerData({
    required this.apkUrl,
    this.fileName,
    this.sha256,
    this.requireUserConfirm,
  }) : super(name: installerName);
}
