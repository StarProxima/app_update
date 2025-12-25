import 'dart:async';

import 'package:flutter/services.dart';

import '../../app_update_apk_installer.dart';

/// Low-level platform API used by [ApkUpdateInstaller].
final class ApkInstallerNative {
  static const MethodChannel _method = MethodChannel(
    'app_update_apk_installer/method',
  );
  static const EventChannel _events = EventChannel(
    'app_update_apk_installer/events',
  );

  Stream<dynamic>? _cachedStream;

  Stream<dynamic> get installEvents =>
      _cachedStream ??= _events.receiveBroadcastStream();

  Future<void> installApk({required String filePath}) async {
    await _method.invokeMethod<void>('installApk', {'filePath': filePath});
  }

  Future<void> cancelInstall() async {
    await _method.invokeMethod<void>('cancel');
  }
}
