# UpdateExecutor API Design

## Обзор

`UpdateExecutor` — внутренний интерфейс для исполнителей обновлений. Реализуется в плагинах для разных платформ и способов обновления. **Не экспортируется** наружу — прогер взаимодействует с исполнителями через `UpdateController`.

**Основная идея:** На одну пару `Source + Platform` — один исполнитель. Прогер регистрирует список исполнителей в `UpdateController`, контроллер сам находит подходящий и управляет его lifecycle.

---

## UpdateController (публичный API)

### Конструктор

```dart
factory UpdateController({
  List<UpdateConfigFetcher> fetchers = const [],
  List<UpdateExecutor> updateExecutors = const [],
}) => UpdateControllerImpl(
  fetchers: fetchers,
  updateExecutors: updateExecutors,
);
```

### Новые методы

```dart
abstract interface class UpdateController {
  // ... существующие методы
  
  /// Запустить обновление подходящим исполнителем
  /// Возвращает null если нет подходящего исполнителя
  Future<UpdateExecutionResult?> executeUpdate(Update update);
  
  /// Отменить текущее обновление
  Future<void> cancelUpdateExecution();
}
```

---

## UpdateExecutionResult

Результат запуска обновления:

```dart
class UpdateExecutionResult {
  /// Имя исполнителя, который выполняет обновление
  final UpdateExecutorName executorName;
  
  /// Stream прогресса выполнения
  final Stream<UpdateExecutionProgress> progress;
  
  const UpdateExecutionResult({
    required this.executorName,
    required this.progress,
  });
}
```

---

## UpdateExecutorName

Идентификатор исполнителя (по аналогии с `UpdateSourceName`):

```dart
class UpdateExecutorName {
  final String name;
  const UpdateExecutorName._(this.name);
  
  // Предопределённые имена
  static const inAppUpdate = UpdateExecutorName._('in_app_update');
  static const apkInstall = UpdateExecutorName._('apk_install');
  static const storeRedirect = UpdateExecutorName._('store_redirect');
  
  // Для кастомных исполнителей
  factory UpdateExecutorName(String name) => UpdateExecutorName._(name);
  
  @override
  bool operator ==(Object other) =>
    other is UpdateExecutorName && other.name == name;
    
  @override
  int get hashCode => name.hashCode;
  
  @override
  String toString() => name;
}
```

---

## UpdateExecutionProgress (sealed)

Состояния процесса обновления:

```dart
sealed class UpdateExecutionProgress {
  const UpdateExecutionProgress();
}

/// Начало процесса обновления
class UpdateExecutionStarted extends UpdateExecutionProgress {
  const UpdateExecutionStarted();
}

/// Загрузка обновления
class UpdateExecutionDownloading extends UpdateExecutionProgress {
  /// Прогресс от 0.0 до 1.0
  final double progress;
  
  /// Загружено байт
  final int bytesDownloaded;
  
  /// Всего байт (null если неизвестно)
  final int? totalBytes;
  
  const UpdateExecutionDownloading({
    required this.progress,
    required this.bytesDownloaded,
    this.totalBytes,
  });
}

/// Загрузка завершена, ожидает запуска установки
/// 
/// Используется когда загрузка и установка разделены:
/// - APK: нужно запросить разрешение на установку
/// - In-App Update Flexible: пользователь решает когда установить
class UpdateExecutionDownloaded extends UpdateExecutionProgress {
  /// Информация о загруженном обновлении
  final DownloadedUpdate downloadedUpdate;
  
  /// Запустить установку
  /// Если не вызвать — установка не начнётся
  /// Для отмены использовать controller.cancelUpdateExecution()
  final void Function() startInstallation;
  
  UpdateExecutionDownloaded({
    required this.downloadedUpdate,
    required this.startInstallation,
  });
}

/// Установка обновления
class UpdateExecutionInstalling extends UpdateExecutionProgress {
  const UpdateExecutionInstalling();
}

/// Обновление успешно завершено (передано системе)
/// 
/// Для APK: системный установщик открыт
/// Для In-App Update: обновление применено
class UpdateExecutionCompleted extends UpdateExecutionProgress {
  const UpdateExecutionCompleted();
}

/// Обновление отменено
class UpdateExecutionCancelled extends UpdateExecutionProgress {
  const UpdateExecutionCancelled();
}

/// Ошибка обновления
class UpdateExecutionFailed extends UpdateExecutionProgress {
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  
  const UpdateExecutionFailed(this.message, [this.error, this.stackTrace]);
}
```

---

## DownloadedUpdate

