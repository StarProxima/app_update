# app_update_apk_installer

Flutter plugin-addition for [`app_update`] that provides an Android APK installer:

- **Dart side**: downloads APK from `update.content.updateUrl` with progress
- **Android side (Kotlin)**: installs downloaded APK via `PackageInstaller`

## Getting Started

### Usage (installer)

```dart
import 'package:app_update/app_update.dart';
import 'package:app_update_apk_installer/app_update_apk_installer.dart';

// Set up installer in controller
final controller = UpdateController(
    installers: [
        ApkUpdateInstaller(),
    ]
);

// TODO доделать

```

> Note: the intended integration is through `UpdateController.installUpdate()` once it is wired to pass installer configs and manage lifecycle.

