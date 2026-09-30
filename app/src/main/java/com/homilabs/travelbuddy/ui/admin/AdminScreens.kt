package com.homilabs.travelbuddy.ui.admin

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.homilabs.travelbuddy.data.Report
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.AccountStatus
import com.homilabs.travelbuddy.model.Stop
import com.homilabs.travelbuddy.model.UserProfile
import com.homilabs.travelbuddy.ui.BackTopBar
import com.homilabs.travelbuddy.ui.CallButton
import com.homilabs.travelbuddy.ui.EmptyNote
import com.homilabs.travelbuddy.ui.ErrorNote
import com.homilabs.travelbuddy.ui.LabeledValue
import com.homilabs.travelbuddy.ui.Loading
import com.homilabs.travelbuddy.ui.Pill
import com.homilabs.travelbuddy.ui.ReasonDialog
import com.homilabs.travelbuddy.ui.Route
import com.homilabs.travelbuddy.ui.ScreenColumn
import com.homilabs.travelbuddy.ui.SectionTitle
import com.homilabs.travelbuddy.ui.prettyDate
import com.homilabs.travelbuddy.ui.toast
import com.homilabs.travelbuddy.util.Locator
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID

private val stamp = SimpleDateFormat("d MMM yyyy, HH:mm", Locale.US)

