package com.homilabs.travelbuddy.ui.rides

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.DriverLoc
import com.homilabs.travelbuddy.model.Ride
import com.homilabs.travelbuddy.model.RideStatus
import com.homilabs.travelbuddy.model.RideType
import com.homilabs.travelbuddy.model.SeatStatus
import com.homilabs.travelbuddy.model.UserProfile
import com.homilabs.travelbuddy.service.AutoWait
import com.homilabs.travelbuddy.service.DriverLocationService
import com.homilabs.travelbuddy.service.Notif
import com.homilabs.travelbuddy.service.PassengerWaitService
import com.homilabs.travelbuddy.ui.BackTopBar
import com.homilabs.travelbuddy.ui.CallButton
import com.homilabs.travelbuddy.ui.ConfirmDialog
import com.homilabs.travelbuddy.ui.EmptyNote
import com.homilabs.travelbuddy.ui.ErrorNote
import com.homilabs.travelbuddy.ui.LabeledValue
import com.homilabs.travelbuddy.ui.Loading
import com.homilabs.travelbuddy.ui.ScreenColumn
import com.homilabs.travelbuddy.ui.SeatPill
import com.homilabs.travelbuddy.ui.SectionTitle
import com.homilabs.travelbuddy.ui.StatusPill
import com.homilabs.travelbuddy.ui.prettyDate
import com.homilabs.travelbuddy.ui.toast
import com.homilabs.travelbuddy.util.Geo
import com.homilabs.travelbuddy.util.Locator
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch

