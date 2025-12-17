import 'update_installer_config.dart';

/// Парсер настроек для конкретного исполнителя обновлений
abstract interface class UpdateInstallerConfigParser {
  UpdateInstallerConfig parse(dynamic raw);
}
