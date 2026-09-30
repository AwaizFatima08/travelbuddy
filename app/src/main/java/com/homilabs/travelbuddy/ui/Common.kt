package com.homilabs.travelbuddy.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Call
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.RideStatus
import com.homilabs.travelbuddy.model.SeatStatus
import com.homilabs.travelbuddy.model.Stop
import com.homilabs.travelbuddy.util.Geo
import com.homilabs.travelbuddy.util.Locator
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter

fun Context.toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_LONG).show()

/** Opens the dialer with the number filled in (no CALL_PHONE permission needed). */
fun Context.dial(phone: String) {
    if (phone.isBlank()) return
    runCatching { startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${phone.trim()}"))) }
}

fun prettyDate(iso: String): String = runCatching {
    LocalDate.parse(iso).format(DateTimeFormatter.ofPattern("EEE d MMM"))
}.getOrDefault(iso)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackTopBar(title: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}) {
    TopAppBar(
        title = { Text(title) },
        navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        },
        actions = { actions() },
    )
}

@Composable
fun Loading(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

@Composable
fun EmptyNote(text: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun ErrorNote(text: String?) {
    if (text.isNullOrBlank()) return
    Text(text, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
}

@Composable
fun Pill(text: String, color: Color, onColor: Color = Color.White) {
    Surface(color = color, shape = MaterialTheme.shapes.small) {
        Text(
            text, color = onColor, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
        )
    }
}

@Composable
fun StatusPill(status: RideStatus) {
    val (c, t) = when (status) {
        RideStatus.OPEN -> MaterialTheme.colorScheme.primary to "OPEN"
        RideStatus.FULL -> Color(0xFF5B6CC2) to "FULL"
        RideStatus.STARTED -> Color(0xFFC77700) to "ON THE WAY"
        RideStatus.COMPLETED -> Color(0xFF546E7A) to "COMPLETED"
        RideStatus.CANCELLED -> MaterialTheme.colorScheme.error to "CANCELLED"
    }
    Pill(t, c)
}

@Composable
fun SeatPill(status: SeatStatus) {
    val (c, t) = when (status) {
        SeatStatus.ASKED -> Color(0xFFC77700) to "ASKED"
        SeatStatus.ACCEPTED -> MaterialTheme.colorScheme.primary to "ACCEPTED"
        SeatStatus.DECLINED -> MaterialTheme.colorScheme.error to "DECLINED"
    }
    Pill(t, c)
}

@Composable
fun CallButton(phone: String, label: String = "Call") {
    val ctx = LocalContext.current
    FilledTonalButton(onClick = { ctx.dial(phone) }, enabled = phone.isNotBlank()) {
        Icon(Icons.Default.Call, null, Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text(label)
    }
}

@Composable
fun LabeledValue(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(110.dp))
        Text(value.ifBlank { "—" }, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun ConfirmDialog(
    title: String,
    text: String,
    confirm: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = { TextButton(onClick = { onDismiss(); onConfirm() }) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Back") } },
    )
}

/** A dialog asking for a short reason (block / unblock). */
@Composable
fun ReasonDialog(title: String, confirm: String, required: Boolean, onConfirm: (String) -> Unit, onDismiss: () -> Unit) {
    var reason by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = reason, onValueChange = { reason = it.take(200) },
                label = { Text(if (required) "Reason (required)" else "Reason (optional)") },
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(enabled = !required || reason.isNotBlank(), onClick = { onDismiss(); onConfirm(reason) }) { Text(confirm) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Back") } },
    )
}

/** Active pickup stops, nearest first (uses one location fix per app session). */
@Composable
fun rememberSortedStops(): List<Stop> {
    val ctx = LocalContext.current
    val stops by Repo.stops.collectAsState()
    var here by remember { mutableStateOf(LocationCache.last) }
    LaunchedEffect(Unit) {
        runCatching { Repo.loadStops() }
        if (here == null) {
            Locator.current(ctx)?.let { LocationCache.last = it.latitude to it.longitude; here = LocationCache.last }
        }
    }
    val active = stops.filter { it.active }
    val h = here ?: return active
    return active.sortedBy { if (it.lat == 0.0 && it.lng == 0.0) Double.MAX_VALUE else Geo.distanceMeters(h.first, h.second, it.lat, it.lng) }
}

object LocationCache {
    var last: Pair<Double, Double>? = null
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
        modifier = modifier.padding(top = 12.dp, bottom = 4.dp))
}

@Composable
fun Centered(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) { content() }
}

/** "Delete my account" — asks for the password again, then deletes profile + sign-in. */
@Composable
fun DeleteAccountDialog(onDismiss: () -> Unit, onDeleted: () -> Unit = {}) {
    val ctx = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("Delete my account?") },
        text = {
            Column {
                Text(
                    "This permanently deletes your TravelBuddy profile and sign-in. Your open rides are cancelled. " +
                        "Past rides are removed automatically within 30 days. This can't be undone."
                )
                OutlinedTextField(
                    value = password, onValueChange = { password = it }, singleLine = true,
                    label = { Text("Your password") },
                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                )
                ErrorNote(error)
            }
        },
        confirmButton = {
            TextButton(
                enabled = password.isNotEmpty() && !busy,
                colors = androidx.compose.material3.ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                onClick = {
                    busy = true; error = null
                    scope.launch {
                        try {
                            com.homilabs.travelbuddy.service.DriverLocationService.stop(ctx)
                            com.homilabs.travelbuddy.service.PassengerWaitService.stop(ctx)
                            Repo.deleteAccount(password)
                            ctx.toast("Your account was deleted.")
                            onDeleted()
                        } catch (e: Exception) {
                            error = Repo.friendly(e)
                        } finally {
                            busy = false
                        }
                    }
                },
            ) { Text(if (busy) "Deleting…" else "Delete forever") }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Keep my account") } },
    )
}
