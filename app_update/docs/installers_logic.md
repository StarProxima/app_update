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

## Конфигурация Installer'ов через YAML API

### Концепция

`installer` интегрируется в API v4 как **отдельный тип правил**, на одном уровне с
`content`, `settings` и `app_settings`. Это решает две проблемы:

Мысли о том, как конфиг устроить. Читать много! Так что читай как будет время

Короче, у нас есть основные сущности:
release, source, platform.
Выдавая Update финальный мы берём нынешний platform, находим лучший release и крепим к нему подходящий source (если очень просто и без правил)

Нам необходимо добавить в эту схему ещё одну сущность - intaller
По логике сборке, мы должны для нынешнего platform находить также лучший release, крепим к нему подходящий source и на основании platform и source выбранных, пикается installer. То есть схема зависимостей такая:

platform - release - source
    |                  |
      \              /
          installer 

Что есть цикл, что хуёво. Но так как у нас есть логика обхода, получаем то есть типо дерево (циклов нет, но только из-за однонаправленности):


platform -> release -> source
    |                    |
      \                /
        >  installer <

Так что результат решаемый. 

Если идти согласно логике api, нам необходимо на глобальный уровень вынести installer и сделать возможность его определять у platform и source. То есть получим, что installer можно будет определить в местах:
- глобальный корень (installer: рядом с content/settings/app_settings и т.д.);
- глобальный источник (sources[*].installer);
- глобальная платформа источника (sources[*].platforms[*].installer);
- источник релиза (releases[*].sources[*].installer);
- платформа релиза (releases[*].sources[*].platforms[*].installer).


Логика тогда такая: 
При парсинге парсим только те инсталлеры, которые зарегистрированы в приложении. Остальные буквально игнорируем. Парсим их при помощи их реализации UpdateInstallerConfigParser. Получаем для каждого инсталлера их реализацию UpdateInstallerConfig.
В линкере как обычно линкуем всех со всеми + инсталлеры подходящие. То есть в UpdateData появляется поле UpdateInstallerConfig? installer. 
Именно с "?", потому что также создаёмы и варианты UpdateData, где инсталлер null. Во время searchFull UpdateData с null на месте инсталлера будут уходить вниз по приоритетности, чтобы было более приоритетно запустить какой-то крутой installer.
Если же среди инсталлеров будет StoreRedirect, то он будет забирать на себя считай что все UpdateData, так что обычно будет приоритет: крутые инсталлеры -> StoreRedirect -> отсутствие installer-а.
В общем, во время searchFull находим самый подходящий вариант updateData. Приоритет installer-ов аналогично сурсам в UpdateSearchData задаём. То есть мы не предоставляем пользователю список доступных installer-ов, а выдаём наиболее приоритетный - по аналогии, как мы делаем с сурсами и прочим.
Далее при resolve всё как обычно.
В итоге получаем готовую модельку Update с UpdateInstallerConfig. При запуске installUpdate, мы по UpdateInstallerConfig.name берём UpdateInstaller и в его install закидываем Update и его настройки в UpdateInstallerConfig. Далее магия установки.

В UpdateData и Update должна быть именно UpdateInstallerConfig, а не UpdateInstallerName (по аналогии с source), потому что source по сути дела хранит в себе только имя, а вот installer, обычно, состоит из большего числа полей.
Поле updateUrl так-то просто часть UpdateContentConfig. И пусть только им и остаётся. Installer не будет использовать его, все нужные ссылки пусть получает из конфига
