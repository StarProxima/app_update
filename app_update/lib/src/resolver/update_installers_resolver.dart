import '../entities/update_installer_name.dart';
import '../installer/update_installer.dart';
import '../installer/update_installer_config.dart';
import '../models/release/update_data.dart';

class UpdateInstallersResolver {
  final Map<UpdateInstallerName, UpdateInstaller> _installersByName;

  UpdateInstallersResolver({
    required List<UpdateInstaller> installers,
  }) : _installersByName = {
          for (final installer in installers) installer.name: installer,
        };

  Map<UpdateInstallerName, UpdateInstallerConfig> selectSupportedInstallers({
    required UpdateData updateData,
    required Map<UpdateInstallerName, UpdateInstallerConfig>? installers,
  }) {
    if (installers == null || installers.isEmpty) return {};

    final supported = <UpdateInstallerName, UpdateInstallerConfig>{};
    for (final entry in installers.entries) {
      final installer = _installersByName[entry.key];
      if (installer == null) continue;
      if (!installer.supports(updateData)) continue;
      supported[entry.key] = entry.value;
    }

    return supported;
  }
}