@Composable
fun RideScreen(rideId: String, me: UserProfile, onBack: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    // A listener on this ONE ride doc while the screen is open.
    val res by remember(rideId) { Repo.rideFlow(rideId) }.collectAsStateWithLifecycle(initialValue = null)
    val ride = res?.getOrNull()
    val isDriver = ride?.isDriver(me.uid) == true
    val isPassenger = ride?.isConfirmedPassenger(me.uid) == true
    val listenLoc = ride?.status == RideStatus.STARTED && (isDriver || isPassenger)
    val loc by remember(rideId, listenLoc) { if (listenLoc) Repo.locFlow(rideId) else flowOf(null) }
        .collectAsStateWithLifecycle(initialValue = null)

    val sharing by DriverLocationService.sharingRide.collectAsState()
    val waiting by PassengerWaitService.waitingFor.collectAsState()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(20_000); now = System.currentTimeMillis() } }

    var confirm by remember { mutableStateOf<Pair<String, () -> Unit>?>(null) }
    var busy by remember { mutableStateOf(false) }

    fun act(done: String?, block: suspend () -> Unit) {
        busy = true
        scope.launch {
            try { block(); done?.let { ctx.toast(it) } } catch (e: Exception) { ctx.toast(Repo.friendly(e)) } finally { busy = false }
        }
    }

    // Permission prompts (location for the driver, notifications for waiting).
    var afterLocationGranted by remember { mutableStateOf<(() -> Unit)?>(null) }
    val locLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (Locator.hasPermission(ctx)) afterLocationGranted?.invoke()
        else ctx.toast("Location permission is needed to share your position with passengers.")
        afterLocationGranted = null
    }
    var afterNotifGranted by remember { mutableStateOf<(() -> Unit)?>(null) }
    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        afterNotifGranted?.invoke(); afterNotifGranted = null
    }
    fun withLocation(block: () -> Unit) {
        if (Locator.hasPermission(ctx)) block()
        else {
            afterLocationGranted = block
            locLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
        }
    }
    fun withNotifications(block: () -> Unit) {
        if (Build.VERSION.SDK_INT < 33 || Notif.canPost(ctx)) block()
        else { afterNotifGranted = block; notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }
    }

    // Keep the services in step with the ride.
    LaunchedEffect(ride?.status, sharing, isDriver) {
        val r = ride ?: return@LaunchedEffect
        if (r.isFinished && sharing == r.id) DriverLocationService.stop(ctx)
        if (isPassenger) AutoWait.maybeStart(ctx, r, me.uid)
    }

    Scaffold(topBar = { BackTopBar("Ride", onBack) }) { pad ->
        when {
            res == null -> Loading(Modifier.padding(pad))
            res!!.isFailure -> ScreenColumn(Modifier.padding(pad)) { ErrorNote(res!!.exceptionOrNull()?.message) }
            ride == null -> ScreenColumn(Modifier.padding(pad)) { EmptyNote("This ride was removed.") }
            else -> ScreenColumn(Modifier.padding(pad)) {
                RideHeader(ride)

                // ---------------- live location / ETA
                if (ride.status == RideStatus.STARTED && (isDriver || isPassenger)) {
                    LiveCard(ride, me, loc, now, isDriver, sharing == ride.id)
                }

                // ---------------- people
                SectionTitle("People")
                PersonRow(
                    "Driver",
                    if (ride.hasDriver) ride.driverName else "Not taken yet",
                    ride.driverPhone.takeIf { !isDriver && ride.hasDriver },
                )
                if (ride.type == RideType.REQUEST) {
                    PersonRow("Passenger", ride.posterName, ride.posterPhone.takeIf { !ride.isPoster(me.uid) })
                }

                // ---------------- seat requests (OFFER)
                if (ride.type == RideType.OFFER) {
                    SectionTitle("Seats: ${ride.acceptedCount} of ${ride.totalSeats} taken")
                    val reqs = ride.requests.values.sortedBy { it.status.ordinal }
                    if (reqs.isEmpty()) Text("No seat requests yet.", style = MaterialTheme.typography.bodyMedium)
                    reqs.forEach { r ->
                        val visible = isDriver || r.uid == me.uid || (isPassenger && r.status == SeatStatus.ACCEPTED)
                        if (!visible) return@forEach
                        Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(r.name, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                                    SeatPill(r.status)
                                }
                                Text("Pickup: ${Repo.stopById(r.stopId)?.name ?: ride.stopName}", style = MaterialTheme.typography.bodySmall)
                                if (isDriver && !ride.isFinished && ride.status != RideStatus.STARTED) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    if (r.status != SeatStatus.ACCEPTED) Button(
                                        enabled = !busy && (ride.seatsLeft > 0),
                                        onClick = { act("${r.name} accepted") { Repo.decideSeat(ride.id, r.uid, true) } },
                                    ) { Text("Accept") }
                                    if (r.status != SeatStatus.DECLINED) OutlinedButton(
                                        enabled = !busy,
                                        onClick = { act("${r.name} declined") { Repo.decideSeat(ride.id, r.uid, false) } },
                                    ) { Text(if (r.status == SeatStatus.ACCEPTED) "Remove" else "Decline") }
                                    CallButton(r.phone)
                                } else if (isDriver) CallButton(r.phone)
                            }
                        }
                    }
                }

                HorizontalDivider(Modifier.padding(vertical = 8.dp))

                // ---------------- actions
                when {
                    ride.isFinished -> Text("This ride is ${ride.status.name.lowercase()}.", style = MaterialTheme.typography.bodyLarge)

                    isDriver -> DriverActions(
                        ride = ride, busy = busy, sharing = sharing == ride.id,
                        onStart = {
                            withLocation {
                                act("Ride started — sharing your location") {
                                    Repo.setRideStatus(ride.id, RideStatus.STARTED)
                                    DriverLocationService.start(ctx, ride.id, ride.passengerCount, System.currentTimeMillis())
                                }
                            }
                        },
                        onResume = {
                            withLocation {
                                val started = ride.startedAt?.toDate()?.time ?: System.currentTimeMillis()
                                DriverLocationService.start(ctx, ride.id, ride.passengerCount, started)
                            }
                        },
                        onComplete = {
                            act("Ride completed. Thank you!") {
                                DriverLocationService.stop(ctx)
                                Repo.clearDriverLoc(ride.id)
                                Repo.setRideStatus(ride.id, RideStatus.COMPLETED)
                            }
                        },
                        onCancel = {
                            confirm = "Cancel this ride? Your passengers will see it as cancelled." to {
                                act("Ride cancelled") {
                                    DriverLocationService.stop(ctx)
                                    Repo.clearDriverLoc(ride.id)
                                    Repo.setRideStatus(ride.id, RideStatus.CANCELLED)
                                }
                            }
                        },
                    )

                    ride.isPoster(me.uid) -> { // REQUEST poster (passenger)
                        if (!ride.hasDriver) Text("Waiting for a driver to take your request.", style = MaterialTheme.typography.bodyMedium)
                        else PassengerWaitButtons(ride, me, waiting == ride.id, ::withNotifications)
                        OutlinedButton(
                            enabled = !busy,
                            onClick = {
                                confirm = "Cancel your request?" to {
                                    act("Request cancelled") {
                                        if (!ride.hasDriver) { Repo.deleteRide(ride.id); onBack() }
                                        else Repo.setRideStatus(ride.id, RideStatus.CANCELLED)
                                    }
                                }
                            },
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                        ) { Text("Cancel request") }
                        if (!ride.hasDriver) onBackAfterDeleteHint()
                    }

                    isPassenger -> {
                        PassengerWaitButtons(ride, me, waiting == ride.id, ::withNotifications)
                        Text("Can't make it? Please call the driver.", style = MaterialTheme.typography.bodySmall)
                    }

                    ride.requests[me.uid]?.status == SeatStatus.ASKED -> OutlinedButton(
                        enabled = !busy,
                        onClick = { act("Request withdrawn") { Repo.withdrawSeat(ride.id, me.uid) } },
                    ) { Text("Withdraw my request") }

                    ride.requests[me.uid]?.status == SeatStatus.DECLINED ->
                        Text("The driver declined your request.", style = MaterialTheme.typography.bodyMedium)

                    else -> Text("Use the ride board to ask for a seat or take this passenger.", style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }

    confirm?.let { (text, action) ->
        ConfirmDialog("Are you sure?", text, "Yes", onConfirm = action, onDismiss = { confirm = null })
    }
}

