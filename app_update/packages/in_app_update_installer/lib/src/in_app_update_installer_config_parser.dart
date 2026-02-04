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

  static const _boolParser = BoolParser();
  static const _stringParser = StringParser();

  @override
  UpdateInstallerConfig parse(dynamic raw) {
    if (raw is! Map) {
      return const InAppUpdateInstallerConfig();
    }

    final updateType = _stringParser.parse(raw['update_type']);
    final requireUserConfirm = _boolParser.parse(raw['require_user_confirm']);
    final canChangeUpdateType = _boolParser.parse(
      raw['can_change_update_type'],
    );

    return InAppUpdateInstallerConfig(
      updateType: _parseUpdateType(updateType),
      requireUserConfirm: requireUserConfirm,
      canChangeUpdateType: canChangeUpdateType,
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
