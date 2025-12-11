# UpdateInstaller API Design

## Обзор

`UpdateInstaller` — внутренний интерфейс для исполнителей обновлений. Реализуется в плагинах для разных платформ и способов обновления. **Не экспортируется** наружу — прогер взаимодействует с исполнителями через `UpdateController`.

**Основная идея:** На одну пару `Source + Platform` — один исполнитель. Прогер регистрирует список исполнителей в `UpdateController`, контроллер сам находит подходящий и управляет его lifecycle.

---

## UpdateController (публичный API)

### Конструктор

```dart
factory UpdateController({
  List<UpdateConfigFetcher> fetchers = const [],
  List<UpdateInstaller> updateInstallers = const [], // Добавляем updateInstallers
}) => UpdateControllerImpl(
  fetchers: fetchers,
  updateInstallers: updateInstallers,
);
```

### Новые методы

```dart
abstract interface class UpdateController {
  // ... существующие методы
  
  /// Запустить обновление подходящим исполнителем
  /// Возвращает null если нет подходящего исполнителя
  Future<UpdateInstallationResult?> installUpdate(Update update);
  
  /// Подтвердить продолжение выполнения обновления после состояния Downloaded
  /// Вызывается когда пользователь подтвердил установку
  Future<void> confirmUpdateInstallation();
  
  /// Отменить текущее обновление
  Future<void> cancelUpdateInstallation();
}
```

---

## UpdateInstallationResult

Результат запуска обновления:

```dart
class UpdateInstallationResult {
  /// Имя исполнителя, который выполняет обновление
  final UpdateInstallerName installerName;
  
  /// Stream прогресса выполнения
  final Stream<UpdateInstallationProgress> progress;
  
  const UpdateInstallationResult({
    required this.installerName,
    required this.progress,
  });
}
```

---

## UpdateInstallerName

Идентификатор исполнителя (по аналогии с `UpdateSourceName`):

```dart
class UpdateInstallerName {
  final String name;
  const UpdateInstallerName._(this.name);
  
  // Предопределённые имена
  static const inAppUpdate = UpdateInstallerName._('in_app_update');
  static const apkInstall = UpdateInstallerName._('apk_install');
  static const storeRedirect = UpdateInstallerName._('store_redirect');
  
  // Для кастомных исполнителей
  factory UpdateInstallerName(String name) => UpdateInstallerName._(name);
  
  @override
  bool operator ==(Object other) =>
    other is UpdateInstallerName && other.name == name;
    
  @override
  int get hashCode => name.hashCode;
  
  @override
  String toString() => name;
}
```

---

## UpdateInstallationProgress (sealed)

Состояния процесса обновления:

```dart
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
  
  /// Загружено байт
  final int bytesDownloaded;
  
  /// Всего байт (null если неизвестно)
  final int? totalBytes;
  
  const UpdateInstallationDownloading({
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
/// 
/// Для продолжения установки вызвать controller.confirmUpdateInstallation()
/// Для отмены — controller.cancelUpdateInstallation()
class UpdateInstallationDownloaded extends UpdateInstallationProgress {
  /// Информация о загруженном обновлении
  final DownloadedUpdate downloadedUpdate;
  
  const UpdateInstallationDownloaded({
    required this.downloadedUpdate,
  });
}

/// Установка обновления
class UpdateInstallationExecuting extends UpdateInstallationProgress {
  const UpdateInstallationExecuting();
}

/// Обновление успешно завершено (передано системе)
/// 
/// Для APK: системный установщик открыт
/// Для In-App Update: обновление применено
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

## UpdateInstaller (внутренний интерфейс)

**Не экспортируется** — используется только внутри `UpdateController`.

```dart
/// Интерфейс исполнителя обновлений (internal)
/// 
/// Реализуется в плагинах для разных платформ и способов обновления:
/// - `InAppUpdateInstaller` (googlePlay + android)
/// - `ApkInstallInstaller` (github/custom + android)
/// - `StoreRedirectInstaller` (универсальный fallback)
/// - и др.
abstract interface class UpdateInstaller {
  /// Возвращает парсер настроек Installer'а
  ///
  /// Используется в UpdateController во время основного парсинга YAML,
  /// чтобы превратить raw Map в типобезопасный [UpdateInstallerConfig].
  UpdateInstallerConfigParser createConfigParser();
 
  /// Имя исполнителя
  UpdateInstallerName get name;
  
