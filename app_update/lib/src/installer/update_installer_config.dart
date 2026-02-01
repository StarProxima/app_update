import '../utils/mergeable.dart';

/// Базовый класс для конфигурации Installer'а
abstract class UpdateInstallerConfig implements Mergeable<UpdateInstallerConfig> {
  final String name;

  const UpdateInstallerConfig({required this.name});

  @override
  UpdateInstallerConfig merge(covariant UpdateInstallerConfig other);
}
