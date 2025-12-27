package com.blancvpn.app_update_apk_installer

import android.content.pm.PackageInstaller
import android.util.Log

class InstallSessionCallback : PackageInstaller.SessionCallback() {
  companion object {
    private const val TAG = "ApkInstallerSession"
  }

  override fun onCreated(sessionId: Int) {}
  override fun onBadgingChanged(sessionId: Int) {}
  override fun onActiveChanged(sessionId: Int, active: Boolean) {}
  override fun onFinished(sessionId: Int, success: Boolean) {}

  override fun onProgressChanged(sessionId: Int, progress: Float) {
    Log.d(TAG, "onProgressChanged sessionId=$sessionId progress=$progress")
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


