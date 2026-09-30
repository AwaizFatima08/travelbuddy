package com.homilabs.travelbuddy.service

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.homilabs.travelbuddy.R
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.DriverLoc
import com.homilabs.travelbuddy.model.Ride
import com.homilabs.travelbuddy.model.RideStatus
import com.homilabs.travelbuddy.util.Geo
import com.homilabs.travelbuddy.util.Prefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch

/**
 * PASSENGER "I'm waiting": keeps a small notification and listens to ONE ride doc
 * (+ its live location doc). Works out the ETA on the phone and fires ONE approach
 * alert (driver < 500 m or ETA < 2 min). No exact alarms, no location of the passenger.
 */
class PassengerWaitService : Service() {

    companion object {
        private const val EXTRA_RIDE = "ride"
        private const val EXTRA_UID = "uid"
        private const val ACTION_STOP = "com.homilabs.travelbuddy.PICKED_UP"
        private const val MAX_WAIT_MS = 90 * 60 * 1000L

        private val _waitingFor = MutableStateFlow<String?>(null)
        val waitingFor: StateFlow<String?> = _waitingFor.asStateFlow()

        fun start(context: Context, rideId: String, uid: String) {
            val i = Intent(context, PassengerWaitService::class.java)
                .putExtra(EXTRA_RIDE, rideId)
                .putExtra(EXTRA_UID, uid)
            ContextCompat.startForegroundService(context, i)
        }

        /** "Picked up" / stop waiting. */
        fun stop(context: Context) {
            context.startService(Intent(context, PassengerWaitService::class.java).setAction(ACTION_STOP))
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null
    private var rideId: String? = null
    private lateinit var prefs: Prefs

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            rideId?.let { prefs.markWaitDismissed(it) }
            finish()
            return START_NOT_STICKY
        }
        val id = intent?.getStringExtra(EXTRA_RIDE)
        val uid = intent?.getStringExtra(EXTRA_UID)
        startInForeground(build(id, "Waiting for your driver", "Waiting for the driver to start the ride"))
        if (id == null || uid == null) {
            finish()
            return START_NOT_STICKY
        }
        if (id != rideId) {
            rideId = id
            watch(id, uid)
        }
        _waitingFor.value = id
        return START_NOT_STICKY
    }

    private fun startInForeground(n: android.app.Notification) {
        val type = when {
            Build.VERSION.SDK_INT >= 34 -> ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> ServiceInfo.FOREGROUND_SERVICE_TYPE_MANIFEST
            else -> 0
        }
        ServiceCompat.startForeground(this, Notif.ID_WAIT, n, type)
    }

    private fun watch(id: String, uid: String) {
        job?.cancel()
        val ticker = flow { while (true) { emit(Unit); delay(30_000) } }
        job = scope.launch {
            runCatching { Repo.loadStops() }
            launch { delay(MAX_WAIT_MS); finish() }
            combine(Repo.rideFlow(id), Repo.locFlow(id), ticker) { r, loc, _ -> r.getOrNull() to loc }
                .collect { (ride, loc) -> update(id, uid, ride, loc) }
        }
    }

    private fun update(id: String, uid: String, ride: Ride?, loc: DriverLoc?) {
        when {
            ride == null -> { finish(); return }
            ride.status == RideStatus.CANCELLED -> {
                Notif.alert(this, id, "Ride cancelled", "Your ${ride.slot.label} ride was cancelled by ${ride.driverName.ifBlank { "the driver" }}.", 2)
                finish(); return
            }
            ride.status == RideStatus.COMPLETED || !ride.isConfirmedPassenger(uid) -> { finish(); return }
        }
        ride!!
        val stop = Repo.stopById(ride.pickupStopId(uid))
        val (title, text) = when {
            ride.status != RideStatus.STARTED || loc == null ->
                "Waiting for ${ride.driverName}" to "The driver hasn't started the ride yet"
            stop == null || (stop.lat == 0.0 && stop.lng == 0.0) ->
                "${ride.driverName} is on the way" to "Your pickup point has no map location, so no ETA"
            else -> {
                val m = Geo.distanceMeters(loc.lat, loc.lng, stop.lat, stop.lng)
                if (Geo.isApproaching(m) && !prefs.alertFired(id)) {
                    prefs.markAlertFired(id)
                    Notif.alert(this, id, "Your ride is ~2 min away", "${ride.driverName} is ${Geo.etaText(m)} from ${stop.name}", 3)
                }
                val stale = Geo.staleText(loc.at)?.let { " · $it" }.orEmpty()
                "${ride.driverName} is on the way" to "Driver ${Geo.etaText(m)} away$stale"
            }
        }
        if (Notif.canPost(this)) {
            try {
                NotificationManagerCompat.from(this).notify(Notif.ID_WAIT, build(id, title, text))
            } catch (_: SecurityException) {
            }
        }
    }

    private fun build(id: String?, title: String, text: String) =
        NotificationCompat.Builder(this, Notif.CH_LIVE)
            .setSmallIcon(R.drawable.ic_stat_car)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(Notif.openRideIntent(this, id, 21))
            .addAction(
                0, "Picked up",
                PendingIntent.getService(
                    this, 22,
                    Intent(this, PassengerWaitService::class.java).setAction(ACTION_STOP),
                    PendingIntent.FLAG_IMMUTABLE
                )
            )
            .build()

    private fun finish() {
        job?.cancel()
        job = null
        rideId = null
        _waitingFor.value = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        _waitingFor.value = null
        super.onDestroy()
    }
}
