package ru.planer.notes

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Short-lived foreground service that runs the Dart background check
 * (bgServiceMain) while the process is guaranteed to stay unfrozen.
 *
 * The notification is IMPORTANCE_MIN: no sound, no status-bar icon, only
 * visible in the shade for the few seconds the check runs. Dart reports
 * completion over MethodChannel "planer.bg/finish" -> service stops itself.
 */
class BgCheckService : Service() {
    private var engine: FlutterEngine? = null
    private val watchdog = Handler(Looper.getMainLooper())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        watchdog.removeCallbacksAndMessages(null)
        watchdog.postDelayed({ stopAndCleanup() }, 55_000)
        if (engine == null) {
            try {
                val eng = FlutterEngine(applicationContext)
                val channel = MethodChannel(eng.dartExecutor.binaryMessenger, "planer.bg/finish")
                channel.setMethodCallHandler { call, result ->
                    result.success(true)
                    if (call.method == "done") {
                        stopAndCleanup()
                    }
                }
                val entrypoint = DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "bgServiceMain"
                )
                eng.dartExecutor.executeDartEntrypoint(entrypoint)
                engine = eng
            } catch (e: Exception) {
                Log.e(TAG, "engine start failed", e)
                stopAndCleanup()
            }
        }
        return START_NOT_STICKY
    }

    private fun startAsForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Background check",
                    NotificationManager.IMPORTANCE_MIN
                )
                ch.setShowBadge(false)
                ch.setSound(null, null)
                ch.enableVibration(false)
                nm.createNotificationChannel(ch)
            }
        }
        val builder: Notification.Builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Planer")
            .setContentText("Background check")
            .setPriority(Notification.PRIORITY_MIN)
            .setOngoing(true)
        val notification = builder.build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun stopAndCleanup() {
        watchdog.removeCallbacksAndMessages(null)
        val eng = engine
        engine = null
        if (eng != null) {
            try {
                eng.destroy()
            } catch (e: Exception) {
                Log.e(TAG, "engine destroy failed", e)
            }
        }
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        stopSelf()
    }

    override fun onDestroy() {
        watchdog.removeCallbacksAndMessages(null)
        val eng = engine
        engine = null
        if (eng != null) {
            try {
                eng.destroy()
            } catch (_: Exception) {
            }
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "BgCheck"
        private const val CHANNEL_ID = "planer_bg_check"
        private const val NOTIF_ID = 870202
    }
}
