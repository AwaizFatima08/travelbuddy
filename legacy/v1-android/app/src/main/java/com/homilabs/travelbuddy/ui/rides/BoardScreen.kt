package com.homilabs.travelbuddy.ui.rides

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.Direction
import com.homilabs.travelbuddy.model.Ride
import com.homilabs.travelbuddy.model.RideType
import com.homilabs.travelbuddy.model.SeatStatus
import com.homilabs.travelbuddy.model.SlotClock
import com.homilabs.travelbuddy.model.SlotInstance
import com.homilabs.travelbuddy.model.Stop
import com.homilabs.travelbuddy.model.UserProfile
import com.homilabs.travelbuddy.ui.CallButton
import com.homilabs.travelbuddy.ui.ConfirmDialog
import com.homilabs.travelbuddy.ui.EmptyNote
import com.homilabs.travelbuddy.ui.ErrorNote
import com.homilabs.travelbuddy.ui.Loading
import com.homilabs.travelbuddy.ui.SeatPill
import com.homilabs.travelbuddy.ui.rememberSortedStops
import com.homilabs.travelbuddy.ui.toast
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BoardScreen(me: UserProfile, openRide: (String) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var slots by remember { mutableStateOf(SlotClock.upcoming(4)) }
    var selIdx by rememberSaveable { mutableIntStateOf(0) }

    // When a slot ends, move the board on to the next one.
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            val fresh = SlotClock.upcoming(4)
            if (fresh.first() != slots.first()) { slots = fresh; selIdx = 0 }
        }
    }
    val si = slots[selIdx.coerceIn(slots.indices)]
    var dir by rememberSaveable(si.dateKey, si.slot) { mutableStateOf(si.slot.defaultDirection) }

    // ONE listener: date + slot + direction + OPEN. Removed when this screen stops.
    val board by remember(si, dir) { Repo.boardFlow(si, dir) }.collectAsStateWithLifecycle(initialValue = null)

    var posting by remember { mutableStateOf(false) }
    var asking by remember { mutableStateOf<Ride?>(null) }
    var taking by remember { mutableStateOf<Ride?>(null) }

    fun run(done: String, block: suspend () -> Unit) {
        scope.launch {
            try { block(); ctx.toast(done) } catch (e: Exception) { ctx.toast(Repo.friendly(e)) }
        }
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(title = {
                Column {
                    Text("Ride board")
                    Text(si.label(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                }
            })
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { posting = true },
                icon = { Icon(Icons.Default.Add, null) },
                text = { Text("Post") },
            )
        },
    ) { pad ->
        LazyColumn(
            Modifier.padding(pad),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    slots.forEachIndexed { i, s ->
                        FilterChip(
                            selected = i == selIdx,
                            onClick = { selIdx = i },
                            label = { Text(chipLabel(s, i == 0)) },
                        )
                    }
                }
            }
            item { DirectionPicker(dir) { dir = it } }
            val res = board
            when {
                res == null -> item { Loading(Modifier.height(200.dp)) }
                res.isFailure -> item { ErrorNote(res.exceptionOrNull()?.message) }
                res.getOrNull().isNullOrEmpty() -> item {
                    EmptyNote("No open rides for this slot yet.\nDriving? Offer seats. Need a ride? Post a request.")
                }
                else -> items(res.getOrThrow(), key = { it.id }) { ride ->
                    RideCard(
                        ride = ride, me = me,
                        onOpen = { openRide(ride.id) },
                        onAsk = { asking = ride },
                        onWithdraw = { run("Request withdrawn") { Repo.withdrawSeat(ride.id, me.uid) } },
                        onTake = { taking = ride },
                    )
                }
            }
        }
    }

    if (posting) PostRideDialog(me, slots, si, dir, onDismiss = { posting = false }, onPosted = { posting = false })
    asking?.let { ride ->
        AskSeatDialog(ride, onDismiss = { asking = null }) { stop ->
            asking = null
            run("Seat requested. The driver will accept or decline.") { Repo.askSeat(ride.id, me, stop?.id ?: ride.stopId) }
        }
    }
    taking?.let { ride ->
        ConfirmDialog(
            title = "Take ${ride.posterName}?",
            text = "You'll drive ${ride.posterName} at ${ride.departTime} from ${ride.stopName}. Your phone number will be shared with them.",
            confirm = "Take passenger",
            onConfirm = { run("You're driving ${ride.posterName}") { Repo.takeRequest(ride.id, me); openRide(ride.id) } },
            onDismiss = { taking = null },
        )
    }
}

