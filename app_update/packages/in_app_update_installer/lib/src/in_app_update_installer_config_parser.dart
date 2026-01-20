import 'package:app_update/app_update.dart';

import 'in_app_update_installer_config.dart';
import 'in_app_update_type.dart';

/// Parses config for [InAppUpdateInstallerConfig].
///
/// Supported keys:
/// - update_type: "immediate" | "flexible"
/// - require_user_confirm: bool
final class InAppUpdateInstallerConfigParser
    implements UpdateInstallerConfigParser {
  const InAppUpdateInstallerConfigParser();

  @override
  UpdateInstallerConfig parse(dynamic raw) {
    if (raw is! Map) {
      return const InAppUpdateInstallerConfig();
    }

    final updateType = _parseUpdateType(raw['update_type']);
    final requireUserConfirm = raw['require_user_confirm'] as bool?;

    return InAppUpdateInstallerConfig(
      updateType: updateType,
      requireUserConfirm: requireUserConfirm,
    );
  }

  InAppUpdateType? _parseUpdateType(Object? raw) {
    if (raw is! String) return null;

    return switch (raw.trim().toLowerCase()) {
      'immediate' => InAppUpdateType.immediate,
      'flexible' => InAppUpdateType.flexible,
      _ => null,
    };
  }
}
