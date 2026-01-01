# app_update_apk_installer

`app_update_apk_installer` is a Flutter plugin add-on for `app_update` that enables **direct APK download + installation on Android**.

It provides an `UpdateInstaller` implementation (`ApkUpdateInstaller`) that:
- Downloads an APK from `update.content.updateUrl` TODO поменять как по апи договоримся
- Triggers Android’s package installation flow
- Emits download and installation progress via a stream

> This package is intended to be used together with `app_update` as an additional installer implementation.

## Getting started

### 1) Add dependency

Add the package to your app.

### 2) Android manifest permissions

To be able to install APKs, your app must have the required Android permissions.

Add this to your app’s `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
  <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
  ...
</manifest>
```

### 3) Register installer

Pass `ApkUpdateInstaller()` to `UpdateController` (recommended integration point):

```dart
import 'package:app_update/app_update.dart';
import 'package:app_update_apk_installer/app_update_apk_installer.dart';

final controller = UpdateController(
  updateInstallers: [
    ApkUpdateInstaller(),
    // ...other installers (optional)
  ],
);
```

Only app versions with a registered `ApkUpdateInstaller` can use it.

### 4) Provide an APK URL

Make sure your update config resolves `update.content.updateUrl` to a direct `.apk` URL (not an HTML page).

### 5) Use `updateController.installUpdate(update)`

For updates that have the `apk_install` installer selected, `ApkUpdateInstaller` will be used: it silently downloads the `.apk` file and then installs it after the user grants permission.

## Usage (end-to-end)

This is a typical flow:

```dart
import 'package:app_update/app_update.dart';
import 'package:app_update_apk_installer/app_update_apk_installer.dart';

final controller = UpdateController(
  updateInstallers: [ApkUpdateInstaller()],
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
    case UpdateInstallationDownloading(:final progress):
      // progress: 0..1
      break;

    case UpdateInstallationDownloaded(:final isNeedConfirm):
      if (isNeedConfirm) {
        // Ask user for confirmation, then:
        await controller.confirmUpdateInstallation();
      }
      break;

    case UpdateInstallationExecuting(:final progress):
      // install progress: 0..1 (may be null on some devices)
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

## APK URL requirements

`update.content.updateUrl` must point to a **direct `.apk` file download**.

If the URL points to an HTML page (for example, a GitHub release page, a login page, a “download” landing page, or a CDN error page), the installer will download that HTML and Android installation will fail.

Recommended checks:
- The URL should end with `.apk`
- The server should return the APK bytes (not HTML/JSON)
- If your server requires authentication, provide a Dio client configured with the required headers/tokens any other options

## Features

- **APK download**
  - Downloads the APK from `update.content.updateUrl`
  - Emits `UpdateInstallationDownloading` state with progress and bytes
  - Can download the APK silently in the background
  - Can use your Dio client
  - Can retry a download if possible

- **APK integrity checks**
  - Rejects non-APK downloads (e.g., HTML/JSON error pages instead of an APK)
  - Optional SHA-256 verification

- **APK backup caching**
  - Caches a apk backup copy after downloading
  - If the installation is not finished and you request it again, the installer can reuse that backup
  - Clears old backups

- **Two or one step install flow**
  - Can wait for explicit confirmation before installing (for example, to request permissions first)
  - Or can do all steps by one call without user confirmation

- **Cancellation at any stage**
  - Can cancel the flow during download, after download, and during installation

- **Android installation**
  - Uses Android `PackageInstaller`
  - Emits `UpdateInstallationExecuting` with install progress (when available)
  - Guides the user through required permission flows when needed (e.g. “Install unknown apps”)

## Example app

This repository contains an example sandbox app in [`app_update/example/`].  
To test the installer UI:

1. Run the example on an Android device
2. Open **“APK Installer”** from the Home screen
3. Paste a direct `.apk` URL and use **Start / Confirm / Cancel**

Made especially for Yadda.io.