@Composable
private fun onBackAfterDeleteHint() {
    Text("An unanswered request is deleted when you cancel it.", style = MaterialTheme.typography.bodySmall)
}

@Composable
private fun RideHeader(ride: Ride) {
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (ride.type == RideType.OFFER) "Ride offer" else "Passenger request",
                    style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f),
                )
                StatusPill(ride.status)
            }
            LabeledValue("When", "${prettyDate(ride.date)} · ${ride.slot.label} · ${ride.departTime}")
            LabeledValue("Direction", ride.direction.label)
            LabeledValue("Stop", ride.stopName)
            if (ride.note.isNotBlank()) LabeledValue("Note", ride.note)
        }
    }
}

@Composable
private fun PersonRow(role: String, name: String, phone: String?) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(role, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(name, style = MaterialTheme.typography.bodyLarge)
        }
        if (!phone.isNullOrBlank()) CallButton(phone)
    }
}

@Composable
private fun LiveCard(ride: Ride, me: UserProfile, loc: DriverLoc?, now: Long, isDriver: Boolean, sharing: Boolean) {
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (isDriver) {
                Text(if (sharing) "📡 Sharing your location" else "Location sharing is off", fontWeight = FontWeight.SemiBold)
                Text(
                    if (sharing) "Only your ${ride.passengerCount} passenger(s) can see it. It stops when you tap Complete, or after 45 minutes."
                    else "Your passengers can't see where you are.",
                    style = MaterialTheme.typography.bodySmall,
                )
            } else {
                val stop = Repo.stopById(ride.pickupStopId(me.uid))
                when {
                    loc == null -> Text("Driver has started. Waiting for the first location…", fontWeight = FontWeight.SemiBold)
                    stop == null || (stop.lat == 0.0 && stop.lng == 0.0) ->
                        Text("Driver is on the way (your stop has no map point, so no ETA).", fontWeight = FontWeight.SemiBold)
                    else -> {
                        val m = Geo.distanceMeters(loc.lat, loc.lng, stop.lat, stop.lng)
                        Text("Driver ${Geo.etaText(m)} away", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        Text("to ${stop.name} · straight-line estimate", style = MaterialTheme.typography.bodySmall)
                    }
                }
                Geo.staleText(loc?.at, now)?.let { Text("⚠ $it", color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}

@Composable
private fun DriverActions(
    ride: Ride,
    busy: Boolean,
    sharing: Boolean,
    onStart: () -> Unit,
    onResume: () -> Unit,
    onComplete: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when (ride.status) {
            RideStatus.OPEN, RideStatus.FULL -> {
                Button(onClick = onStart, enabled = !busy && ride.passengerCount > 0, modifier = Modifier.fillMaxWidth()) {
                    Text("Start ride")
                }
                if (ride.passengerCount == 0) Text("Accept at least one passenger to start.", style = MaterialTheme.typography.bodySmall)
            }
            RideStatus.STARTED -> {
                val startedMs = ride.startedAt?.toDate()?.time
                val withinLimit = startedMs == null ||
                    System.currentTimeMillis() - startedMs < DriverLocationService.MAX_SHARE_MS
                if (!sharing && withinLimit) OutlinedButton(onClick = onResume, modifier = Modifier.fillMaxWidth()) {
                    Text("Resume location sharing")
                }
                Button(onClick = onComplete, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Complete ride") }
            }
            else -> Unit
        }
        TextButton(
            onClick = onCancel, enabled = !busy,
            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
        ) { Text("Cancel ride") }
    }
}

@Composable
private fun PassengerWaitButtons(
    ride: Ride,
    me: UserProfile,
    waiting: Boolean,
    withNotifications: (() -> Unit) -> Unit,
) {
    val ctx = LocalContext.current
    if (waiting) {
        Text("✅ You're waiting. We'll notify you once when the driver is ~2 min away — even with the screen off.",
            style = MaterialTheme.typography.bodyMedium)
        OutlinedButton(onClick = { PassengerWaitService.stop(ctx) }, modifier = Modifier.fillMaxWidth()) { Text("Picked up") }
    } else {
        Button(
            onClick = { withNotifications { PassengerWaitService.start(ctx, ride.id, me.uid) } },
            modifier = Modifier.fillMaxWidth(),
        ) { Text("I'm waiting") }
        Text("Tap when you're at the stop. It also starts by itself 10 min before the slot if the app is open.",
            style = MaterialTheme.typography.bodySmall)
    }
}
