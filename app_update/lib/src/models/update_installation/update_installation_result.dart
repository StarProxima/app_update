import 'dart:async';

import '../../entities/update_installer_name.dart';
import 'update_installation_progress.dart';

/// Результат запуска обновления
class UpdateInstallationResult {
  /// Имя исполнителя, который выполняет обновление
  final UpdateInstallerName installerName;

  /// Stream прогресса выполнения
  final Stream<UpdateInstallationProgress> progressStream;

  const UpdateInstallationResult({
    required this.installerName,
    required this.progressStream,
  });
}
