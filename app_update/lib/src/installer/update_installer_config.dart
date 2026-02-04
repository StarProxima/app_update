import '../utils/mergeable.dart';

/// Базовый класс для конфигурации Installer'а, парсится из YAML
abstract class UpdateInstallerConfig
    implements Mergeable<UpdateInstallerConfig> {
  final String name;

  const UpdateInstallerConfig({required this.name});

  @override
  UpdateInstallerConfig merge(covariant UpdateInstallerConfig other);

  UpdateInstallerData toData();
}

/// Базовый класс для данных Installer'а, может содержать required поля, используется в самом installer'е
abstract class UpdateInstallerData {
  final String name;

  const UpdateInstallerData({required this.name});
}