  /// Проверяет, поддерживает ли исполнитель данное обновление
  /// (по Source + Platform)
  bool supports(Update update);
  
  /// Запускает процесс обновления
  /// [config] — настройки Installer'а из YAML (может быть null)
  /// Возвращает Stream для отслеживания прогресса
  Stream<UpdateInstallationProgress> install(
    Update update,
    UpdateInstallerConfig? config,
  );
  
  /// Продолжает установку после состояния Downloaded
  /// Вызывается контроллером при controller.confirmUpdateInstallation()
  Future<void> confirmInstallation();
  
  /// Отменяет текущее обновление
  Future<void> cancel();
}
```



## Примеры использования

### Базовое использование

```dart
// Инициализация
final controller = UpdateController(
  fetchers: [...],
  updateInstallers: [
    InAppUpdateInstaller(),    // приоритет 1 (первый в списке)
    ApkInstallInstaller(),     // приоритет 2
    StoreRedirectInstaller(),  // fallback (последний)
  ],
);

// Поиск обновления
final update = controller.findUpdate(searchConfig);
if (update == null) return;

// Запуск обновления
final result = await controller.installUpdate(update);
if (result == null) {
  print('Нет подходящего исполнителя');
  return;
}

print('Используем: ${result.installerName}');

// Слушаем прогресс
result.progress.listen((progress) {
  switch (progress) {
    case UpdateInstallationStarted():
      showLoader();
      
    case UpdateInstallationDownloading(:final progress):
      updateProgressBar(progress);
      
    case UpdateInstallationDownloaded(:final downloadedUpdate):
      // Показываем диалог подтверждения установки
      showInstallDialog(
        onInstall: () => controller.confirmUpdateInstallation(),
        onCancel: () => controller.cancelUpdateInstallation(),
      );
      
    case UpdateInstallationExecuting():
      showInstallingMessage();
      
    case UpdateInstallationCompleted():
      showSuccess();
      
    case UpdateInstallationCancelled():
      showCancelled();
      
    case UpdateInstallationFailed(:final message):
      showError(message);
  }
});

---

## Сводка API

### Публичный API (экспортируется)

| Компонент | Поля/Методы |
|-----------|-------------|
| **UpdateController** | `installUpdate()`, `confirmUpdateInstallation()`, `cancelUpdateInstallation()` + параметр `updateInstallers` в конструкторе |
| **UpdateInstallationResult** | `installerName`, `progress` |
| **UpdateInstallerName** | `name`, константы: `inAppUpdate`, `apkInstall`, `storeRedirect` |
| **UpdateInstallationProgress** | `Started`, `Downloading`, `Downloaded`, `Installing`, `Completed`, `Cancelled`, `Failed` |
| **UpdateInstallationDownloaded** | `downloadedUpdate` |
| **DownloadedUpdate** | TBD |

### Внутренний API (не экспортируется)

| Компонент | Поля/Методы |
|-----------|-------------|
| **UpdateInstaller** | `createConfigParser()`, `name`, `supports()`, `install(update, config)`, `confirmInstallation()`, `cancel()` |
| **UpdateInstallerConfigParser** | `parse(raw) -> UpdateInstallerConfig` |

---

## Ключевые решения

1. **Инкапсуляция Installer-а** — прогер не получает `UpdateInstaller` напрямую, взаимодействует через `UpdateController`

2. **Один исполнитель на Source+Platform** — контроллер сам находит подходящий

3. **Приоритет через порядок в списке** — первый в `updateInstallers` = самый приоритетный

4. **`supports()` проверяет только совместимость** — не проверяет возможность обновления, только Source+Platform

5. **`UpdateInstallationDownloaded` для двухэтапных обновлений** — загрузка отдельно, установка отдельно (APK permission, flexible in_app_update)

6. **Состояния — только данные** — `UpdateInstallationProgress` не содержит callbacks, управление через методы контроллера

7. **`controller.confirmUpdateInstallation()`** — продолжает установку после Downloaded, `controller.cancelUpdateInstallation()` — отменяет

8. **Stream-based API** — единый интерфейс для всех типов обновлений с отслеживанием прогресса

9. **Контроллер управляет lifecycle** — решает проблему stateful Installer, контроллер знает какой Installer активен

---

## Конфигурация Installer'ов через YAML API

### Концепция

Настройки Installer'ов задаются в YAML-конфиге как поле `Installer` внутри `data` секции `sources`, рядом с `update_url`. Это обеспечивает:

