// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

package pl.wattbyte.system

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Native "charging session completed" alert, posted by [ChargingWorker].
 * The switch and the localized text are pushed from Dart settings.
 */
object ChargingNotifier {
    private const val PREFS = "wattbyte_native"
    private const val CHANNEL = "wattbyte.charging"
    private const val ID = 1001

    fun configure(
        ctx: Context,
        enabled: Boolean,
        title: String,
        body: String,
        channelName: String,
        channelDescription: String,
    ) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("enabled", enabled)
            .putString("title", title)
            .putString("body", body)
            .putString("channelName", channelName)
            .putString("channelDescription", channelDescription)
            .apply()
    }

    /** A plug-in shorter than this is not a charging session worth announcing. */
    const val MIN_SESSION_MS = 2 * 60_000L

    /** Remembers when the current plugged run started (survives the 9-minute worker chain). */
    fun onSample(ctx: Context, plugged: Boolean, timeMs: Long) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (plugged && p.getLong("plugged_since", 0L) == 0L) {
            p.edit().putLong("plugged_since", timeMs).apply()
        }
    }

    fun sessionCompleted(ctx: Context) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val since = p.getLong("plugged_since", 0L)
        p.edit().putLong("plugged_since", 0L).apply()
        if (since == 0L || System.currentTimeMillis() - since < MIN_SESSION_MS) return
        if (!p.getBoolean("enabled", false)) return
        val compat = NotificationManagerCompat.from(ctx)
        if (!compat.areNotificationsEnabled()) return

        // The channel's name and description are shown in the system settings, so they
        // are localized by the app (pushed with the alert text); the native side has no
        // text of its own. Until the app has pushed them, the (localized) title is the
        // best readable name there is.
        val channelName = p.getString("channelName", null)?.takeIf { it.isNotEmpty() }
            ?: p.getString("title", null)?.takeIf { it.isNotEmpty() }
            ?: CHANNEL
        val channel = NotificationChannel(CHANNEL, channelName, NotificationManager.IMPORTANCE_DEFAULT)
        p.getString("channelDescription", null)?.takeIf { it.isNotEmpty() }?.let {
            channel.description = it
        }
        val manager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val pending = launch?.let {
            PendingIntent.getActivity(
                ctx, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
        val notification = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_wb_bolt)
            .setContentTitle(p.getString("title", "") ?: "")
            .setContentText(p.getString("body", ""))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        try {
            compat.notify(ID, notification)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted.
        }
    }
}
