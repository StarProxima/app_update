import 'dart:ui';

import 'package:package_info_plus/package_info_plus.dart';

import '../../entities/update_source.dart';
import '../../installer/installer_config_parser_coordinator.dart';
import '../../models/release/update_data.dart';
import '../update_config_source_fetcher.dart';

class RuStoreFetcher extends UpdateConfigSourceFetcher {
  const RuStoreFetcher();

  @override
  UpdateSource get source => UpdateSource.ruStore;

  @override
  Future<Uri?> getSourceAppUrl({
    required Locale locale,
    required PackageInfo packageInfo,
  }) async {
    return Uri.https(
      'apps.rustore.ru',
      'app/${packageInfo.packageName}',
    );
  }

  @override
  Future<List<UpdateData>> fetchUpdates({
    required Locale locale,
    required PackageInfo packageInfo,
    required InstallerConfigParserCoordinator installerConfigParserCoordinator,
  }) {
    // TODO: implement fetchUpdates
    throw UnimplementedError();
  }
}
