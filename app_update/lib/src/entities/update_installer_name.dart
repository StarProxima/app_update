import 'package:flutter/foundation.dart';

import 'update_entity.dart';

@immutable
base class UpdateInstallerName extends UpdateEntityName {
  // Предопределённые имена
  static const inAppUpdate = UpdateInstallerName._('in_app_update');
  static const apkInstall = UpdateInstallerName._('apk_install');
  static const storeRedirect = UpdateInstallerName._('store_redirect');

  static const values = [
    inAppUpdate,
    apkInstall,
    storeRedirect,
  ];

  const UpdateInstallerName._(super._name);

  // Для кастомных исполнителей
  const factory UpdateInstallerName.custom(String name) = UpdateInstallerName._;
}
