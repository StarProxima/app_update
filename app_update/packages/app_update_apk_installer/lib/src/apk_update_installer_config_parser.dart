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

  static const _boolParser = BoolParser();
  static const _stringParser = StringParser();
  static const _uriParser = UriParser();

  @override
  UpdateInstallerConfig parse(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw ParseConfigException.wrongType(
        rightType: Map<String, dynamic>,
        wrongType: raw.runtimeType,
        parserType: ApkUpdateInstallerConfigParser,
        configs: [raw],
      );
    }

    final apkUrl = _uriParser.parse(raw['apk_url']);
    if (apkUrl == null) {
      throw ParseConfigException.requiredParams(
        params: ['apk_url'],
        parserType: ApkUpdateInstallerConfigParser,
        configs: [raw],
      );
    }

    final fileName = _stringParser.parse(raw['file_name']);
    final sha256 = _stringParser.parse(raw['sha256']);
    final requireUserConfirm = _boolParser.parse(raw['require_user_confirm']);

    return ApkUpdateInstallerConfig(
      apkUrl: apkUrl,
      fileName: fileName,
      sha256: sha256,
      requireUserConfirm: requireUserConfirm,
    );
  }
}
