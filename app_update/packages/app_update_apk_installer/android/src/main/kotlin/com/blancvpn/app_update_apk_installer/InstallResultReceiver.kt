package com.blancvpn.app_update_apk_installer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

class InstallResultReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val status = intent.getIntExtra(
      PackageInstaller.EXTRA_STATUS,
      PackageInstaller.STATUS_FAILURE,
    )

    val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

    if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
      val confirmationIntent = getConfirmationIntent(intent)
      if (confirmationIntent != null) {
        confirmationIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(confirmationIntent)
      }
      AppUpdateApkInstallerPlugin.dispatchEvent(mapOf("event" to "pendingUserAction"))
      return
    }

    if (status == PackageInstaller.STATUS_SUCCESS) {
      AppUpdateApkInstallerPlugin.dispatchEvent(mapOf("event" to "completed", "message" to msg))
    } else {
      AppUpdateApkInstallerPlugin.dispatchEvent(
        mapOf(
          "event" to "failed",
          "message" to (msg ?: "PackageInstaller failed with status=$status"),
          "status" to status,
        ),
      )
    }
  }

  @Suppress("DEPRECATION")
  private fun getConfirmationIntent(intent: Intent): Intent? {
    val extras = intent.extras ?: return null
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      extras.getParcelable(Intent.EXTRA_INTENT, Intent::class.java)
    } else {
      extras.getParcelable(Intent.EXTRA_INTENT) as? Intent
    }
  }
}


