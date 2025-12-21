import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_update_apk_installer_platform_interface.dart';

/// An implementation of [AppUpdateApkInstallerPlatform] that uses method channels.
class MethodChannelAppUpdateApkInstaller extends AppUpdateApkInstallerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('app_update_apk_installer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
