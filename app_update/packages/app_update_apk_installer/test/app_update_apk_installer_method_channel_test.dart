import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_update_apk_installer/app_update_apk_installer_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelAppUpdateApkInstaller platform = MethodChannelAppUpdateApkInstaller();
  const MethodChannel channel = MethodChannel('app_update_apk_installer');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
