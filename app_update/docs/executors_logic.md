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

---

## Конфигурация executor'ов через YAML API

### Концепция

Настройки executor'ов задаются в YAML-конфиге как поле `executor` внутри `data` секции `sources`, рядом с `update_url`. Это обеспечивает:

1. **Естественную привязку** — executor логически связан с источником и URL обновления
2. **Гибкость через when** — разные настройки для разных условий (статус, платформа, locale)
3. **Полную развязку** — app_update не знает о конкретных executor'ах, передаёт сырые данные в плагины
4. **Соответствие Source+Platform↔Executor** — настройки определяются в контексте конкретного источника

### Структура поля executor

```yaml
executor:
  name: inAppUpdate          # Обязательно: имя зарегистрированного executor'а
  # ... любые другие поля — настройки конкретного executor'а
  update_type: flexible
  stale_days: 5
```

Поле `executor` — это `Map<String, dynamic>` с обязательным полем `name`. Остальные поля — произвольные настройки, которые executor сам парсит при выполнении.

### Пример конфигурации

```yaml
sources:
  - name: googlePlay
    platforms: [android]
    content:
      # Дефолтный executor для Google Play
      - data:
          update_url: "https://play.google.com/store/apps/details?id=$appPackageName"
          executor:
            name: inAppUpdate
            update_type: flexible
            stale_days: 5

      # Для критических статусов — принудительное обновление
      - when: { app_status_is: [deprecated, unsupported] }
        data:
          executor:
            name: inAppUpdate
            update_type: immediate

  - name: github
    platforms: [android, windows, macos, linux]
    content:
      # Android — установка APK
      - when: { platform_is: android }
        data:
          update_url: "https://github.com/user/repo/releases/download/v$releaseVersion/app.apk"
          executor:
            name: apkInstall
            show_notification: true
            checksum_url: "https://github.com/user/repo/releases/download/v$releaseVersion/checksums.txt"

      # Desktop — редирект на страницу релизов (executor не указан)
      - when: { platform_is: [windows, macos, linux] }
        data:
          update_url: "https://github.com/user/repo/releases/latest"
          # executor не указан → автоопределение

  - name: appStore
    platforms: [ios, macos]
    content:
      - data:
          update_url: "https://apps.apple.com/app/id123"
          # executor не указан → storeRedirect (iOS не поддерживает in-app updates)
```

### UpdateExecutorConfig

Типизированная обёртка над настройками executor'а из YAML:

```dart
class UpdateExecutorConfig {
  /// Имя executor'а (обязательное поле в YAML)
  final String? name;
  
  /// Сырые настройки из YAML (без поля 'name')
  final Map<String, dynamic> settings;
  
  const UpdateExecutorConfig({
    this.name,
    this.settings = const {},
  });
  
  factory UpdateExecutorConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UpdateExecutorConfig();
    final settings = Map<String, dynamic>.from(map)..remove('name');
    return UpdateExecutorConfig(
      name: map['name'] as String?,
      settings: settings,
    );
  }
}
```

### Логика выбора executor'а в executeUpdate()

```dart
Future<UpdateExecutionResult?> executeUpdate(Update update) async {
  final executorConfig = update.content.executor;
  
  UpdateExecutor? executor;
  
  if (executorConfig.name != null) {
    // 1. Executor указан явно — ищем по имени
    executor = _executors.firstWhereOrNull(
      (e) => e.name.name == executorConfig.name,
    );
    // Если указан, но не зарегистрирован — возвращаем null
    if (executor == null) return null;
  } else {
    // 2. Executor не указан — автоопределение по Source+Platform
    executor = _executors.firstWhereOrNull(
      (e) => e.supports(update),
    );
    // Если нет подходящего — возвращаем null
    if (executor == null) return null;
  }
  
  // Парсим настройки и запускаем
  await executor.parseSettings(executorConfig);
  return _execute(executor, update);
}
```

### Метод parseSettings()

Интерфейс `UpdateExecutor` расширяется методом `parseSettings()`:

```dart
abstract interface class UpdateExecutor {
  UpdateExecutorName get name;
  
  bool supports(Update update);
  
  /// Парсит и применяет настройки из YAML-конфига
  /// Вызывается перед execute() для конфигурирования executor'а
  Future<void> parseSettings(UpdateExecutorConfig config);
  
  /// Запускает процесс обновления (сигнатура не изменилась)
  Stream<UpdateExecutionProgress> execute(Update update);
  
  Future<void> cancel();
}
```

**Преимущества отдельного метода:**
- Разделение настройки и выполнения
- Сигнатура `execute()` остаётся чистой
- Асинхронный парсинг (если нужна валидация через сеть)
- Возможность выбросить исключение при невалидных настройках до начала выполнения