Информация о загруженном обновлении. Содержимое TBD.

```dart
class DownloadedUpdate {
  // TBD: определить поля
  // Возможные поля:
  // - String? filePath
  // - Version version
  // - int fileSize
  // - Map<String, dynamic>? metadata
}
```

---

## UpdateExecutor (внутренний интерфейс)

**Не экспортируется** — используется только внутри `UpdateController`.

```dart
/// Интерфейс исполнителя обновлений (internal)
/// 
/// Реализуется в плагинах для разных платформ и способов обновления:
/// - `InAppUpdateExecutor` (googlePlay + android)
/// - `ApkInstallExecutor` (github/custom + android)
/// - `StoreRedirectExecutor` (универсальный fallback)
/// - и др.
abstract interface class UpdateExecutor {
  /// Имя исполнителя
  UpdateExecutorName get name;
  
  /// Проверяет, поддерживает ли исполнитель данное обновление
  /// (по Source + Platform)
  bool supports(Update update);
  
  /// Запускает процесс обновления
  /// Возвращает Stream для отслеживания прогресса
  Stream<UpdateExecutionProgress> execute(Update update);
  
  /// Отменяет текущее обновление
  Future<void> cancel();
}
```

---

## Диаграмма состояний

```
executeUpdate() → Future<UpdateExecutionResult?>
                      │
                      ▼
              UpdateExecutionResult
                      │
                      ▼
              progress Stream<UpdateExecutionProgress>
                      │
                      ├─→ UpdateExecutionStarted
                      │
                      ├─→ UpdateExecutionDownloading (progress: 0.0 → 1.0)
                      │
                      ├─→ UpdateExecutionDownloaded  ← ожидание startInstallation()
                      │       │
                      │       └─→ startInstallation() → продолжаем
                      │           (или cancelUpdateExecution() → Cancelled)
                      │
                      ├─→ UpdateExecutionInstalling
                      │
                      └─→ UpdateExecutionCompleted / UpdateExecutionCancelled / UpdateExecutionFailed
```

**Примечание:** Исполнители, где загрузка и установка неразрывны, могут пропускать состояния `UpdateExecutionDownloading` и `UpdateExecutionDownloaded`.

---

## Примеры использования

### Базовое использование

```dart
// Инициализация
final controller = UpdateController(
  fetchers: [...],
  updateExecutors: [
    InAppUpdateExecutor(),    // приоритет 1 (первый в списке)
    ApkInstallExecutor(),     // приоритет 2
    StoreRedirectExecutor(),  // fallback (последний)
  ],
);

// Поиск обновления
final update = controller.findUpdate(searchConfig);
if (update == null) return;

// Запуск обновления
final result = await controller.executeUpdate(update);
if (result == null) {
  print('Нет подходящего исполнителя');
  return;
}

print('Используем: ${result.executorName}');

// Слушаем прогресс
result.progress.listen((progress) {
  switch (progress) {
    case UpdateExecutionStarted():
      showLoader();
      
    case UpdateExecutionDownloading(:final progress):
      updateProgressBar(progress);
      
    case UpdateExecutionDownloaded(:final downloadedUpdate, :final startInstallation):
      showInstallDialog(
        onInstall: startInstallation,
      );
      
    case UpdateExecutionInstalling():
      showInstallingMessage();
      
    case UpdateExecutionCompleted():
      showSuccess();
      
    case UpdateExecutionCancelled():
      showCancelled();
      
    case UpdateExecutionFailed(:final message):
      showError(message);
  }
});
```

### Отмена обновления

```dart
// Если пользователь закрыл экран или нажал "Отмена"
await controller.cancelUpdateExecution();
```

---

## Примеры реализаций исполнителей (internal)

### StoreRedirectExecutor (fallback)

```dart
class StoreRedirectExecutor implements UpdateExecutor {
  @override
  UpdateExecutorName get name => UpdateExecutorName.storeRedirect;
  
  @override
  bool supports(Update update) => update.updateUrl != null;
  
  @override
  Stream<UpdateExecutionProgress> execute(Update update) async* {
    yield const UpdateExecutionStarted();
    
    final uri = Uri.parse(update.updateUrl!);
    await launchUrl(uri);
    
    // Store открыт — мы сделали всё что могли
    yield const UpdateExecutionCompleted();
  }
  
  @override
  Future<void> cancel() async {
    // Redirect нельзя отменить
  }
}
```

### InAppUpdateExecutor

