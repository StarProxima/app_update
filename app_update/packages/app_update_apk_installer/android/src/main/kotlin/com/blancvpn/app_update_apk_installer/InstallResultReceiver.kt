package com.blancvpn.app_update_apk_installer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log

class InstallResultReceiver : BroadcastReceiver() {
  companion object {
    private const val TAG = "ApkInstallerReceiver"
  }

  override fun onReceive(context: Context, intent: Intent) {
    Log.d(TAG, "onReceive. action=${intent.action} extras=${intent.extras?.keySet()}")
    val status = intent.getIntExtra(
      PackageInstaller.EXTRA_STATUS,
      PackageInstaller.STATUS_FAILURE,
    )

    val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
    Log.d(TAG, "PackageInstaller status=$status msg=$msg")

    if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
      val confirmationIntent = getConfirmationIntent(intent)
      Log.d(TAG, "STATUS_PENDING_USER_ACTION confirmationIntent=${confirmationIntent != null}")
      if (confirmationIntent != null) {
        confirmationIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
          context.startActivity(confirmationIntent)
          Log.d(TAG, "confirmation UI started")
        } catch (e: Exception) {
          Log.e(TAG, "failed to start confirmation activity", e)
        }
      }
      AppUpdateApkInstallerPlugin.dispatchEvent(mapOf("event" to "pendingUserAction"))
      return
    }

    if (status == PackageInstaller.STATUS_SUCCESS) {
      Log.d(TAG, "STATUS_SUCCESS")
      AppUpdateApkInstallerPlugin.dispatchEvent(mapOf("event" to "completed", "message" to msg))
    } else {
      Log.w(TAG, "STATUS_FAILURE status=$status msg=$msg")
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