### Пример реализации executor'а

```dart
class InAppUpdateExecutor implements UpdateExecutor {
  // Типизированные настройки, заполняются в parseSettings()
  InAppUpdateSettings _settings = const InAppUpdateSettings();
  
  @override
  UpdateExecutorName get name => UpdateExecutorName.inAppUpdate;
  
  @override
  bool supports(Update update) =>
    update.sourceName == UpdateSourceName.googlePlay &&
    update.platform == UpdatePlatform.android;
  
  @override
  Future<void> parseSettings(UpdateExecutorConfig config) async {
    // Парсим настройки один раз перед выполнением
    _settings = InAppUpdateSettings.fromMap(config.settings);
  }
  
  @override
  Stream<UpdateExecutionProgress> execute(Update update) async* {
    // Используем уже распарсенные настройки
    yield const UpdateExecutionStarted();
    
    if (_settings.updateType == UpdateType.immediate) {
      // Immediate update: блокирующий UI
      await InAppUpdate.performImmediateUpdate();
      yield const UpdateExecutionCompleted();
      return;
    }
    
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
    // Отмена обновления
  }
}

/// Типизированные настройки для InAppUpdate
class InAppUpdateSettings {
  final UpdateType updateType;
  final int staleDays;
  
  const InAppUpdateSettings({
    this.updateType = UpdateType.flexible,
    this.staleDays = 0,
  });
  
  factory InAppUpdateSettings.fromMap(Map<String, dynamic> map) {
    return InAppUpdateSettings(
      updateType: UpdateType.fromString(map['update_type'] as String?),
      staleDays: map['stale_days'] as int? ?? 0,
    );
  }
}

enum UpdateType {
  flexible,
  immediate;
  
  static UpdateType fromString(String? value) =>
    UpdateType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UpdateType.flexible,
    );
}
```

### Мердж настроек executor'а

Настройки executor'а мерджатся по стандартным правилам API v4:

```yaml
content:
  # Базовые настройки
  - data:
      executor:
        name: inAppUpdate
        update_type: flexible
        stale_days: 5
        
  # Переопределение для unsupported — только update_type
  - when: { app_status_is: unsupported }
    data:
      executor:
        update_type: immediate
        # name и stale_days наследуются из базового правила
```

**Результат для `app_status: unsupported`:**
```yaml
executor:
  name: inAppUpdate       # из базового
  update_type: immediate  # переопределено
  stale_days: 5           # из базового
```

### Модель данных

```dart
class UpdateContentData {
  final String? updateUrl;
  final String? title;
  final String? description;
  // ... другие поля контента
  
  /// Настройки executor'а (сырые данные из YAML)
  /// Содержит 'name' и произвольные настройки конкретного executor'а
  final Map<String, dynamic>? executor;
  
  const UpdateContentData({
    this.updateUrl,
    this.title,
    this.description,
    this.executor,
    // ...
  });
}
```

### Преимущества подхода

| Аспект | Описание |
|--------|----------|
| **Простота** | Не нужна отдельная секция, executor рядом с update_url |
| **Гибкость** | Разные executor'ы/настройки для разных when-условий |
| **Развязка** | app_update не знает о реализациях, передаёт сырой Map |
| **Типобезопасность** | Каждый executor сам парсит свои настройки в типизированную структуру |
| **Расширяемость** | Новый executor = новый плагин, без изменений в app_update |
| **Явность** | Source+Platform↔Executor соответствие видно в конфиге |
| **Разделение ответственности** | `parseSettings()` — настройка, `execute()` — выполнение |
| **Валидация до выполнения** | Ошибки конфига выбрасываются в `parseSettings()`, до начала обновления |

### Сценарии поведения executeUpdate()

| Условие | Результат |
|---------|-----------|
| `executor.name` указан и зарегистрирован | Используется указанный executor |
| `executor.name` указан, но НЕ зарегистрирован | `return null` |
| `executor` не указан, есть подходящий по `supports()` | Используется первый подходящий (по приоритету) |
| `executor` не указан, нет подходящего | `return null` |

### Регистрация executor'ов в приложении

```dart
final controller = UpdateController(
  fetchers: [...],
  updateExecutors: [
    // Порядок = приоритет для автоопределения
    InAppUpdateExecutor(),     // 1. Google Play In-App Updates
    ApkInstallExecutor(),      // 2. APK Install
    StoreRedirectExecutor(),   // 3. Fallback — открытие URL
  ],
);
```

**Важно:** Executor'ы регистрируются на этапе сборки приложения (compile-time), а конфиг определяет какие из них использовать для конкретных источников (runtime). Это позволяет:
- Включить все возможные executor'ы в сборку
- Гибко управлять их использованием через удалённый конфиг
- Не менять код приложения для изменения стратегии обновления
