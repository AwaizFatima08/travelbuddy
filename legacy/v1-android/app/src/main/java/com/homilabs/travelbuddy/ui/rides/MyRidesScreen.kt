package com.homilabs.travelbuddy.ui.rides

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.google.firebase.firestore.DocumentSnapshot
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.Ride
import com.homilabs.travelbuddy.model.RideType
import com.homilabs.travelbuddy.model.UserProfile
import com.homilabs.travelbuddy.service.AutoWait
import com.homilabs.travelbuddy.ui.EmptyNote
import com.homilabs.travelbuddy.ui.ErrorNote
import com.homilabs.travelbuddy.ui.Loading
import com.homilabs.travelbuddy.ui.StatusPill
import com.homilabs.travelbuddy.ui.prettyDate
import kotlinx.coroutines.launch

/** My rides from today on — one-time get, refreshed on open or with the refresh button. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyRidesScreen(me: UserProfile, openRide: (String) -> Unit) {
    val ctx = LocalContext.current
    var rides by remember { mutableStateOf<List<Ride>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }

    LaunchedEffect(reload) {
        error = null
        try {
            val list = Repo.myUpcoming(me.uid)
            rides = list.sortedWith(compareBy({ it.isFinished }, { it.date }, { it.slot.ordinal }, { it.departTime }))
            list.forEach { AutoWait.maybeStart(ctx, it, me.uid) }
        } catch (e: Exception) {
            error = Repo.friendly(e)
            if (rides == null) rides = emptyList()
        }
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = { Text("My rides") },
                actions = { IconButton(onClick = { reload++ }) { Icon(Icons.Default.Refresh, "Refresh") } },
            )
        },
    ) { pad ->
        val list = rides
        if (list == null) { Loading(Modifier.padding(pad)); return@Scaffold }
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                ErrorNote(error)
                Text(
                    "Rides you drive, or where your seat is confirmed. Seat requests still waiting for an answer show on the board.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (list.isEmpty()) item { EmptyNote("No upcoming rides.") }
            items(list, key = { it.id }) { RideRow(it, me, openRide) }
        }
    }
}

/** Own ride history (last 30 days are kept), newest first, 20 per page. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(me: UserProfile, openRide: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val rides = remember { mutableStateListOf<Ride>() }
    var cursor by remember { mutableStateOf<DocumentSnapshot?>(null) }
    var more by remember { mutableStateOf(true) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun loadPage() {
        if (loading || !more) return
        loading = true
        scope.launch {
            try {
                val (page, last) = Repo.history(me.uid, cursor)
                rides.addAll(page.filter { r -> rides.none { it.id == r.id } })
                cursor = last
                more = page.size == 20
            } catch (e: Exception) {
                error = Repo.friendly(e)
            } finally {
                loading = false
            }
        }
    }
    LaunchedEffect(Unit) { loadPage() }

    Scaffold(contentWindowInsets = WindowInsets(0), topBar = { TopAppBar(title = { Text("History") }) }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                ErrorNote(error)
                Text("Your rides from the last 30 days. Older rides are deleted automatically.", style = MaterialTheme.typography.bodySmall)
            }
            if (rides.isEmpty() && !loading) item { EmptyNote("No rides yet.") }
            items(rides, key = { it.id }) { RideRow(it, me, openRide) }
            item {
                if (loading) Loading(Modifier.padding(16.dp))
                else if (more && rides.isNotEmpty()) OutlinedButton(onClick = { loadPage() }, modifier = Modifier.fillMaxWidth()) { Text("Load more") }
            }
        }
    }
}

@Composable
private fun RideRow(ride: Ride, me: UserProfile, openRide: (String) -> Unit) {
    val role = when {
        ride.isDriver(me.uid) -> "You drive"
        else -> "You ride with ${ride.driverName.ifBlank { "—" }}"
    }
    Card(Modifier.fillMaxWidth().clickable { openRide(ride.id) }) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("${prettyDate(ride.date)} · ${ride.slot.label} · ${ride.departTime}",
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                StatusPill(ride.status)
            }
            Text("${ride.direction.label} · ${ride.stopName}", style = MaterialTheme.typography.bodyMedium)
            Text(
                if (ride.type == RideType.OFFER && ride.isDriver(me.uid)) "$role · ${ride.acceptedCount} passenger(s)" else role,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
