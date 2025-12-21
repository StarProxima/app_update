import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'app_update_apk_installer_method_channel.dart';

abstract class AppUpdateApkInstallerPlatform extends PlatformInterface {
  /// Constructs a AppUpdateApkInstallerPlatform.
  AppUpdateApkInstallerPlatform() : super(token: _token);

  static final Object _token = Object();

  static AppUpdateApkInstallerPlatform _instance = MethodChannelAppUpdateApkInstaller();

  /// The default instance of [AppUpdateApkInstallerPlatform] to use.
  ///
  /// Defaults to [MethodChannelAppUpdateApkInstaller].
  static AppUpdateApkInstallerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AppUpdateApkInstallerPlatform] when
  /// they register themselves.
  static set instance(AppUpdateApkInstallerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
