import 'dart:async';

import '../models/release/update.dart';
import '../models/update_installation/update_installation_progress.dart';
import '../models/update_installation/update_installation_result.dart';
import 'update_installer.dart';
import 'update_installer_config.dart';

typedef UpdateInstallerAndData = ({
  UpdateInstaller installer,
  UpdateInstallerData data
});

class InstallerLauncher {
  UpdateInstaller? _activeInstaller;
  StreamSubscription<UpdateInstallationProgress>?
      _activeInstallerProgressSubscription;

  UpdateInstaller? get activeInstaller => _activeInstaller;

  bool get isInstalling =>
      _activeInstaller != null && !_activeInstaller!.lastState.isFinal;

  List<UpdateInstallerAndData> _supportedInstallers(
    Update update,
    List<UpdateInstaller> updateInstallers,
  ) {
    final installerDatas = update.settings.installers;
    if (installerDatas.isEmpty) return [];

    final supportedInstallers = <UpdateInstallerAndData>[];
    for (final installer in updateInstallers) {
      final data = installerDatas[installer.name];
      if (data == null) continue;
      supportedInstallers.add((installer: installer, data: data));
    }

    return supportedInstallers;
  }

  UpdateInstallerAndData? selectHighestPriorityInstaller(
    Update update,
    List<UpdateInstaller> updateInstallers,
  ) {
    final supportedInstallers = _supportedInstallers(update, updateInstallers);
    if (supportedInstallers.isEmpty) return null;

    // ищем installer с наибольшим приоритетом
    for (final installerAndData in supportedInstallers) {
      if (installerAndData.installer.isHighestPriority(update)) {
        return installerAndData;
      }
    }

    // иначе приоритет определяется порядком регистрации installer'ов в UpdateController
    return supportedInstallers.first;
  }

  UpdateInstallerAndData? selectInstallerByType<T extends UpdateInstaller>(
    Update update,
    List<UpdateInstaller> updateInstallers,
  ) {
    final supportedInstallers = _supportedInstallers(update, updateInstallers);

    return supportedInstallers
        .where((installer) => installer.installer is T)
        .firstOrNull;
  }

  UpdateInstallationResult launchInstaller(
    Update update,
    UpdateInstallerAndData installerAndData,
    UpdateInstallerAndData? fallbackInstallerAndData,
  ) {
    resetActiveInstaller();
    // выходной контроллер, в который дублируем прогресс из контроллеров installer'ов
    final controller = StreamController<UpdateInstallationProgress>.broadcast();

    // функция запуска установки installer'а. рекурсивно используется для fallback
    void startInstaller(
      UpdateInstallerAndData current,
      UpdateInstallerAndData? fallback,
    ) {
      _activeInstaller = current.installer;

      // запуск установки
      final progressStream = current.installer.install(
        update,
        current.data,
      );

      _activeInstallerProgressSubscription?.cancel();
      _activeInstallerProgressSubscription = progressStream.listen(
        (progress) {
          // если случилась ошибка, вместо UpdateInstallationFailed запускаем установку fallback
          if (progress is UpdateInstallationFailed && fallback != null) {
            startInstaller(fallback, null);
            return;
          }

          controller.add(progress);
          if (progress.isFinal) {
            resetActiveInstaller();
            if (!controller.isClosed) {
              controller.close();
            }
          }
        },
        onError: (error, stackTrace) {
          final progress = UpdateInstallationFailed(
            'Installer stream error',
            error,
            stackTrace,
          );
          controller.add(progress);
          resetActiveInstaller();
          if (!controller.isClosed) {
            controller.close();
          }
        },
        onDone: () {
          resetActiveInstaller();
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );
    }

    startInstaller(
      installerAndData,
      fallbackInstallerAndData,
    );

    return UpdateInstallationResult(
      installerName: installerAndData.installer.name,
      progressStream: controller.stream,
    );
  }

  void resetActiveInstaller() {
    _activeInstaller = null;
    _activeInstallerProgressSubscription?.cancel();
    _activeInstallerProgressSubscription = null;
  }
}
