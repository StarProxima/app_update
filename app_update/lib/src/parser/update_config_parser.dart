// ignore_for_file: avoid-collection-mutating-methods, prefer-type-over-var, avoid-unnecessary-reassignment

import '../installer/installer_config_parser_coordinator.dart';
import '../models/update_config/update_config.dart';
import 'base_parsers/custom_params_parser.dart';
import 'base_parsers/update_rules_container_parser.dart';
import 'parse_config_exeption.dart';
import 'primitive_parsers/list_or_value_parser.dart';
import 'sub_parsers/global_source_config_parser.dart';
import 'sub_parsers/release_config_parser.dart';
import 'sub_parsers/update_settings_config_parser.dart';

class UpdateConfigParser {
  // for stores fetchers
  final InstallerConfigParserCoordinator? _installerConfigParserCoordinator;

  static const _listOrValueParser = ListOrValueParser();
  static const _customParamsParser = CustomParamsParser();
  late final UpdateSettingsConfigParser _updateSettingsConfigParser =
      UpdateSettingsConfigParser(
    installerConfigParserCoordinator: _installerConfigParserCoordinator,
  );
  late final _updateRulesPartParser = UpdateRulesPartParser(
    updateSettingsConfigParser: _updateSettingsConfigParser,
  );
  late final _releaseConfigParser = ReleaseConfigParser(
    updateRulesPartParser: _updateRulesPartParser,
  );
  late final _globalSourceConfigParser = GlobalSourceConfigParser(
    updateRulesPartParser: _updateRulesPartParser,
  );

  UpdateConfigParser({
    InstallerConfigParserCoordinator? installerConfigParserCoordinator,
  }) : _installerConfigParserCoordinator = installerConfigParserCoordinator;

  UpdateConfig? parse(
    Object? value, {
    required bool isDebug,
  }) {
    if (value == null) return null;

    if (value is! Map) {
      throw ParseConfigException.wrongType(
        rightType: Map,
        wrongType: value.runtimeType,
        parserType: UpdateConfigParser,
        configs: [value],
      );
    }

    final map = Map<String, dynamic>.from(value);

    // customParams
    final customParamsValue = map.remove('custom_params');
    final customParams = _customParamsParser.parse(customParamsValue);

    // releases
    final releasesRawValue = map.remove('releases');
    final releasesValue = _listOrValueParser.parse(releasesRawValue);

    if (releasesValue == null) throw const ParseConfigException();

    final releases = releasesValue
        .map((value) => _releaseConfigParser.parse(value, isDebug: isDebug))
        .nonNulls
        .toList();

    // sources
    final sourcesRawValue = map.remove('sources');
    final sourcesValue = _listOrValueParser.parse(sourcesRawValue);

    final sources = sourcesValue
        ?.map(
          (value) => _globalSourceConfigParser.parse(value, isDebug: isDebug),
        )
        .nonNulls
        .toList();

    // rules
    final rules = _updateRulesPartParser.parse(map, isDebug: isDebug);

    // Проверяем, что не осталось неизвестных параметров
    if (isDebug && map.isNotEmpty) {
      throw ParseConfigException.unexpectedParams(
        params: map,
        parserType: UpdateConfigParser,
        configs: [value],
      );
    }

    return UpdateConfig.byRequired(
      contentRules: rules.contentRules,
      settingsRules: rules.settingsRules,
      appSettingsRules: rules.appSettingsRules,
      sources: sources,
      releases: releases,
      customParams: customParams,
    );
  }

  InstallerConfigParserCoordinator get installerConfigParserCoordinator =>
      _installerConfigParserCoordinator ?? InstallerConfigParserCoordinator();
}
