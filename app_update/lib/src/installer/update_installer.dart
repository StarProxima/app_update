import 'dart:async';

import '../entities/update_installer_name.dart';
import '../models/release/update.dart';
import '../models/release/update_data.dart';
import '../models/update_installation/update_installation_progress.dart';
import 'default_installers/store_redirect_installer.dart';
import 'update_installer_config.dart';
import 'update_installer_config_parser.dart';

/// Интерфейс исполнителя обновлений
///
/// Реализуется в плагинах для разных платформ и способов обновления
abstract interface class UpdateInstaller {
  /// Возвращает парсер настроек Installer'а
  ///
  /// Используется в UpdateController во время основного парсинга YAML
  UpdateInstallerConfigParser createConfigParser();

  UpdateInstallerName get name;

  /// Возвращает true, если исполнитель сейчас выполняет установку
  bool get isInstalling;

  /// Проверяет, поддерживает ли исполнитель данное обновление
  bool canLaunch(UpdateData update);

  /// Проверяет, является ли исполнитель наиболее приоритетным для данного обновления
  /// Считаем, что canLaunch уже вернул true
  bool isHighestPriority(Update update);

  /// Запускает процесс обновления
  Stream<UpdateInstallationProgress> install(
    Update update,
    UpdateInstallerConfig config,
  );

  /// Продолжает установку после состояния Downloaded с флагом isNeedConfirm
  Future<void> confirmInstallation();

  /// Отменяет установку
  Future<void> cancelInstallation();

  /// Освобождает ресурсы Installer'а
  void dispose();

  static const defaultInstallers = [
    StoreRedirectInstaller(),
  ];
}

sealed class UpdateInstallingException implements Exception {
  final UpdateInstaller? installer;

  const UpdateInstallingException(this.installer);
}

class UpdateInstallerNotActiveException extends UpdateInstallingException {
  const UpdateInstallerNotActiveException() : super(null);
}

class UpdateInstallerAlreadyActiveException extends UpdateInstallingException {
  const UpdateInstallerAlreadyActiveException(UpdateInstaller super.installer);
}
