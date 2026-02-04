import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:app_update/app_update.dart';
import 'package:app_update_apk_installer/app_update_apk_installer.dart';
import 'package:app_update_apk_installer/src/apk_update_installer_config_parser.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

final class _FakeApkHttpClientAdapter implements HttpClientAdapter {
  final List<int> bytes;
  final int _statusCode;
  final int _chunkSize;

  _FakeApkHttpClientAdapter({
    required this.bytes,
    int statusCode = 200,
    int chunkSize = 64 * 1024,
  }) : _statusCode = statusCode,
       _chunkSize = chunkSize;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    debugPrint('Mocked fetch: ${options.uri}');
    final total = bytes.length;
    final chunks = <Uint8List>[];
    for (var i = 0; i < total; i += _chunkSize) {
      final end = min(i + _chunkSize, total);
      chunks.add(Uint8List.fromList(bytes.sublist(i, end)));
    }

    final stream = Stream<Uint8List>.fromIterable(chunks);
    return ResponseBody(
      stream,
      _statusCode,
      headers: {
        Headers.contentLengthHeader: [total.toString()],
        Headers.contentTypeHeader: ['application/vnd.android.package-archive'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const testApkUrl = 'https://example.com/test.apk';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Unit-тесты не поднимают реальные плагины, поэтому мокаем platform channels.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const apkInstallerChannel = MethodChannel('app_update_apk_installer/method');
  const apkInstallerEventsChannel = MethodChannel(
    'app_update_apk_installer/events',
  );
  const eventCodec = StandardMethodCodec();

  setUpAll(() {
    void emitNativeEvent(Map<String, Object?> event) {
      final data = eventCodec.encodeSuccessEnvelope(event);
      ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'app_update_apk_installer/events',
        data,
        (_) {},
      );
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          // path_provider ожидает string path.
          switch (call.method) {
            case 'getTemporaryDirectory':
            case 'getTemporaryPath':
              return Directory.systemTemp.path;
            default:
              debugPrint('Unexpected method call: ${call.method}');
              return Directory.systemTemp.path;
          }
        });

    // EventChannel handshake for ApkInstallerNative.installEvents.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(apkInstallerEventsChannel, (call) async {
          switch (call.method) {
            case 'listen':
            case 'cancel':
              return null;
            default:
              debugPrint('Unexpected event channel call: ${call.method}');
              return null;
          }
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(apkInstallerChannel, (call) async {
          // В этом тесте мы отменяем установку ДО нативного installApk,
          // но cancelInstallation() всё равно вызывает 'cancel'.
          switch (call.method) {
            case 'cancel':
              emitNativeEvent(<String, Object?>{'event': 'cancelled'});
              return null;
            case 'installApk':
              await Future.delayed(const Duration(seconds: 10));
              emitNativeEvent(<String, Object?>{'event': 'completed'});
              return null;
            default:
              debugPrint('Unexpected method call: ${call.method}');
              return null;
          }
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(apkInstallerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(apkInstallerEventsChannel, null);

    // Cleanup temp APKs/caches produced by tests (best-effort).
    final dir = Directory.systemTemp;
    if (dir.existsSync()) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        final isTestApk = path.endsWith('${Platform.pathSeparator}test.apk');
        final isInstallerCache =
            path.endsWith('.app_update.cache') && path.contains('test.apk.');

        if (!isTestApk && !isInstallerCache) continue;

        try {
          await entity.delete();
        } catch (_) {
          // ignore
        }
      }
    }
  });

  final fakeApkBytes =
      List<int>.generate(256 * 1024, (i) => i % 256)
        ..[0] = 0x50
        ..[1] = 0x4B; // 'PK' (ZIP/APK signature)

  final dio =
      Dio()..httpClientAdapter = _FakeApkHttpClientAdapter(bytes: fakeApkBytes);
  final mockUpdate = Update(
    version: Version(1, 2, 3),
    date: DateTime.utc(2025, 12, 26, 12),
    sourceName: UpdateSourceName.gitHub,
    // Apk installer ожидает android-апдейт (или any). Для теста задаём явно.
    platform: UpdatePlatform.android,
    rawContent: const UpdateContentData(
      updateUrl: testApkUrl,
      title: 'Update available: v1.2.3',
      description: 'Bug fixes and performance improvements.',
      releaseNotesTitle: 'What’s new',
      releaseNotes: '- Fixed crashes\n- Improved startup time',
      skipButton: 'Skip',
      postponeButton: 'Later',
      updateButton: 'Update',
      customParams: {'raw': true},
    ),
    content: const UpdateContentData(
      updateUrl: testApkUrl,
      title: 'Update available: v1.2.3',
      description: 'Bug fixes and performance improvements.',
      releaseNotesTitle: 'What’s new',
      releaseNotes: '- Fixed crashes\n- Improved startup time',
      skipButton: 'Skip',
      postponeButton: 'Later',
      updateButton: 'Update',
      customParams: {'utm_campaign': 'test', 'channel': 'beta'},
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
      customParams: {'priority': 'recommended'},
    ),
    appSettings: const UpdateAppSettingsData(
      appStatus: AppStatus.active,
      customParams: {'build': 12345},
    ),
    customParams: {'request_id': 'test-req-1', 'os': Platform.operatingSystem},
  );

  test('ApkUpdateInstallerConfigParser parses map', () {
    const parser = ApkUpdateInstallerConfigParser();
    final cfg =
        parser.parse({
              'apk_url': testApkUrl,
              'file_name': 'my.apk',
              'sha256': 'abc',
              'require_user_confirm': false,
            })
            as ApkUpdateInstallerConfig;

    expect(cfg.fileName, 'my.apk');
    expect(cfg.sha256, 'abc');
    expect(cfg.requireUserConfirm, isFalse);
  });

  test('ApkUpdateInstaller can cancel installation', () async {
    final installer = ApkUpdateInstaller(dio: dio);
    final data = ApkUpdateInstallerData(
      apkUrl: Uri.parse(testApkUrl),
      fileName: 'test.apk',
    );
    final stream = installer.install(mockUpdate, data);

    int numberOfEvent = 1;
    double lastProgress = 0;
    int numberOfDownloadedEvent = 0;
    final completer = Completer<void>();
    bool streamIsCompleted = false;
    final sub = stream.listen((event) {
      switch (event) {
        case UpdateInstallationInitialized():
          expect(numberOfEvent, equals(1));
        case UpdateInstallationDownloading(:final progress):
          expect(progress, greaterThanOrEqualTo(lastProgress));
          expect(progress, lessThanOrEqualTo(1.0));
          expect(numberOfEvent, greaterThan(1));
          lastProgress = progress;
        case UpdateInstallationDownloaded(
          :final downloadedUpdate,
          :final isNeedConfirm,
        ):
          debugPrint('downloadedUpdate.filePath: ${downloadedUpdate.filePath}');
          expect(downloadedUpdate.filePath, endsWith('test.apk'));
          expect(isNeedConfirm, isTrue);
          numberOfDownloadedEvent = numberOfEvent;
          completer.complete();
        case UpdateInstallationCancelled():
          expect(numberOfEvent, equals(numberOfDownloadedEvent + 1));
          streamIsCompleted = true;
        case UpdateInstallationFailed(:final message):
          fail(
            'UpdateInstallationFailed by: $message with error: ${event.error} and stackTrace: ${event.stackTrace}',
          );
        default:
          fail('Unexpected event: $event');
      }

      numberOfEvent++;
    });

    // ожидаем загрузки файла
    await completer.future.timeout(const Duration(minutes: 1));

    // отменяем установку
    await installer.cancelInstallation();
    await Future.delayed(const Duration(seconds: 1));
    expect(streamIsCompleted, isTrue);
    await sub.cancel();
  });

  test('ApkUpdateInstaller confirm installation', () async {
    final installer = ApkUpdateInstaller(dio: dio);
    final data = ApkUpdateInstallerData(
      apkUrl: Uri.parse(testApkUrl),
      fileName: 'test.apk',
    );
    final stream = installer.install(mockUpdate, data);

    int numberOfEvent = 1;
    double lastProgress = 0;
    bool isDownloadedEvent = false;
    bool isExecutingEvent = false;
    final completerDownloaded = Completer<void>();
    final completerCompleted = Completer<void>();
    final sub = stream.listen((event) {
      switch (event) {
        case UpdateInstallationInitialized():
          expect(numberOfEvent, equals(1));
        case UpdateInstallationDownloading(:final progress):
          expect(progress, greaterThanOrEqualTo(lastProgress));
          expect(progress, lessThanOrEqualTo(1.0));
          expect(numberOfEvent, greaterThan(1));
          lastProgress = progress;
        case UpdateInstallationDownloaded(
          :final downloadedUpdate,
          :final isNeedConfirm,
        ):
          debugPrint('downloadedUpdate.filePath: ${downloadedUpdate.filePath}');
          expect(downloadedUpdate.filePath, endsWith('test.apk'));
          expect(isNeedConfirm, isTrue);
          isDownloadedEvent = true;
          completerDownloaded.complete();
        case UpdateInstallationExecuting(:final progress):
          expect(isDownloadedEvent, isTrue);
          expect(isExecutingEvent, isFalse);
          expect(progress, isNull);
          isExecutingEvent = true;
        case UpdateInstallationCompleted():
          expect(isDownloadedEvent, isTrue);
          expect(isExecutingEvent, isTrue);
          completerCompleted.complete();
        case UpdateInstallationCancelled():
          fail('UpdateInstallationCancelled? Why?');
        case UpdateInstallationFailed(:final message):
          fail(
            'UpdateInstallationFailed by: $message with error: ${event.error} and stackTrace: ${event.stackTrace}',
          );
      }

      numberOfEvent++;
    });

    // ожидаем загрузки файла
    await completerDownloaded.future.timeout(const Duration(minutes: 1));

    // подтверждаем установку
    await installer.confirmInstallation();

    // ожидаем установки
    await completerCompleted.future.timeout(const Duration(minutes: 1));
    await sub.cancel();
  });
}
