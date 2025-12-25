import 'package:app_update_apk_installer/app_update_apk_installer.dart';
import 'package:app_update_apk_installer/src/apk_update_installer_config_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ApkUpdateInstallerConfigParser parses map', () {
    const parser = ApkUpdateInstallerConfigParser();
    final cfg =
        parser.parse({
              'file_name': 'my.apk',
              'sha256': 'abc',
              'require_user_confirm': false,
            })
            as ApkUpdateInstallerConfig;

    expect(cfg.fileName, 'my.apk');
    expect(cfg.sha256, 'abc');
    expect(cfg.requireUserConfirm, isFalse);
  });

  test('ApkUpdateInstallerConfigParser handles non-map', () {
    const parser = ApkUpdateInstallerConfigParser();
    final cfg = parser.parse('nope') as ApkUpdateInstallerConfig;
    expect(cfg.fileName, isNull);
    expect(cfg.sha256, isNull);
    expect(cfg.requireUserConfirm, isTrue);
  });
}
