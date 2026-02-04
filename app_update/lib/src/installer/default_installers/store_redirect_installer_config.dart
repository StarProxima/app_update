import 'package:url_launcher/url_launcher.dart';

import '../../entities/update_installer_name.dart';
import '../update_installer_config.dart';

final class StoreRedirectInstallerConfig extends UpdateInstallerConfig {
  final LaunchMode? launchMode;
  final Uri? storeUrl;
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

  @override
  StoreRedirectInstallerData toData() {
    return StoreRedirectInstallerData(
      launchMode: launchMode,
      storeUrl: storeUrl ?? (throw ArgumentError('storeUrl is required')),
    );
  }
}

class StoreRedirectInstallerData extends UpdateInstallerData {
  final LaunchMode? launchMode;
  final Uri storeUrl;
  StoreRedirectInstallerData({required this.launchMode, required this.storeUrl})
      : super(name: UpdateInstallerName.storeRedirect.name);
}
