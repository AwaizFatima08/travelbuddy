package com.homilabs.travelbuddy.service

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.homilabs.travelbuddy.R
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.util.Locator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Shares the DRIVER's location while a ride is STARTED.
 * - visible notification the whole time (foreground service, type=location)
 * - writes rides/{id}/live/loc at most every 30 s, and only after moving >= 100 m
 * - stops on Complete / Cancel / "Stop sharing", or automatically 45 min after the ride started
 * No background-location permission: it only runs while this notification is showing.
 */
class DriverLocationService : Service() {

    companion object {
        private const val EXTRA_RIDE = "ride"
        private const val EXTRA_PASSENGERS = "passengers"
        private const val EXTRA_STARTED_MS = "started_ms"
        private const val ACTION_STOP = "com.homilabs.travelbuddy.STOP_SHARING"

        const val MAX_SHARE_MS = 45 * 60 * 1000L
        private const val MIN_WRITE_INTERVAL_MS = 30_000L
        private const val MIN_MOVE_METERS = 100f

        private val _sharingRide = MutableStateFlow<String?>(null)
        /** Ride id currently being shared, or null. */
        val sharingRide: StateFlow<String?> = _sharingRide.asStateFlow()

        /** [startedAtMs] = wall-clock time the ride was started (for the 45-min limit). */
        fun start(context: Context, rideId: String, passengers: Int, startedAtMs: Long) {
            if (!Locator.hasPermission(context)) return
            val i = Intent(context, DriverLocationService::class.java)
                .putExtra(EXTRA_RIDE, rideId)
                .putExtra(EXTRA_PASSENGERS, passengers)
                .putExtra(EXTRA_STARTED_MS, startedAtMs)
            ContextCompat.startForegroundService(context, i)
        }

        fun stop(context: Context) {
            context.startService(Intent(context, DriverLocationService::class.java).setAction(ACTION_STOP))
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var fused: FusedLocationProviderClient
    private var rideId: String? = null
    private var lastWritten: Location? = null
    private var lastWriteElapsed = 0L

    private val autoStop = Runnable {
        val id = rideId
        stopSharing()
        if (id != null) Notif.alert(
            this, id, "Location sharing stopped",
            "TravelBuddy stopped sharing after 45 minutes. Tap Complete when you arrive.", 1
        )
    }

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            result.lastLocation?.let(::onLocation)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        fused = LocationServices.getFusedLocationProviderClient(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSharing()
            return START_NOT_STICKY
        }
        val id = intent?.getStringExtra(EXTRA_RIDE)
        val passengers = intent?.getIntExtra(EXTRA_PASSENGERS, 0) ?: 0
        val startedMs = intent?.getLongExtra(EXTRA_STARTED_MS, System.currentTimeMillis()) ?: System.currentTimeMillis()
        val remaining = MAX_SHARE_MS - (System.currentTimeMillis() - startedMs)

        // Must call startForeground promptly after startForegroundService().
        startInForeground(buildNotification(id, passengers))

        if (id == null || remaining <= 0 || !Locator.hasPermission(this)) {
            stopSharing()
            return START_NOT_STICKY
        }
        if (rideId != id) {
            rideId = id
            lastWritten = null
            beginUpdates()
        }
        handler.removeCallbacks(autoStop)
        handler.postDelayed(autoStop, remaining)
        _sharingRide.value = id
        return START_NOT_STICKY
    }

    private fun startInForeground(n: android.app.Notification) {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
        ServiceCompat.startForeground(this, Notif.ID_DRIVER, n, type)
    }

    @SuppressLint("MissingPermission") // checked in onStartCommand
    private fun beginUpdates() {
        fused.removeLocationUpdates(callback)
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 15_000L)
            .setMinUpdateIntervalMillis(10_000L)
            .build()
        fused.requestLocationUpdates(req, callback, Looper.getMainLooper())
    }

    private fun onLocation(loc: Location) {
        val id = rideId ?: return
        val now = SystemClock.elapsedRealtime()
        val prev = lastWritten
        val shouldWrite = prev == null ||
            (now - lastWriteElapsed >= MIN_WRITE_INTERVAL_MS && loc.distanceTo(prev) >= MIN_MOVE_METERS)
        if (!shouldWrite) return
        Repo.writeDriverLoc(id, loc.latitude, loc.longitude)
        lastWritten = loc
        lastWriteElapsed = now
    }

    private fun buildNotification(rideId: String?, passengers: Int) =
        NotificationCompat.Builder(this, Notif.CH_LIVE)
            .setSmallIcon(R.drawable.ic_stat_car)
            .setContentTitle("Ride in progress")
            .setContentText(
                "TravelBuddy is sharing your location with $passengers " +
                    if (passengers == 1) "passenger" else "passengers"
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setContentIntent(Notif.openRideIntent(this, rideId, 11))
            .addAction(
                0, "Stop sharing",
                android.app.PendingIntent.getService(
                    this, 12,
                    Intent(this, DriverLocationService::class.java).setAction(ACTION_STOP),
                    android.app.PendingIntent.FLAG_IMMUTABLE
                )
            )
            .build()

    private fun stopSharing() {
        handler.removeCallbacks(autoStop)
        fused.removeLocationUpdates(callback)
        rideId?.let { id -> scope.launch { Repo.clearDriverLoc(id) } }
        rideId = null
        _sharingRide.value = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStop)
        fused.removeLocationUpdates(callback)
        _sharingRide.value = null
        super.onDestroy()
    }
}
