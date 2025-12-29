/// Информация о загруженном обновлении
class DownloadedUpdate {
  /// Путь к файлу (если применимо)
  final String? filePath;

  /// Размер файла в байтах
  final int? fileSize;

  /// Дополнительные метаданные
  final Map<String, dynamic>? metadata;

  /// Флаг, что файл является резервной копией
  final bool isBackup;

  const DownloadedUpdate({
    this.filePath,
    this.fileSize,
    this.metadata,
    required this.isBackup,
  });
}
