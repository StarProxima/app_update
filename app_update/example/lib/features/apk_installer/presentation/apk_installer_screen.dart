import 'dart:async';

import 'package:app_update/app_update.dart';
import 'package:app_update_apk_installer/app_update_apk_installer.dart';
import 'package:flutter/material.dart';
import 'package:pub_semver/pub_semver.dart';

class ApkInstallerScreen extends StatefulWidget {
  const ApkInstallerScreen({super.key});

  @override
  State<ApkInstallerScreen> createState() => _ApkInstallerScreenState();
}

class _ApkInstallerScreenState extends State<ApkInstallerScreen> {
  final _urlController = TextEditingController(
    text:
        'https://github.com/iamgirya/junk/raw/refs/heads/main/app_update_example.apk',
  );
  final _fileNameController = TextEditingController();
  final _sha256Controller = TextEditingController(
    text: '3f0c2ecac8d7bce683b69fe5b34f2449fcb4dd8d174bf786679d5346071fb476',
  );

  final _logs = <String>[];

  ApkUpdateInstaller? _installer;
  StreamSubscription<UpdateInstallationProgress>? _sub;
  UpdateInstallationProgress? _lastProgress;

  bool _requireConfirm = true;

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _urlController.dispose();
    _fileNameController.dispose();
    _sha256Controller.dispose();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $message');
    });
  }

  Update _buildFakeUpdate(String url) {
    const emptyCustom = <String, dynamic>{};

    final content = UpdateContentData(
      updateUrl: url,
      title: 'APK Installer Test',
      description: 'Manual installer test screen',
      releaseNotesTitle: 'Release notes',
      releaseNotes: null,
      skipButton: 'Skip',
      postponeButton: 'Later',
      updateButton: 'Install',
      customParams: emptyCustom,
    );

    const settings = UpdateSettingsData(
      shouldShow: true,
      canSkip: true,
      canPostpone: true,
      skipReleaseDelay: Duration(hours: 1),
      skipAllReleasesDelay: Duration(hours: 1),
      postponeReleaseDelay: Duration(minutes: 10),
      postponeAllReleasesDelay: Duration(minutes: 10),
      customParams: emptyCustom,
    );

    const appSettings = UpdateAppSettingsData(
      appStatus: AppStatus.outdated,
      customParams: emptyCustom,
    );

    return Update(
      version: Version.parse('999.0.0'),
      date: DateTime.now(),
      sourceName: UpdateSourceName.gitHub,
      platform: UpdatePlatform.android,
      rawContent: content,
      content: content,
      settings: settings,
      appSettings: appSettings,
      customParams: emptyCustom,
    );
  }

  Future<void> _start() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _log('URL is empty');
      return;
    }

    await _sub?.cancel();
    _sub = null;
    _lastProgress = null;

    final installer = ApkUpdateInstaller(requireUserConfirm: _requireConfirm);
    _installer = installer;

    final update = _buildFakeUpdate(url);
    final config = ApkUpdateInstallerConfig(
      fileName: _fileNameController.text.trim().isEmpty
          ? null
          : _fileNameController.text.trim(),
      sha256: _sha256Controller.text.trim().isEmpty
          ? null
          : _sha256Controller.text.trim(),
      requireUserConfirm: null, // uses installer.requireUserConfirm
    );

    _log('Starting install. url=$url requireConfirm=$_requireConfirm');

    final stream = installer.install(update, config);
    _sub = stream.listen(
      (p) {
        setState(() => _lastProgress = p);
        _log(p.runtimeType.toString());
        if (p is UpdateInstallationDownloading) {
          _log(
            'Downloading: ${(p.progress * 100).toStringAsFixed(1)}% '
            '${p.bytesDownloaded}/${p.totalBytes ?? '?'}',
          );
        } else if (p is UpdateInstallationDownloaded) {
          _log(
            'Downloaded: filePath=${p.downloadedUpdate.filePath} '
            'needConfirm=${p.isNeedConfirm}',
          );
        } else if (p is UpdateInstallationExecuting) {
          _log('Executing: ${((p.progress ?? 0) * 100).toStringAsFixed(1)}%');
        } else if (p is UpdateInstallationFailed) {
          _log('Failed: ${p.message}');
        }
      },
      onError: (e, s) {
        _log('Stream error: $e');
        _log('$s');
      },
      onDone: () {
        _log('Stream done');
      },
    );
  }

  Future<void> _confirm() async {
    final installer = _installer;
    if (installer == null) {
      _log('No active installer');
      return;
    }
    try {
      await installer.confirmInstallation();
      _log('confirmInstallation() called');
    } catch (e) {
      _log('confirmInstallation() error: $e');
    }
  }

  Future<void> _cancel() async {
    final installer = _installer;
    if (installer == null) {
      _log('No active installer');
      return;
    }
    try {
      await installer.cancelInstallation();
      _log('cancelInstallation() called');
    } catch (e) {
      _log('cancelInstallation() error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastState = _lastProgress;
    final progress = lastState is UpdateInstallationDownloading
        ? lastState.progress
        : lastState is UpdateInstallationExecuting
            ? lastState.progress
            : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('APK Installer'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'APK URL (https://.../file.apk)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fileNameController,
            decoration: const InputDecoration(
              labelText: 'File name (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sha256Controller,
            decoration: const InputDecoration(
              labelText: 'SHA-256 hex (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Require confirm before install'),
            value: _requireConfirm,
            onChanged: (v) => setState(() => _requireConfirm = v),
          ),
          const SizedBox(height: 12),
          if (progress != null) ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.download),
                  label: const Text('Start'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Logs',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_logs.isEmpty)
                  Text(
                    'No events yet',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                for (final line in _logs.take(200))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
