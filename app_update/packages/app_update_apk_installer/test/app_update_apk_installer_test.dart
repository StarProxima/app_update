import 'package:flutter_test/flutter_test.dart';
import 'package:app_update_apk_installer/app_update_apk_installer.dart';
import 'package:app_update_apk_installer/app_update_apk_installer_platform_interface.dart';
import 'package:app_update_apk_installer/app_update_apk_installer_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAppUpdateApkInstallerPlatform
    with MockPlatformInterfaceMixin
    implements AppUpdateApkInstallerPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final AppUpdateApkInstallerPlatform initialPlatform = AppUpdateApkInstallerPlatform.instance;

  test('$MethodChannelAppUpdateApkInstaller is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAppUpdateApkInstaller>());
  });

  test('getPlatformVersion', () async {
    AppUpdateApkInstaller appUpdateApkInstallerPlugin = AppUpdateApkInstaller();
    MockAppUpdateApkInstallerPlatform fakePlatform = MockAppUpdateApkInstallerPlatform();
    AppUpdateApkInstallerPlatform.instance = fakePlatform;

    expect(await appUpdateApkInstallerPlugin.getPlatformVersion(), '42');
  });
}