/** Admin tab: live pending list (the only admin listener) + buttons for the rest. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdminHome(me: UserProfile, push: (Route) -> Unit) {
    val pending by remember { Repo.pendingFlow() }.collectAsStateWithLifecycle(initialValue = null)
    Scaffold(contentWindowInsets = WindowInsets(0), topBar = { TopAppBar(title = { Text("Admin") }) }) { pad ->
        ScreenColumn(Modifier.padding(pad)) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(onClick = { push(Route.AdminAudit) }) { Text("Members & audit") }
                FilledTonalButton(onClick = { push(Route.AdminStops) }) { Text("Pickup stops") }
                FilledTonalButton(onClick = { push(Route.AdminReports) }) { Text("Reports") }
            }
            SectionTitle("Waiting for approval")
            val res = pending
            when {
                res == null -> Loading(Modifier.height(120.dp))
                res.isFailure -> ErrorNote(res.exceptionOrNull()?.message)
                res.getOrThrow().isEmpty() -> EmptyNote("No one is waiting. 🎉")
                else -> res.getOrThrow().forEach { MemberCard(it, me) }
            }
        }
    }
}

/** A member with Approve / Block / Unblock buttons. */
@Composable
fun MemberCard(user: UserProfile, me: UserProfile, onChanged: () -> Unit = {}) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var dialog by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var showAudit by remember { mutableStateOf(false) }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(user.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                val c = when (user.status) {
                    AccountStatus.ACTIVE -> MaterialTheme.colorScheme.primary
                    AccountStatus.PENDING -> MaterialTheme.colorScheme.tertiary
                    AccountStatus.BLOCKED -> MaterialTheme.colorScheme.error
                }
                Pill(if (user.role == "ADMIN") "${user.status} · ADMIN" else user.status.name, c)
            }
            LabeledValue("Email", user.email)
            LabeledValue("Employee ID", user.employeeId)
            LabeledValue("Department", user.department)
            LabeledValue("Phone", user.phone)
            LabeledValue("Township", user.townshipLocation)
            if (user.audit.isNotEmpty()) {
                TextButton(onClick = { showAudit = !showAudit }) {
                    Text(if (showAudit) "Hide audit trail" else "Audit trail (${user.audit.size})")
                }
                if (showAudit) user.audit.reversed().forEach { a ->
                    Text(
                        "• ${a.action} by ${a.byName} · ${a.at?.toDate()?.let(stamp::format) ?: ""}" +
                            if (a.reason.isNotBlank()) "\n   “${a.reason}”" else "",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            Spacer(Modifier.height(6.dp))
            if (user.uid != me.uid) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when (user.status) {
                    AccountStatus.PENDING -> {
                        Button(enabled = !busy, onClick = { dialog = "APPROVED" }) { Text("Approve") }
                        OutlinedButton(enabled = !busy, onClick = { dialog = "BLOCKED" },
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Block") }
                    }
                    AccountStatus.ACTIVE -> OutlinedButton(enabled = !busy, onClick = { dialog = "BLOCKED" },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Block") }
                    AccountStatus.BLOCKED -> Button(enabled = !busy, onClick = { dialog = "UNBLOCKED" }) { Text("Unblock") }
                }
                CallButton(user.phone)
            }
        }
    }

    dialog?.let { action ->
        val title = when (action) {
            "APPROVED" -> "Approve ${user.name}?"
            "BLOCKED" -> "Block ${user.name}?"
            else -> "Unblock ${user.name}?"
        }
        ReasonDialog(
            title = title,
            confirm = when (action) { "APPROVED" -> "Approve"; "BLOCKED" -> "Block"; else -> "Unblock" },
            required = action != "APPROVED",
            onConfirm = { reason ->
                busy = true
                scope.launch {
                    try {
                        Repo.adminAction(user.uid, action, reason, me)
                        ctx.toast("${user.name}: ${action.lowercase()}")
                        onChanged()
                    } catch (e: Exception) {
                        ctx.toast(Repo.friendly(e))
                    } finally {
                        busy = false
                    }
                }
            },
            onDismiss = { dialog = null },
        )
    }
}

/** Audit trail (one-time get, last 30 admin actions) + find a member by email. */
@Composable
fun AuditScreen(me: UserProfile, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var list by remember { mutableStateOf<List<UserProfile>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var email by remember { mutableStateOf("") }
    var found by remember { mutableStateOf<List<UserProfile>?>(null) }

    fun load() = scope.launch {
        error = null
        try { list = Repo.recentAdminActions() } catch (e: Exception) { error = Repo.friendly(e) }
    }
    LaunchedEffect(Unit) { load() }

    Scaffold(topBar = { BackTopBar("Members & audit", onBack) }) { pad ->
        ScreenColumn(Modifier.padding(pad)) {
            SectionTitle("Find a member")
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = email, onValueChange = { email = it.trim() }, label = { Text("Email") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.weight(1f),
                )
                Button(enabled = email.contains('@'), onClick = {
                    scope.launch {
                        try { found = Repo.findUserByEmail(email) } catch (e: Exception) { error = Repo.friendly(e) }
                    }
                }) { Text("Find") }
            }
            found?.let { f ->
                if (f.isEmpty()) Text("No member with that email.")
                f.forEach { MemberCard(it, me, onChanged = { scope.launch { found = Repo.findUserByEmail(email) } }) }
            }
            ErrorNote(error)
            SectionTitle("Recent admin actions (last 30)")
            when (val l = list) {
                null -> Loading(Modifier.height(120.dp))
                else -> if (l.isEmpty()) EmptyNote("No admin actions yet.") else l.forEach { MemberCard(it, me, onChanged = { load() }) }
            }
        }
    }
}

/** Pickup stops editor: add / rename / reorder / disable; GPS capture or typed coordinates. */
@Composable
fun StopsEditorScreen(onBack: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val stops = remember { mutableStateListOf<Stop>() }
    var loaded by remember { mutableStateOf(false) }
    var dirty by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Stop?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        try { stops.addAll(Repo.loadStops(force = true)) } catch (e: Exception) { error = Repo.friendly(e) }
        loaded = true
    }

    Scaffold(topBar = {
        BackTopBar("Pickup stops", onBack) {
            TextButton(enabled = dirty && !saving, onClick = {
                saving = true
                scope.launch {
                    try { Repo.saveStops(stops.toList()); dirty = false; ctx.toast("Stops saved") }
                    catch (e: Exception) { ctx.toast(Repo.friendly(e)) } finally { saving = false }
                }
            }) { Text("SAVE") }
        }
    }) { pad ->
        if (!loaded) { Loading(Modifier.padding(pad)); return@Scaffold }
        ScreenColumn(Modifier.padding(pad)) {
            ErrorNote(error)
            Text("Tip: stand at the stop and tap “Use my GPS” to capture its exact point. Disabled stops are hidden from members. Tap SAVE when done.",
                style = MaterialTheme.typography.bodySmall)
            Button(onClick = { editing = Stop(UUID.randomUUID().toString().take(8), "", 0.0, 0.0, true, stops.size) }) { Text("Add stop") }
            if (stops.isEmpty()) EmptyNote("No stops yet.")
            stops.forEachIndexed { i, s ->
                Card(
                    Modifier.fillMaxWidth(),
                    colors = if (s.active) CardDefaults.cardColors() else CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    Row(Modifier.padding(start = 12.dp, end = 4.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(s.name, fontWeight = FontWeight.SemiBold)
                            Text(
                                if (s.lat == 0.0 && s.lng == 0.0) "⚠ no map point" else String.format(Locale.US, "%.5f, %.5f", s.lat, s.lng),
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        Switch(checked = s.active, onCheckedChange = { stops[i] = s.copy(active = it); dirty = true })
                        IconButton(onClick = { editing = s }) { Icon(Icons.Default.Edit, "Edit") }
                        Column {
                            IconButton(enabled = i > 0, onClick = { stops.add(i - 1, stops.removeAt(i)); dirty = true }) {
                                Icon(Icons.Default.ArrowUpward, "Move up")
                            }
                            IconButton(enabled = i < stops.lastIndex, onClick = { stops.add(i + 1, stops.removeAt(i)); dirty = true }) {
                                Icon(Icons.Default.ArrowDownward, "Move down")
                            }
                        }
                    }
                }
            }
        }
    }

    editing?.let { s ->
        StopDialog(s, onDismiss = { editing = null }) { updated ->
            val idx = stops.indexOfFirst { it.id == updated.id }
            if (idx >= 0) stops[idx] = updated else stops.add(updated)
            dirty = true
            editing = null
        }
    }
}

@Composable
private fun StopDialog(stop: Stop, onDismiss: () -> Unit, onDone: (Stop) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(stop.name) }
    var lat by remember { mutableStateOf(if (stop.lat == 0.0) "" else stop.lat.toString()) }
    var lng by remember { mutableStateOf(if (stop.lng == 0.0) "" else stop.lng.toString()) }
    var locating by remember { mutableStateOf(false) }
    val latD = lat.toDoubleOrNull()
    val lngD = lng.toDoubleOrNull()
    val coordsOk = (lat.isBlank() && lng.isBlank()) ||
        (latD != null && lngD != null && latD in -90.0..90.0 && lngD in -180.0..180.0)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (stop.name.isEmpty()) "Add stop" else "Edit stop") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it.take(50) }, label = { Text("Stop name") }, singleLine = true)
                OutlinedTextField(lat, { lat = it.trim() }, label = { Text("Latitude") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
                OutlinedTextField(lng, { lng = it.trim() }, label = { Text("Longitude") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
                OutlinedButton(enabled = !locating, onClick = {
                    if (!Locator.hasPermission(ctx)) { ctx.toast("Allow location for TravelBuddy in phone settings first."); return@OutlinedButton }
                    locating = true
                    scope.launch {
                        val l = Locator.current(ctx, highAccuracy = true)
                        locating = false
                        if (l == null) ctx.toast("Couldn't get a GPS fix. Go outside and try again.")
                        else {
                            lat = String.format(Locale.US, "%.6f", l.latitude)
                            lng = String.format(Locale.US, "%.6f", l.longitude)
                            ctx.toast("Captured (±${l.accuracy.toInt()} m)")
                        }
                    }
                }) {
                    Icon(Icons.Default.MyLocation, null); Spacer(Modifier.padding(4.dp))
                    Text(if (locating) "Getting GPS…" else "Use my GPS")
                }
                if (!coordsOk) Text("Latitude/longitude don't look right.", color = MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = {
            TextButton(enabled = name.isNotBlank() && coordsOk, onClick = {
                onDone(stop.copy(name = name.trim(), lat = latD ?: 0.0, lng = lngD ?: 0.0))
            }) { Text("OK") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** Reports for the last 30 days — loaded only when the button is pressed. */
@Composable
fun ReportsScreen(onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var report by remember { mutableStateOf<Report?>(null) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Scaffold(topBar = { BackTopBar("Reports", onBack) }) { pad ->
        ScreenColumn(Modifier.padding(pad)) {
            Text("Rolling last 30 days. Loaded only when you tap the button.", style = MaterialTheme.typography.bodySmall)
            Button(enabled = !loading, onClick = {
                loading = true; error = null
                scope.launch {
                    try { report = Repo.loadReport() } catch (e: Exception) { error = Repo.friendly(e) } finally { loading = false }
                }
            }) { Text(if (report == null) "Load report" else "Reload") }
            if (loading) Loading(Modifier.height(120.dp))
            ErrorNote(error)
            report?.let { r ->
                SectionTitle("Since ${prettyDate(r.fromDate)}")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        LabeledValue("Rides posted", r.ridesPosted.toString())
                        LabeledValue("Completed", r.completed.toString())
                        LabeledValue("Cancelled", r.cancelled.toString())
                        LabeledValue("Seats shared", r.seatsShared.toString())
                    }
                }
                SectionTitle("Completed rides by slot")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        r.completedBySlot.forEach { (s, n) -> LabeledValue(s.label, n.toString()) }
                    }
                }
                SectionTitle("Top volunteer drivers")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        if (r.topVolunteers.isEmpty()) Text("No completed rides yet.")
                        r.topVolunteers.forEachIndexed { i, (name, n) -> LabeledValue("${i + 1}. $name", "$n ride(s)") }
                    }
                }
                SectionTitle("Members")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        LabeledValue("Active", r.activeMembers.toString())
                        LabeledValue("Pending", r.pendingMembers.toString())
                        LabeledValue("Blocked", r.blockedMembers.toString())
                    }
                }
            }
        }
    }
}