```dart
class InAppUpdateExecutor implements UpdateExecutor {
  @override
  UpdateExecutorName get name => UpdateExecutorName.inAppUpdate;
  
  @override
  bool supports(Update update) =>
    update.sourceName == UpdateSourceName.googlePlay &&
    update.platform == UpdatePlatform.android;
  
  @override
  Stream<UpdateExecutionProgress> execute(Update update) async* {
    yield const UpdateExecutionStarted();
    
    // Flexible update: загрузка в фоне
    await for (final event in InAppUpdate.startFlexibleUpdate()) {
      yield UpdateExecutionDownloading(
        progress: event.bytesDownloaded / event.totalBytesToDownload,
        bytesDownloaded: event.bytesDownloaded,
        totalBytes: event.totalBytesToDownload,
      );
    }
    
    // Ожидаем подтверждения от пользователя
    final completer = Completer<void>();
    yield UpdateExecutionDownloaded(
      downloadedUpdate: DownloadedUpdate(...),
      startInstallation: () => completer.complete(),
    );
    await completer.future;
    
    yield const UpdateExecutionInstalling();
    await InAppUpdate.completeFlexibleUpdate();
    yield const UpdateExecutionCompleted();
  }
  
  @override
  Future<void> cancel() async {
    // Отмена flexible update
  }
}
```

### ApkInstallExecutor

```dart
class ApkInstallExecutor implements UpdateExecutor {
  CancelToken? _cancelToken;
  
  @override
  UpdateExecutorName get name => UpdateExecutorName.apkInstall;
  
  @override
  bool supports(Update update) =>
    update.platform == UpdatePlatform.android &&
    update.sourceName != UpdateSourceName.googlePlay &&
    update.updateUrl?.endsWith('.apk') == true;
  
  @override
  Stream<UpdateExecutionProgress> execute(Update update) async* {
    yield const UpdateExecutionStarted();
    
    _cancelToken = CancelToken();
    
    // Загрузка APK
    final controller = StreamController<UpdateExecutionProgress>();
    final apkPath = await _downloadApk(
      update.updateUrl!,
      cancelToken: _cancelToken,
      onProgress: (received, total) {
        controller.add(UpdateExecutionDownloading(
          progress: received / total,
          bytesDownloaded: received,
          totalBytes: total,
        ));
      },
    );
    yield* controller.stream;
    
    // Ожидаем подтверждения (для запроса разрешения)
    final completer = Completer<void>();
    yield UpdateExecutionDownloaded(
      downloadedUpdate: DownloadedUpdate(...),
      startInstallation: () => completer.complete(),
    );
    await completer.future;
    
    yield const UpdateExecutionInstalling();
    await OpenFile.open(apkPath);
    yield const UpdateExecutionCompleted();
  }
  
  @override
  Future<void> cancel() async {
    _cancelToken?.cancel();
  }
}
```

---

## Сводка API

### Публичный API (экспортируется)

| Компонент | Поля/Методы |
|-----------|-------------|
| **UpdateController** | `executeUpdate()`, `cancelUpdateExecution()` + параметр `updateExecutors` в конструкторе |
| **UpdateExecutionResult** | `executorName`, `progress` |
| **UpdateExecutorName** | `name`, константы: `inAppUpdate`, `apkInstall`, `storeRedirect` |
| **UpdateExecutionProgress** | `Started`, `Downloading`, `Downloaded`, `Installing`, `Completed`, `Cancelled`, `Failed` |
| **UpdateExecutionDownloaded** | `downloadedUpdate`, `startInstallation()` |
| **DownloadedUpdate** | TBD |

### Внутренний API (не экспортируется)

| Компонент | Поля/Методы |
|-----------|-------------|
| **UpdateExecutor** | `name`, `supports()`, `execute()`, `cancel()` |

---

## Ключевые решения

1. **Инкапсуляция executor-а** — прогер не получает `UpdateExecutor` напрямую, взаимодействует через `UpdateController`

2. **Один исполнитель на Source+Platform** — контроллер сам находит подходящий

3. **Приоритет через порядок в списке** — первый в `updateExecutors` = самый приоритетный

4. **`supports()` проверяет только совместимость** — не проверяет возможность обновления, только Source+Platform

5. **`UpdateExecutionDownloaded` для двухэтапных обновлений** — загрузка отдельно, установка отдельно (APK permission, flexible in_app_update)

6. **`startInstallation()` без параметров** — просто запускает установку, для отмены использовать `controller.cancelUpdateExecution()`

7. **Stream-based API** — единый интерфейс для всех типов обновлений с отслеживанием прогресса

8. **Контроллер управляет lifecycle** — решает проблему stateful executor, контроллер знает какой executor активен
