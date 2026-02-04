import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../parser/parse_config_exeption.dart';
import '../../parser/primitive_parsers/string_parser.dart';
import '../../parser/primitive_parsers/uri_parser.dart';
import '../update_installer_config.dart';
import '../update_installer_config_parser.dart';
import 'store_redirect_installer_config.dart';

final class StoreRedirectInstallerConfigParser
    implements UpdateInstallerConfigParser {
  const StoreRedirectInstallerConfigParser();

  static const _stringParser = StringParser();
  static const _uriParser = UriParser();

  @override
  UpdateInstallerConfig parse(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw ParseConfigException.wrongType(
        rightType: Map<String, dynamic>,
        wrongType: raw.runtimeType,
        parserType: StoreRedirectInstallerConfigParser,
        configs: [raw],
      );
    }

    final rawLaunchMode = _stringParser.parse(raw['launch_mode']);
    final launchMode = LaunchMode.values.firstWhereOrNull(
      (mode) => mode.name == rawLaunchMode,
    );

    final storeUrl = _uriParser.parse(raw['store_url']);
    if (storeUrl == null) {
      throw ParseConfigException.requiredParams(
        params: ['store_url'],
        parserType: StoreRedirectInstallerConfigParser,
        configs: [raw],
      );
    }

    return StoreRedirectInstallerConfig(launchMode, storeUrl);
  }
}
