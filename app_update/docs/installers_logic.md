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

  /// Освободить ресурсы контроллера и зарегистрированных installer-ов
  void dispose();
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
  final Stream<UpdateInstallationProgress> progressStream;
  
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
  /// Прогресс от 0.0 до 1.0. null если нет возможности его получить
  final double? progress;

  const UpdateInstallationExecuting({
    this.progress,
  });
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
  /// [config] — настройки Installer'а из YAML
  /// Возвращает Stream для отслеживания прогресса
  Stream<UpdateInstallationProgress> install(
    Update update,
    UpdateInstallerConfig config,
  );
  
  /// Продолжает установку после состояния Downloaded
  /// Вызывается контроллером при controller.confirmUpdateInstallation()
  Future<void> confirmInstallation();
  
  /// Отменяет текущее обновление
  Future<void> cancelInstallation();

  /// Освобождает ресурсы Installer'а (стримы, подписки, временные файлы и т.п.)
  /// Вызывается контроллером при controller.dispose()
  void dispose();
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

## Конфигурация Installer'ов через YAML API и путь конфига внутри UpdateController

`installers` - это словарь имя_установщика:модель_конфига, который является полем settings. Благодаря этому мы сохраняем возможность гибко настраивать установщики, так как они подчиняются базовым правилам, а также иметь несколько вариантов уставщиков для одного обновления. 

Везде, где мы можем определять правила для settings можно теперь определять и installers. То есть мы делаем в модели UpdateSettingsConfig новое поле installers типа Map<UpdateInstallerName, UpdateInstallerConfig> и обрабатываем его как и любые другие поля, используя глубокий мерж полей для одинаковых имён установщиков.

Для того, чтобы иметь возможность правильно распарсить конфиг каждого из installer-ов, в parser зарегистированные installer-ы будут передавать свою реализацию UpdateInstallerConfigParser, возвращающую свою реализацию UpdateInstallerConfig. Если у parser не будет нужного UpdateInstallerConfigParser для имени инсталлера, то он просто пропускается.

Аналогично, если инсталлер зарегистирован в UpdateController, но не указан в апи, то никаких обновления его не будут использовать, так как UpdateInstallerConfigParser ни разу не будет использован. Таким образом для installer-ов нужно регистрация в двух местах: в приложении и в api.

Далее на этапе resolve мы объединяем все правила в конкретные settings и чистим их от лишних installer-ов при помощи их метода support, после чего передаём модельку Update со всеми возможными доступными установщиками обновления.

Далее юзер должен передать эту модельку в метод install, в котором контроллер выберет самый подходящий установщик и запустит его. Возможно, используя даже fallback логику

Отдельно отмечу, что updateUrl из content не должен использоваться в installer-ах как ссылка для установки. Это отдельное поле, имеющее свой смысл.

------

Фетчеры сторов, которые генерируют конфиги распаршенные, пусть будут форкаться в плагинах и дополняться конфигами этих инсталлеров