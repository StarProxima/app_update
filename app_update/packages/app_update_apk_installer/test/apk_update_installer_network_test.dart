import 'dart:async';
import 'dart:io';

import 'package:app_update/app_update.dart';
import 'package:app_update_apk_installer/app_update_apk_installer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

void main() {
  // Needed for MethodChannel mocks (path_provider + plugin channel).
  TestWidgetsFlutterBinding.ensureInitialized();

  // TODO заменить на url из app_update
  const url =
      'https://github.com/iamgirya/junk/raw/refs/heads/main/app_update_example.apk';

  // Unit/widget tests override HttpClient to return 400 (no real network).
  // For this *explicit* network test we temporarily disable that override.
  late final HttpOverrides? prevHttpOverrides;

  // Unit-тесты не поднимают реальные плагины, поэтому мокаем platform channels.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const apkInstallerChannel = MethodChannel('app_update_apk_installer/method');

  setUpAll(() {
    prevHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          switch (call.method) {
            case 'getTemporaryDirectory':
            case 'getTemporaryPath':
              return Directory.systemTemp.path;
            default:
              debugPrint('Unexpected method call: ${call.method}');
              return Directory.systemTemp.path;
          }
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(apkInstallerChannel, (call) async {
          // cancelInstallation() calls 'cancel'. We cancel during download,
          // so installApk should never happen, but keep it harmless anyway.
          switch (call.method) {
            case 'cancel':
            case 'installApk':
              return null;
            default:
              debugPrint('Unexpected method call: ${call.method}');
              return null;
          }
        });
  });

  tearDownAll(() async {
    HttpOverrides.global = prevHttpOverrides;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(apkInstallerChannel, null);
  });

  test('ApkUpdateInstaller with real network and sha256 validation', () async {
    final mockUpdate = Update(
      version: Version(1, 2, 3),
      date: DateTime.utc(2025, 12, 26, 12),
      sourceName: UpdateSourceName.gitHub,
      platform: UpdatePlatform.android,
      rawContent: const UpdateContentData(
        updateUrl: url,
        title: 'Update available: v1.2.3',
        description: 'Network test download.',
        releaseNotesTitle: 'What’s new',
        releaseNotes: 'Network download test.\nURL: $url',
        skipButton: 'Skip',
        postponeButton: 'Later',
        updateButton: 'Update',
        customParams: {'network_test': true},
      ),
      content: const UpdateContentData(
        updateUrl: url,
        title: 'Update available: v1.2.3',
        description: 'Network test download.',
        releaseNotesTitle: 'What’s new',
        releaseNotes: 'Network download test.\nURL: $url',
        skipButton: 'Skip',
        postponeButton: 'Later',
        updateButton: 'Update',
        customParams: {'network_test': true},
      ),
      settings: const UpdateSettingsData(
        shouldShow: true,
        canSkip: true,
        canPostpone: true,
        skipReleaseDelay: Duration(days: 7),
        skipAllReleasesDelay: Duration(days: 30),
        postponeReleaseDelay: Duration(hours: 8),
        postponeAllReleasesDelay: Duration(days: 1),
        installers: {},
        customParams: null,
      ),
      appSettings: const UpdateAppSettingsData(
        appStatus: AppStatus.active,
        customParams: null,
      ),
      customParams: {'os': Platform.operatingSystem},
    );

    final installer = ApkUpdateInstaller();
    final data = ApkUpdateInstallerData(
      apkUrl: Uri.parse(url),
      fileName: 'network_test.apk',
      sha256:
          '3f0c2ecac8d7bce683b69fe5b34f2449fcb4dd8d174bf786679d5346071fb476',
    );
    final stream = installer.install(mockUpdate, data);

    final cancelled = Completer<void>();
    bool sawDownloading = false;
    bool sawDownloaded = false;
    final sub = stream.listen((event) async {
      switch (event) {
        case UpdateInstallationDownloading():
          expect(sawDownloaded, isFalse);
          sawDownloading = true;
        case UpdateInstallationDownloaded(
          :final isNeedConfirm,
          :final downloadedUpdate,
        ):
          if (downloadedUpdate.isCached) {
            expect(sawDownloading, isFalse);
            sawDownloading = true;
          } else {
            expect(sawDownloading, isTrue);
          }
          expect(sawDownloaded, isFalse);
          sawDownloaded = true;
          debugPrint('downloadedUpdate filePath: ${downloadedUpdate.filePath}');

          expect(isNeedConfirm, isTrue);
          expect(downloadedUpdate.filePath, endsWith('network_test.apk'));
          expect(downloadedUpdate.fileSize, greaterThan(0));
          expect(downloadedUpdate.metadata, {'url': url});

          await installer.cancelInstallation();
        case UpdateInstallationCancelled():
          expect(sawDownloading, isTrue);
          expect(sawDownloaded, isTrue);
          cancelled.complete();
        case UpdateInstallationFailed(:final message):
          fail(
            'UpdateInstallationFailed by: $message '
            'with error: ${event.error} and stackTrace: ${event.stackTrace}',
          );
        case UpdateInstallationCompleted():
          fail('UpdateInstallationCompleted? Why?');
        default:
          // ignore other events for this test
          break;
      }
    });

    await cancelled.future.timeout(const Duration(minutes: 3));
    await sub.cancel();
  });
}
