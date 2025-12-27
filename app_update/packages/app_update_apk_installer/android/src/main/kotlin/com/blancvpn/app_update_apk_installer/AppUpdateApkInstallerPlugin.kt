package com.blancvpn.app_update_apk_installer

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
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
    private const val TAG = "ApkInstallerPlugin"

    @Volatile
    private var instance: AppUpdateApkInstallerPlugin? = null

    fun dispatchEvent(event: Map<String, Any?>) {
      Log.d(TAG, "dispatchEvent: $event (instance=${instance != null})")
      instance?.sendEvent(event) ?: Log.w(TAG, "dispatchEvent dropped: no instance attached")
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
    Log.d(TAG, "onAttachedToEngine")
    instance = this
    context = flutterPluginBinding.applicationContext

    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "app_update_apk_installer/method")
    methodChannel.setMethodCallHandler(this)

    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "app_update_apk_installer/events")
    eventChannel.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(TAG, "onDetachedFromEngine")
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    eventSink = null
    instance = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    Log.d(TAG, "onMethodCall: ${call.method} args=${call.arguments}")
    when (call.method) {
      "installApk" -> {
        val filePath = call.argument<String>("filePath")
        if (filePath.isNullOrBlank()) {
          result.error("bad_args", "filePath is required", null)
          return
        }
        Log.d(TAG, "installApk requested. filePath=$filePath")
        installApk(filePath)
        result.success(null)
      }

      "cancel" -> {
        Log.d(TAG, "cancel requested")
        cancelRequested = true
        dispatchEvent(mapOf("event" to "cancelRequested"))
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    Log.d(TAG, "onListen. arguments=$arguments sink=${events != null}")
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    Log.d(TAG, "onCancel. arguments=$arguments")
    eventSink = null
  }

  private fun sendEvent(event: Map<String, Any?>) {
    mainHandler.post {
      Log.d(TAG, "sendEvent -> sink: $event (sink=${eventSink != null})")
      eventSink?.success(event)
    }
  }

  private fun installApk(filePath: String) {
    if (installInProgress) {
      Log.w(TAG, "installApk ignored: install already in progress")
      dispatchEvent(mapOf("event" to "failed", "message" to "Another install is already running"))
      return
    }

    installInProgress = true
    cancelRequested = false

    executor.execute {
      try {
        val file = File(filePath)
        Log.d(TAG, "worker started. file.exists=${file.exists()} size=${file.length()}")
        if (!file.exists()) {
          dispatchEvent(mapOf("event" to "failed", "message" to "APK file not found: $filePath"))
          return@execute
        }

        dispatchEvent(mapOf("event" to "installing", "progress" to 0.0))

        val packageInstaller = context.packageManager.packageInstaller
        Log.d(TAG, "PackageInstaller acquired. registering session callback")
        packageInstaller.registerSessionCallback(installSessionCallback, mainHandler)

        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        // Helpful for debugging on some devices/ROMs
        params.setSize(file.length())
        val sessionId = packageInstaller.createSession(params)
        Log.d(TAG, "createSession -> sessionId=$sessionId")
        val session = packageInstaller.openSession(sessionId)
        Log.d(TAG, "openSession ok. sessionId=$sessionId")

        if (cancelRequested) {
          Log.d(TAG, "cancelRequested before write -> abandon sessionId=$sessionId")
          session.abandon()
          dispatchEvent(mapOf("event" to "cancelled"))
          return@execute
        }

        val totalBytes = file.length().coerceAtLeast(0L)
        var writtenBytes = 0L

        Log.d(TAG, "writing apk bytes. totalBytes=$totalBytes")
        session.openWrite("package", 0, totalBytes).use { out ->
          FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
              if (cancelRequested) {
                Log.d(TAG, "cancelRequested during write -> abandon sessionId=$sessionId")
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
        Log.d(TAG, "write complete. writtenBytes=$writtenBytes")

        val intent = Intent(context, InstallResultReceiver::class.java).apply {
          action = "${context.packageName}.APP_UPDATE_APK_INSTALL_COMPLETE"
        }
        Log.d(TAG, "creating PendingIntent for result broadcast. action=${intent.action} receiver=${InstallResultReceiver::class.java.name}")

        val flags =
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
          } else {
            PendingIntent.FLAG_UPDATE_CURRENT
          }

        val pendingIntent = PendingIntent.getBroadcast(context, sessionId, intent, flags)
        Log.d(TAG, "commit session. sessionId=$sessionId")
        session.commit(pendingIntent.intentSender)
        session.close()

        dispatchEvent(mapOf("event" to "committed", "sessionId" to sessionId))
        Log.d(TAG, "commit done. sessionId=$sessionId")
      } catch (e: Exception) {
        Log.e(TAG, "installApk failed", e)
        dispatchEvent(mapOf("event" to "failed", "message" to (e.message ?: "Installation failed")))
      } finally {
        Log.d(TAG, "worker finished. reset state")
        installInProgress = false
        cancelRequested = false
      }
    }
  }
}
