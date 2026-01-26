/// Информация о загруженном обновлении
class DownloadedUpdate {
  /// Путь к файлу (если применимо)
  final String? filePath;

  /// Размер файла в байтах
  final int? fileSize;

  /// Дополнительные метаданные
  final Map<String, dynamic>? metadata;

  /// Является ли файл резервной копией, сохранённой локально, или был загружен заново
  final bool isCached;

  const DownloadedUpdate({
    this.filePath,
    this.fileSize,
    this.metadata,
    required this.isCached,
  });
}
