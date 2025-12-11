import 'downloaded_update.dart';

/// Состояния процесса обновления
sealed class UpdateInstallationProgress {
  const UpdateInstallationProgress();
}

/// Начало процесса обновления
class UpdateInstallationStarted extends UpdateInstallationProgress {
  const UpdateInstallationStarted();
}

/// Загрузка обновления
class UpdateInstallationDownloading extends UpdateInstallationProgress {
  /// Прогресс от 0.0 до 1.0
  final double progress;

  final int bytesDownloaded;

  final int? totalBytes;

  const UpdateInstallationDownloading({
    required this.progress,
    required this.bytesDownloaded,
    this.totalBytes,
  });
}

/// Загрузка завершена, ожидает запуска установки
class UpdateInstallationDownloaded extends UpdateInstallationProgress {
  /// Информация о загруженном обновлении
  final DownloadedUpdate downloadedUpdate;

  // Нужно ли для продолжения установки вызвать controller.confirmUpdateInstallation()
  final bool isNeedConfirm;

  const UpdateInstallationDownloaded({
    required this.downloadedUpdate,
    required this.isNeedConfirm,
  });
}

/// Установка обновления
class UpdateInstallationExecuting extends UpdateInstallationProgress {
  const UpdateInstallationExecuting();
}

/// Обновление успешно завершено (передано системе)
class UpdateInstallationCompleted extends UpdateInstallationProgress {
  const UpdateInstallationCompleted();
}

/// Обновление отменено
class UpdateInstallationCancelled extends UpdateInstallationProgress {
  const UpdateInstallationCancelled();
}

/// Ошибка обновления
class UpdateInstallationFailed extends UpdateInstallationProgress {
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  const UpdateInstallationFailed(this.message, [this.error, this.stackTrace]);
}
