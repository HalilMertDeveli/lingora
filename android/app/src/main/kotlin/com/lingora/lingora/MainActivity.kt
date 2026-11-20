package com.lingora.lingora

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The API level, so Android 7–9 get emoji they can draw (lib/core/legacy_emoji.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dilmac/device").setMethodCallHandler { call, result ->
            if (call.method == "sdkInt") result.success(Build.VERSION.SDK_INT) else result.notImplemented()
        }
        // Daily reminders (lib/services/notifications.dart): see [narrowReminderWindows].
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lingora/reminder_window").setMethodCallHandler { call, result ->
            if (call.method != "narrow") return@setMethodCallHandler result.notImplemented()
            val ids = call.argument<List<Number>>("ids").orEmpty()
            val at = call.argument<List<Number>>("at").orEmpty()
            val windowMs = call.argument<Number>("windowMs")?.toLong() ?: DEFAULT_WINDOW_MS
            result.success(narrowReminderWindows(applicationContext, ids.map { it.toInt() }, at.map { it.toLong() }, windowMs))
        }
    }

    companion object {
        const val DEFAULT_WINDOW_MS = 10 * 60 * 1000L

        /**
         * flutter_local_notifications schedules an inexact alarm, which Android may
         * deliver up to an hour after the chosen time (the window is 75% of the time
         * until the alarm, capped at one hour). Exact alarms need SCHEDULE_EXACT_ALARM,
         * which Play does not grant a learning reminder, and which Android revokes on
         * app updates ("lost permission to set exact alarms").
         *
         * So the plugin's own alarm (same PendingIntent: same receiver and request
         * code) is moved into a short [windowMs] window starting at the chosen time
         * with [AlarmManager.setWindow]. A window of 10 minutes or more is not an
         * exact alarm and needs no permission. Returns how many were narrowed.
         */
        fun narrowReminderWindows(context: Context, ids: List<Int>, at: List<Long>, windowMs: Long): Int {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return 0
            var narrowed = 0
            for ((i, id) in ids.withIndex()) {
                val trigger = at.getOrNull(i) ?: continue
                if (trigger <= System.currentTimeMillis()) continue
                val intent = Intent(context, ScheduledNotificationReceiver::class.java)
                // FLAG_NO_CREATE: only an alarm the plugin scheduled (its extras stay).
                val pending = PendingIntent.getBroadcast(
                    context, id, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
                ) ?: continue
                alarms.setWindow(AlarmManager.RTC_WAKEUP, trigger, windowMs, pending)
                narrowed++
            }
            return narrowed
        }
    }
}
