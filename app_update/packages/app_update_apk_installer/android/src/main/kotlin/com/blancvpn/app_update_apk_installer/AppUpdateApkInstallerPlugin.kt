package com.blancvpn.app_update_apk_installer

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors

/** AppUpdateApkInstallerPlugin */
class AppUpdateApkInstallerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
  companion object {
    @Volatile
    private var instance: AppUpdateApkInstallerPlugin? = null

    fun dispatchEvent(event: Map<String, Any?>) {
      instance?.sendEvent(event)
    }
  }

  private val mainHandler = Handler(Looper.getMainLooper())
  private val executor = Executors.newSingleThreadExecutor()

  private lateinit var context: Context
  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel: EventChannel

  @Volatile
  private var eventSink: EventChannel.EventSink? = null

  @Volatile
  private var installInProgress = false

  @Volatile
  private var cancelRequested = false

  private val installSessionCallback = InstallSessionCallback()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    instance = this
    context = flutterPluginBinding.applicationContext

    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "app_update_apk_installer/method")
    methodChannel.setMethodCallHandler(this)

    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "app_update_apk_installer/events")
    eventChannel.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    eventSink = null
    instance = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "installApk" -> {
        val filePath = call.argument<String>("filePath")
        if (filePath.isNullOrBlank()) {
          result.error("bad_args", "filePath is required", null)
          return
        }
        installApk(filePath)
        result.success(null)
      }

      "cancel" -> {
        cancelRequested = true
        dispatchEvent(mapOf("event" to "cancelRequested"))
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  private fun sendEvent(event: Map<String, Any?>) {
    mainHandler.post {
      eventSink?.success(event)
    }
  }

  private fun installApk(filePath: String) {
    if (installInProgress) {
      dispatchEvent(mapOf("event" to "failed", "message" to "Another install is already running"))
      return
    }

    installInProgress = true
    cancelRequested = false

    executor.execute {
      try {
        val file = File(filePath)
        if (!file.exists()) {
          dispatchEvent(mapOf("event" to "failed", "message" to "APK file not found: $filePath"))
          return@execute
        }

        dispatchEvent(mapOf("event" to "installing", "progress" to 0.0))

        val packageInstaller = context.packageManager.packageInstaller
        packageInstaller.registerSessionCallback(installSessionCallback, mainHandler)

        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val sessionId = packageInstaller.createSession(params)
        val session = packageInstaller.openSession(sessionId)

        if (cancelRequested) {
          session.abandon()
          dispatchEvent(mapOf("event" to "cancelled"))
          return@execute
        }

        val totalBytes = file.length().coerceAtLeast(0L)
        var writtenBytes = 0L

        session.openWrite("package", 0, totalBytes).use { out ->
          FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
              if (cancelRequested) {
                session.abandon()
                dispatchEvent(mapOf("event" to "cancelled"))
                return@execute
              }

              val read = input.read(buffer)
              if (read <= 0) break
              out.write(buffer, 0, read)
              writtenBytes += read.toLong()
              if (totalBytes > 0) {
                session.setStagingProgress(writtenBytes.toFloat() / totalBytes.toFloat())
              }
            }
            session.fsync(out)
          }
        }

        val intent = Intent(context, InstallResultReceiver::class.java).apply {
          action = "${context.packageName}.APP_UPDATE_APK_INSTALL_COMPLETE"
        }

        val flags =
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
          } else {
            PendingIntent.FLAG_UPDATE_CURRENT
          }

        val pendingIntent = PendingIntent.getBroadcast(context, sessionId, intent, flags)
        session.commit(pendingIntent.intentSender)
        session.close()

        dispatchEvent(mapOf("event" to "committed", "sessionId" to sessionId))
      } catch (e: Exception) {
        dispatchEvent(mapOf("event" to "failed", "message" to (e.message ?: "Installation failed")))
      } finally {
        installInProgress = false
        cancelRequested = false
      }
    }
  }
}
