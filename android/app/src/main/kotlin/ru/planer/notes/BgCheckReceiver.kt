package ru.planer.notes

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Native 3-minute alarm chain for background notifications of "Obshchie".
 *
 * Why not android_alarm_manager_plus: its JobIntentService releases the job
 * before the Dart engine finishes booting (onHandleWork sees !isRunning and
 * only queues the intent), and HiOS re-freezes the process right after the
 * job ends - the queued Dart callback then never runs until the user opens
 * the app. Here the receiver re-arms the chain natively and starts a short
 * foreground service that keeps the process alive until the Dart check ends.
 */
object BgScheduler {
    private const val TAG = "BgCheck"
    private const val REQ_CODE = 870201
    private const val INTERVAL_MS = 3 * 60 * 1000L

    fun scheduleNext(context: Context) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, BgCheckReceiver::class.java)
            val pi = PendingIntent.getBroadcast(
                context,
                REQ_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val at = System.currentTimeMillis() + INTERVAL_MS
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: Exception) {
            Log.e(TAG, "scheduleNext failed", e)
        }
    }
}

class BgCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Chain lives in native code - survives even if the check fails.
        BgScheduler.scheduleNext(context)
        try {
            val svc = Intent(context, BgCheckService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(svc)
            } else {
                context.startService(svc)
            }
        } catch (e: Exception) {
            Log.e("BgCheck", "start BgCheckService failed", e)
        }
    }
}
