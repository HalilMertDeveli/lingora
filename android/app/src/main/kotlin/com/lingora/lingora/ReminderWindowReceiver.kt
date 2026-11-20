package com.lingora.lingora

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * After a reboot or an app update flutter_local_notifications schedules the
 * reminders again with its inexact alarm (up to an hour late); the app is not
 * running to narrow them (MainActivity.narrowReminderWindows). This receiver
 * waits until the plugin's receiver has done that, reads the plugin's list of
 * scheduled notifications and narrows them the same way.
 */
class ReminderWindowReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACTIONS) return
        val pending = goAsync()
        val app = context.applicationContext
        Thread {
            try {
                Thread.sleep(PLUGIN_GRACE_MS)
                val (ids, at) = scheduled(app)
                MainActivity.narrowReminderWindows(app, ids, at, MainActivity.DEFAULT_WINDOW_MS)
            } catch (_: Exception) {
                // The plugin's inexact alarms stay: late, but they still come.
            } finally {
                pending.finish()
            }
        }.start()
    }

    companion object {
        private val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
        )
        private const val PLUGIN_GRACE_MS = 5_000L

        /** flutter_local_notifications' own store of zoned notifications. */
        private const val STORE = "scheduled_notifications"

        fun scheduled(context: Context): Pair<List<Int>, List<Long>> {
            val json = context.getSharedPreferences(STORE, Context.MODE_PRIVATE).getString(STORE, null)
                ?: return Pair(emptyList(), emptyList())
            val ids = mutableListOf<Int>()
            val at = mutableListOf<Long>()
            val list = JSONArray(json)
            for (i in 0 until list.length()) {
                val n = list.optJSONObject(i) ?: continue
                val date = n.optString("scheduledDateTime").ifEmpty { null } ?: continue
                val zone = n.optString("timeZoneName").ifEmpty { "UTC" }
                ids += n.optInt("id")
                at += LocalDateTime.parse(date).atZone(ZoneId.of(zone)).toInstant().toEpochMilli()
            }
            return Pair(ids, at)
        }
    }
}
