import 'package:app_update/app_update.dart';

import 'apk_update_installer_config.dart';

/// Parses config for ApkUpdateInstallerConfig.
///
/// Supported keys:
/// - file_name: String
/// - sha256: String
/// - require_user_confirm: bool
final class ApkUpdateInstallerConfigParser
    implements UpdateInstallerConfigParser {
  const ApkUpdateInstallerConfigParser();

  @override
  UpdateInstallerConfig parse(dynamic raw) {
    if (raw is! Map) {
      return const ApkUpdateInstallerConfig();
    }

    final fileName = raw['file_name'] as String?;
    final sha256 = raw['sha256'] as String?;
    final requireUserConfirm = raw['require_user_confirm'] as bool?;

    return ApkUpdateInstallerConfig(
      fileName: fileName,
      sha256: sha256,
      requireUserConfirm: requireUserConfirm,
    );
  }
}