private fun chipLabel(s: SlotInstance, first: Boolean): String {
    val running = !SlotClock.now().isBefore(s.startAt)
    val name = "${dayWord(s)} ${s.slot.label}".trim()
    return when {
        first && running -> "Now: ${s.slot.label}"
        first -> "Next: $name"
        else -> name
    }
}

private fun dayWord(s: SlotInstance): String = when (s.date) {
    SlotClock.today() -> ""
    SlotClock.today().plusDays(1) -> "Tmrw"
    else -> s.date.dayOfWeek.name.take(3).lowercase().replaceFirstChar { it.uppercase() }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DirectionPicker(dir: Direction, onChange: (Direction) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        Direction.entries.forEachIndexed { i, d ->
            SegmentedButton(
                selected = dir == d,
                onClick = { onChange(d) },
                shape = SegmentedButtonDefaults.itemShape(i, Direction.entries.size),
            ) { Text(d.short, maxLines = 1) }
        }
    }
}

@Composable
private fun RideCard(
    ride: Ride,
    me: UserProfile,
    onOpen: () -> Unit,
    onAsk: () -> Unit,
    onWithdraw: () -> Unit,
    onTake: () -> Unit,
) {
    val mine = ride.isPoster(me.uid) || ride.isDriver(me.uid)
    val myReq = ride.requests[me.uid]
    val offer = ride.type == RideType.OFFER
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(
            containerColor = if (offer) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f)
            else MaterialTheme.colorScheme.tertiaryContainer
        ),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (offer) "🚗  ${ride.driverName}" else "🙋  ${ride.posterName}",
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                Text(ride.departTime, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            Text(
                if (offer) "Offering ${ride.seatsLeft} of ${ride.totalSeats} seat(s) · from ${ride.stopName}"
                else "Needs a seat · pickup at ${ride.stopName}",
                style = MaterialTheme.typography.bodyMedium,
            )
            if (ride.note.isNotBlank()) Text("“${ride.note}”", style = MaterialTheme.typography.bodySmall)
            if (myReq != null) Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Your request: ", style = MaterialTheme.typography.bodySmall); SeatPill(myReq.status)
            }
            Spacer(Modifier.height(4.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                when {
                    mine -> Button(onClick = onOpen) { Text("Manage") }
                    offer && myReq == null -> Button(onClick = onAsk, enabled = ride.seatsLeft > 0) { Text("Ask for seat") }
                    offer && myReq?.status == SeatStatus.ASKED -> OutlinedButton(onClick = onWithdraw) { Text("Withdraw") }
                    offer && myReq?.status == SeatStatus.ACCEPTED -> Button(onClick = onOpen) { Text("Open") }
                    !offer -> Button(onClick = onTake) { Text("Take this passenger") }
                }
                if (!mine) CallButton(if (offer) ride.driverPhone else ride.posterPhone)
            }
        }
    }
}

@Composable
private fun AskSeatDialog(ride: Ride, onDismiss: () -> Unit, onConfirm: (Stop?) -> Unit) {
    val stops = rememberSortedStops()
    var chosen by remember(stops) { mutableStateOf(stops.firstOrNull()) } // nearest first
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Ask ${ride.driverName} for a seat") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text("Where should the driver pick you up? (nearest first)", style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(8.dp))
                if (stops.isEmpty()) Text("No pickup stops yet — you'll be picked up at ${ride.stopName}.")
                stops.forEach { s ->
                    Row(
                        Modifier.fillMaxWidth().selectable(selected = chosen?.id == s.id, onClick = { chosen = s }),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = chosen?.id == s.id, onClick = { chosen = s })
                        Text(s.name)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(chosen) }) { Text("Ask for seat") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Back") } },
    )
}

