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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Unit-тесты не поднимают реальные плагины, поэтому мокаем platform channels.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const apkInstallerChannel = MethodChannel('app_update_apk_installer/method');

  setUpAll(() {
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(apkInstallerChannel, (call) async {
          // В этом тесте мы отменяем установку ДО нативного installApk,
          // но cancelInstallation() всё равно вызывает 'cancel'.
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(apkInstallerChannel, null);
  });

  final dio =
      Dio()
        ..httpClientAdapter = _FakeApkHttpClientAdapter(
          bytes: List<int>.generate(256 * 1024, (i) => i % 256),
        );
  final mockUpdate = Update(
    version: Version(1, 2, 3),
    date: DateTime.utc(2025, 12, 26, 12),
    sourceName: UpdateSourceName.gitHub,
    // Apk installer ожидает android-апдейт (или any). Для теста задаём явно.
    platform: UpdatePlatform.android,
    rawContent: const UpdateContentData(
      updateUrl: 'https://example.com/test.apk',
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
      updateUrl: 'https://example.com/test.apk',
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
    const config = ApkUpdateInstallerConfig(fileName: 'test.apk');
    final stream = installer.install(mockUpdate, config);

    int numberOfEvent = 1;
    double lastProgress = 0;
    int numberOfDownloadedEvent = 0;
    final completer = Completer<void>();
    bool streamIsCompleted = false;
    stream.listen((event) {
      switch (event) {
        case UpdateInstallationStarted():
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
  });

  test('ApkUpdateInstaller confirm installation', () async {
    final installer = ApkUpdateInstaller(dio: dio);
    const config = ApkUpdateInstallerConfig(fileName: 'test.apk');
    final stream = installer.install(mockUpdate, config);

    int numberOfEvent = 1;
    double lastProgress = 0;
    bool isDownloadedEvent = false;
    bool isExecutingEvent = false;
    final completerDownloaded = Completer<void>();
    final completerCompleted = Completer<void>();
    stream.listen((event) {
      switch (event) {
        case UpdateInstallationStarted():
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
  });
}
