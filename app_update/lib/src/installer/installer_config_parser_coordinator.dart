import '../entities/update_installer_name.dart';
import '../parser/parse_config_exeption.dart';
import 'update_installer_config.dart';
import 'update_installer_config_parser.dart';

class InstallerConfigParserCoordinator {
  // TODO а может сделать изменяемым полем, потерять const и быть счастливым?
  final Map<String, UpdateInstallerConfigParser> installerParsers;

  const InstallerConfigParserCoordinator({
    this.installerParsers = const {},
  });

  Map<UpdateInstallerName, UpdateInstallerConfig>? parse(
    Object? value, {
    required bool isDebug,
  }) {
    if (value == null) return null;

    if (value is! Map<String, dynamic>) {
      throw ParseConfigException.wrongType(
        rightType: Map<String, dynamic>,
        wrongType: value.runtimeType,
        parserType: InstallerConfigParserCoordinator,
        configs: [value],
      );
    }

    final result = <UpdateInstallerName, UpdateInstallerConfig>{};
    final rawMap = Map<String, dynamic>.from(value);

    for (final entry in rawMap.entries) {
      final rawName = entry.key;
      final installerName = UpdateInstallerName.custom(rawName);

      final parser = installerParsers[installerName.name];
      if (parser == null) {
        if (isDebug) {
          throw ParseConfigException.unexpectedParams(
            params: rawMap,
            parserType: InstallerConfigParserCoordinator,
            configs: [value],
          );
        }

        continue;
      }

      final parsedConfig = parser.parse(entry.value);
      result[installerName] = parsedConfig;
    }

    return result.isNotEmpty ? result : null;
  }
}