@Composable
fun StopPicker(stops: List<Stop>, selected: Stop?, onSelect: (Stop) -> Unit, label: String = "Pickup stop") {
    var open by remember { mutableStateOf(false) }
    Box {
        OutlinedTextField(
            value = selected?.name ?: "", onValueChange = {}, readOnly = true,
            label = { Text(label) }, trailingIcon = { Icon(Icons.Default.ArrowDropDown, null) },
            modifier = Modifier.fillMaxWidth(),
        )
        // Transparent overlay so a tap anywhere opens the menu.
        Box(Modifier.matchParentSize().clickable { open = true })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            stops.forEach { s ->
                DropdownMenuItem(text = { Text(s.name) }, onClick = { onSelect(s); open = false })
            }
        }
    }
}

@Composable
private fun PostRideDialog(
    me: UserProfile,
    slots: List<SlotInstance>,
    initialSlot: SlotInstance,
    initialDir: Direction,
    onDismiss: () -> Unit,
    onPosted: () -> Unit,
) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val stops = rememberSortedStops()
    var type by remember { mutableStateOf(RideType.OFFER) }
    var si by remember { mutableStateOf(initialSlot) }
    var dir by remember { mutableStateOf(initialDir) }
    // Leaving time: 5-minute steps from 30 min before the slot to its end (no typing, no ":" needed).
    var time by remember(si) { mutableStateOf(si.slot.start) }
    var stop by remember(stops) { mutableStateOf(stops.firstOrNull()) }
    var seats by remember { mutableIntStateOf(3) }
    var note by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var slotMenu by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("Post a ride") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(type == RideType.OFFER, { type = RideType.OFFER }, { Text("I'm driving") })
                    FilterChip(type == RideType.REQUEST, { type = RideType.REQUEST }, { Text("I need a seat") })
                }
                Box {
                    OutlinedButton(onClick = { slotMenu = true }, modifier = Modifier.fillMaxWidth()) { Text(si.label()) }
                    DropdownMenu(expanded = slotMenu, onDismissRequest = { slotMenu = false }) {
                        slots.forEach { s ->
                            DropdownMenuItem(text = { Text(s.label()) }, onClick = {
                                si = s; dir = s.slot.defaultDirection; slotMenu = false
                            })
                        }
                    }
                }
                DirectionPicker(dir) { dir = it }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Leaving at")
                        Text("slot ${si.slot.window}", style = MaterialTheme.typography.bodySmall)
                    }
                    IconButton(
                        enabled = time.isAfter(si.slot.start.minusMinutes(30)),
                        onClick = { time = time.minusMinutes(5) },
                    ) { Icon(Icons.Default.Remove, "5 minutes earlier") }
                    Text(SlotClock.formatTime(time), style = MaterialTheme.typography.titleMedium)
                    IconButton(
                        enabled = time.isBefore(si.slot.end),
                        onClick = { time = time.plusMinutes(5) },
                    ) { Icon(Icons.Default.Add, "5 minutes later") }
                }
                if (stops.isEmpty()) Text("The admin hasn't added pickup stops yet.", color = MaterialTheme.colorScheme.error)
                else StopPicker(stops, stop, { stop = it }, if (type == RideType.OFFER) "Starting stop (nearest first)" else "Pick me up at (nearest first)")
                if (type == RideType.OFFER) Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Seats offered", Modifier.weight(1f))
                    IconButton(onClick = { if (seats > 1) seats-- }) { Icon(Icons.Default.Remove, "Fewer") }
                    Text("$seats", style = MaterialTheme.typography.titleMedium, modifier = Modifier.width(24.dp))
                    IconButton(onClick = { if (seats < 6) seats++ }) { Icon(Icons.Default.Add, "More") }
                }
                OutlinedTextField(
                    value = note, onValueChange = { note = it.take(140) },
                    label = { Text("Note (optional)") }, modifier = Modifier.fillMaxWidth(),
                )
                ErrorNote(error)
            }
        },
        confirmButton = {
            TextButton(
                enabled = !busy && stop != null,
                onClick = {
                    val t = SlotClock.formatTime(time)
                    busy = true; error = null
                    scope.launch {
                        try {
                            Repo.postRide(me, type, si, dir, t, stop!!, seats, note)
                            ctx.toast(if (type == RideType.OFFER) "Ride posted" else "Request posted")
                            onPosted()
                        } catch (e: Exception) {
                            error = Repo.friendly(e)
                        } finally {
                            busy = false
                        }
                    }
                },
            ) { Text("Post") }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Cancel") } },
    )
}
