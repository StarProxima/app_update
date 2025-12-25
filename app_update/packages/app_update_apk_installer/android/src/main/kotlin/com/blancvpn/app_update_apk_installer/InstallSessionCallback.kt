package com.blancvpn.app_update_apk_installer

import android.content.pm.PackageInstaller

class InstallSessionCallback : PackageInstaller.SessionCallback() {
  override fun onCreated(sessionId: Int) {}
  override fun onBadgingChanged(sessionId: Int) {}
  override fun onActiveChanged(sessionId: Int, active: Boolean) {}
  override fun onFinished(sessionId: Int, success: Boolean) {}

  override fun onProgressChanged(sessionId: Int, progress: Float) {
    // progress: 0..1
    AppUpdateApkInstallerPlugin.dispatchEvent(
      mapOf(
        "event" to "installing",
        "sessionId" to sessionId,
        "progress" to progress.toDouble(),
      ),
    )
  }
}