1. **Естественную привязку** — Installer логически связан с источником и URL обновления
2. **Гибкость через when** — разные настройки для разных условий (статус, платформа, locale)
3. **Полную развязку** — app_update не знает о конкретных Installer'ах, передаёт сырые данные в плагины
4. **Соответствие Source+Platform↔Installer** — настройки определяются в контексте конкретного источника

### Структура поля Installer

```yaml
installer:
  name: inAppUpdate          # Обязательно: имя зарегистрированного Installer'а
  # ... любые другие поля — настройки конкретного Installer'а
  update_type: flexible
  stale_days: 5
```

Поле `Installer` — это `Map<String, dynamic>` с обязательным полем `name`. Остальные поля — произвольные настройки, которые Installer сам парсит при выполнении.

### Пример конфигурации

```yaml
sources:
  - name: googlePlay
    platforms: [android]
    content:
      # Дефолтный Installer для Google Play
      - data:
          update_url: "https://play.google.com/store/apps/details?id=$appPackageName"
          installer:
            name: inAppUpdate
            update_type: flexible
            stale_days: 5

      # Для критических статусов — принудительное обновление
      - when: { app_status_is: [deprecated, unsupported] }
        data:
          installer:
            name: inAppUpdate
            update_type: immediate

  - name: github
    platforms: [android, windows, macos, linux]
    content:
      # Android — установка APK
      - when: { platform_is: android }
        data:
          update_url: "https://github.com/user/repo/releases/download/v$releaseVersion/app.apk"
          installer:
            name: apkInstall
            show_notification: true
            checksum_url: "https://github.com/user/repo/releases/download/v$releaseVersion/checksums.txt"

      # Desktop — редирект на страницу релизов (Installer не указан)
      - when: { platform_is: [windows, macos, linux] }
        data:
          update_url: "https://github.com/user/repo/releases/latest"
          # Installer не указан → автоопределение

  - name: appStore
    platforms: [ios, macos]
    content:
      - data:
          update_url: "https://apps.apple.com/app/id123"
          # Installer не указан → storeRedirect (iOS не поддерживает in-app updates)
```

### UpdateInstallerConfig

Типизированная обёртка над настройками Installer'а из YAML:

```dart
abstract class UpdateInstallerConfig {
  /// Имя Installer'а (обязательное поле в YAML)
  final String name;
  
  factory UpdateInstallerConfig.fromMap(Map<String, dynamic>? map);
}
```

### UpdateInstallerConfigParser

Интерфейс парсера настроек конкретного Installer'а:

```dart
/// Парсер настроек для конкретного исполнителя обновлений
///
/// Используется UpdateController во время основного парсинга:
/// 1. Находит Installer по имени
/// 2. Берёт его parser через createConfigParser()
/// 3. Вызывает parser.parse(...) для получения UpdateInstallerConfig
abstract interface class UpdateInstallerConfigParser {
  /// Парсит Map из YAML в [UpdateInstallerConfig]
  ///
  /// [raw] — сырые данные из поля `Installer` (без доп. обработки).
  UpdateInstallerConfig parse(Map<String, dynamic>? raw);
}
```

**Преимущества:**
- Простота API — один метод вместо двух
- Настройки парсятся внутри Installer'а по мере необходимости
- Легче тестировать — все параметры в одном месте

### Мердж настроек Installer'а

Настройки Installer'а мерджатся по стандартным правилам API v4:

```yaml
content:
  # Базовые настройки
  - data:
      installer:
        name: inAppUpdate
        update_type: flexible
        stale_days: 5
        
  # Переопределение для unsupported — только update_type
  - when: { app_status_is: unsupported }
    data:
      installer:
        update_type: immediate
        # name и stale_days наследуются из базового правила
```

**Результат для `app_status: unsupported`:**
```yaml
installer:
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
  
  /// Настройки Installer'а
  final UpdateInstallerConfig? installer;
  
  const UpdateContentData({
    this.updateUrl,
    this.title,
    this.description,
    this.installer,
    // ...
  });
}
```

**Важно:** Installer'ы регистрируются на этапе сборки приложения (compile-time), а конфиг определяет какие из них использовать для конкретных источников (runtime). Это позволяет:
- Включить все возможные Installer'ы в сборку
- Гибко управлять их использованием через удалённый конфиг
- Не менять код приложения для изменения стратегии обновления
