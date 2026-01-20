# in_app_update_installer

`in_app_update_installer` is a Flutter plugin add-on for `app_update` that enables **In App Update installation on Android**.

It provides an `UpdateInstaller` implementation (`InAppUpdateInstaller`) that:
- Uses Google Play In-App Updates
- Supports immediate or flexible update flows
- Emits progress states via a stream

> This package is intended to be used together with `app_update` as an additional installer implementation.

## Getting started

### 1) Add dependency

Add the package to your app.

### 2) Register installer

Pass `InAppUpdateInstaller()` to `UpdateController` (recommended integration point):

```dart
import 'package:app_update/app_update.dart';
import 'package:in_app_update_installer/in_app_update_installer.dart';

final controller = UpdateController(
  updateInstallers: [
    InAppUpdateInstaller(),
    // ...other installers (optional)
  ],
);
```

### 3) Use `updateController.installUpdate(update)`

For updates that have the `in_app_update` installer selected, `InAppUpdateInstaller`
will use Google Play to trigger an in-app update flow.

## Usage (end-to-end)

```dart
import 'package:app_update/app_update.dart';
import 'package:in_app_update_installer/in_app_update_installer.dart';

final controller = UpdateController(
  updateInstallers: [InAppUpdateInstaller()],
);

// 1) Find an update (your app_update flow)
final update = controller.findUpdate(searchConfig).update;
if (update == null) return;

// 2) Start installation
final result = await controller.installUpdate(update);
if (result == null) return;

// 3) Listen to progress and handle confirm/cancel
result.progress.listen((p) async {
  switch (p) {
    case UpdateInstallationDownloading():
      break;

    case UpdateInstallationDownloaded(:final isNeedConfirm):
      if (isNeedConfirm) {
        await controller.confirmUpdateInstallation();
      }
      break;

    case UpdateInstallationExecuting():
      break;

    case UpdateInstallationCompleted():
      break;

    case UpdateInstallationCancelled():
      break;

    case UpdateInstallationFailed(:final message):
      // show error message
      break;
  }
});
```

## Configuration

Optional installer config fields (YAML):

```yaml
installer:
  name: in_app_update
  update_type: flexible # or "immediate"
  require_user_confirm: true
```

If `update_type` is not provided, the installer picks the best available type
(flexible preferred when allowed).