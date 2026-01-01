import 'package:flutter/material.dart';
import 'package:app_update/app_update.dart';

import 'apk_installer_controller.dart';

class ApkInstallerScreen extends StatefulWidget {
  const ApkInstallerScreen({super.key});

  @override
  State<ApkInstallerScreen> createState() => _ApkInstallerScreenState();
}

class _ApkInstallerScreenState extends State<ApkInstallerScreen> {
  late final ApkInstallerController _controller;
  final _urlController = TextEditingController(
    text:
        'https://github.com/iamgirya/junk/raw/refs/heads/main/app_update_example.apk', // TODO Убрать
  );
  final _fileNameController = TextEditingController();
  final _sha256Controller = TextEditingController(
    text: '3f0c2ecac8d7bce683b69fe5b34f2449fcb4dd8d174bf786679d5346071fb476',
  );

  @override
  void initState() {
    super.initState();
    _controller = ApkInstallerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _urlController.dispose();
    _fileNameController.dispose();
    _sha256Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ApkInstallerState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final lastState = state.lastProgress;
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
                value: state.requireConfirm,
                onChanged: _controller.setRequireConfirm,
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
                      onPressed: () => _controller.start(
                        url: _urlController.text,
                        fileName: _fileNameController.text,
                        sha256: _sha256Controller.text,
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text('Start'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _controller.confirm,
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _controller.cancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _controller.reloadInstaller,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload installer'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => _controller.clearBackup(
                  url: _urlController.text,
                  fileName: _fileNameController.text,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear backup'),
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
                    if (state.logs.isEmpty)
                      Text(
                        'No events yet',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    for (final line in state.logs.take(200))
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
      },
    );
  }
}
