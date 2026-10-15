package com.homilabs.travelbuddy.service

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.homilabs.travelbuddy.MainActivity
import com.homilabs.travelbuddy.R

object Notif {
    const val CH_LIVE = "ride_live"      // quiet, ongoing (foreground services)
    const val CH_ALERT = "ride_alert"    // sound: approach alert, ride cancelled

    const val ID_DRIVER = 1001
    const val ID_WAIT = 1002
    const val ID_ALERT_BASE = 2000

    const val EXTRA_OPEN_RIDE = "open_ride"

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CH_LIVE, "Active ride", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while you share your location or wait for a driver"
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_ALERT, "Ride alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Your driver is about 2 minutes away, or a ride was cancelled"
            }
        )
    }

    fun canPost(context: Context) =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    fun openRideIntent(context: Context, rideId: String?, requestCode: Int): PendingIntent {
        val i = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(EXTRA_OPEN_RIDE, rideId)
        return PendingIntent.getActivity(
            context, requestCode, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** A normal one-off notification with sound. */
    fun alert(context: Context, rideId: String, title: String, text: String, idOffset: Int) {
        if (!canPost(context)) return
        val n = NotificationCompat.Builder(context, CH_ALERT)
            .setSmallIcon(R.drawable.ic_stat_car)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setContentIntent(openRideIntent(context, rideId, rideId.hashCode() + idOffset))
            .build()
        try {
            NotificationManagerCompat.from(context).notify(ID_ALERT_BASE + idOffset, n)
        } catch (_: SecurityException) {
        }
    }
}
