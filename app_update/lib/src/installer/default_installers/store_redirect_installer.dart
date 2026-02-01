import 'dart:async';

import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../entities/update_installer_name.dart';
import '../../models/release/update.dart';
import '../../models/release/update_data.dart';
import '../../models/update_installation/update_installation_progress.dart';
import '../../parser/parse_config_exeption.dart';
import '../../parser/primitive_parsers/string_parser.dart';
import '../../parser/primitive_parsers/uri_parser.dart';
import '../update_installer.dart';
import '../update_installer_config.dart';
import '../update_installer_config_parser.dart';

/// Default fallback installer that redirects user to the store (or any URL)
/// using Update.content.updateUrl.
///
/// Typically used as the last installer in UpdateController.updateInstallers.
class StoreRedirectInstaller implements UpdateInstaller {
  const StoreRedirectInstaller();

  @override
  UpdateInstallerName get name => UpdateInstallerName.storeRedirect;

  @override
  UpdateInstallerConfigParser createConfigParser() =>
      const StoreRedirectInstallerConfigParser();

  @override
  bool supports(UpdateData update) => true;

  @override
  Stream<UpdateInstallationProgress> install(
    Update update,
    covariant StoreRedirectInstallerConfig config,
  ) async* {
    yield const UpdateInstallationStarted();

    var launchMode = LaunchMode.platformDefault;
    final configLaunchMode = config.launchMode;
    if (configLaunchMode != null) {
      launchMode = configLaunchMode;
    }

    final uri = config.storeUrl;
    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      yield UpdateInstallationFailed('Cannot launch updateUrl: $uri');
      return;
    }

    yield const UpdateInstallationExecuting();

    try {
      final launched = await launchUrl(uri, mode: launchMode);
      if (!launched) {
        yield UpdateInstallationFailed(
          'Return false on launch update URL: $uri',
        );
        return;
      }
    } catch (e, s) {
      yield UpdateInstallationFailed(
        'Failed to launch update URL: $uri',
        e,
        s,
      );
      return;
    }

    yield const UpdateInstallationCompleted();
  }

  @override
  bool get isInstalling => false;

  @override
  Future<void> confirmInstallation() async {
    // Not need to confirm
  }

  @override
  Future<void> cancelInstallation() async {
    // Cant cancel
  }

  @override
  void dispose() {
    // No resources to dispose.
  }
}

final class StoreRedirectInstallerConfig extends UpdateInstallerConfig {
  final LaunchMode? launchMode;
  final Uri storeUrl;
  StoreRedirectInstallerConfig(this.launchMode, this.storeUrl)
      : super(name: UpdateInstallerName.storeRedirect.name);

  @override
  StoreRedirectInstallerConfig merge(
    covariant StoreRedirectInstallerConfig other,
  ) =>
      StoreRedirectInstallerConfig(
        other.launchMode ?? launchMode,
        other.storeUrl,
      );
}

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
