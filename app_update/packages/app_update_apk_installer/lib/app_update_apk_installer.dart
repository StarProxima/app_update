
import 'app_update_apk_installer_platform_interface.dart';

class AppUpdateApkInstaller {
  Future<String?> getPlatformVersion() {
    return AppUpdateApkInstallerPlatform.instance.getPlatformVersion();
  }
}
