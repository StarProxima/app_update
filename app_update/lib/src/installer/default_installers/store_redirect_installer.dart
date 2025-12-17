import 'dart:async';

import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../entities/update_installer_name.dart';
import '../../models/release/update.dart';
import '../../models/update_installation/update_installation_progress.dart';
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
      const _StoreRedirectInstallerConfigParser();

  @override
  bool supports(Update update) {
    return update.content.updateUrl.trim().isNotEmpty;
  }

  @override
  Stream<UpdateInstallationProgress> install(
    Update update,
    UpdateInstallerConfig? config,
  ) async* {
    yield const UpdateInstallationStarted();

    var launchMode = LaunchMode.platformDefault;
    if (config is StoreRedirectInstallerConfig) {
      if (config.launchMode != null) {
        launchMode = config.launchMode!;
      }
    }

    final urlString = update.content.updateUrl.trim();
    final uri = Uri.tryParse(urlString);
    if (uri == null) {
      yield UpdateInstallationFailed('Invalid updateUrl: $urlString');
      return;
    }

    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      yield UpdateInstallationFailed('Cannot launch updateUrl: $urlString');
      return;
    }

    yield const UpdateInstallationExecuting();

    try {
      final launched = await launchUrl(uri, mode: launchMode);
      if (!launched) {
        yield UpdateInstallationFailed(
          'Return false on launch update URL: $urlString',
        );
        return;
      }
    } catch (e, s) {
      yield UpdateInstallationFailed(
        'Failed to launch update URL: $urlString',
        e,
        s,
      );
      return;
    }

    yield const UpdateInstallationCompleted();
  }

  @override
  Future<void> confirmInstallation() async {
    // Not need to confirm
  }

  @override
  Future<void> cancelInstallation() async {
    // Cant cancel
  }
}

final class StoreRedirectInstallerConfig extends UpdateInstallerConfig {
  final LaunchMode? launchMode;
  StoreRedirectInstallerConfig(this.launchMode)
      : super(name: UpdateInstallerName.storeRedirect.name);
}

final class _StoreRedirectInstallerConfigParser
    implements UpdateInstallerConfigParser {
  const _StoreRedirectInstallerConfigParser();

  @override
  UpdateInstallerConfig parse(dynamic raw) {
    LaunchMode? launchMode;

    if (raw is Map<String, dynamic>) {
      final rawLaunchMode = raw['launch_mode'];
      if (rawLaunchMode is String) {
        launchMode = LaunchMode.values.firstWhereOrNull(
          (mode) => mode.name == rawLaunchMode,
        );
      }
    }

    return StoreRedirectInstallerConfig(launchMode);
  }
}
