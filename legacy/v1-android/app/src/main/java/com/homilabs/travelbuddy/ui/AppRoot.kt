package com.homilabs.travelbuddy.ui

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AdminPanelSettings
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.EventNote
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.homilabs.travelbuddy.MainActivity
import com.homilabs.travelbuddy.R
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.data.UserState
import com.homilabs.travelbuddy.model.AccountStatus
import com.homilabs.travelbuddy.model.UserProfile
import com.homilabs.travelbuddy.service.AutoWait
import com.homilabs.travelbuddy.ui.admin.AdminHome
import com.homilabs.travelbuddy.ui.admin.AuditScreen
import com.homilabs.travelbuddy.ui.admin.ReportsScreen
import com.homilabs.travelbuddy.ui.admin.StopsEditorScreen
import com.homilabs.travelbuddy.ui.auth.AuthFlow
import com.homilabs.travelbuddy.ui.auth.BlockedScreen
import com.homilabs.travelbuddy.ui.auth.MissingProfileScreen
import com.homilabs.travelbuddy.ui.auth.PendingScreen
import com.homilabs.travelbuddy.ui.rides.BoardScreen
import com.homilabs.travelbuddy.ui.rides.HistoryScreen
import com.homilabs.travelbuddy.ui.rides.MyRidesScreen
import com.homilabs.travelbuddy.ui.rides.RideScreen

@Composable
fun AppRoot(activity: MainActivity) {
    val user by remember { Repo.authFlow() }.collectAsState(Repo.currentUser)
    val locked by activity.locked

    val u = user
    if (u == null) {
        AuthFlow(activity.loginNotice.value)
        return
    }
    LaunchedEffect(u.uid) { activity.loginNotice.value = null }
    if (locked) {
        LockScreen(activity)
        return
    }
    val state by remember(u.uid) { Repo.userFlow(u.uid) }.collectAsStateWithLifecycle(UserState.Loading)
    val registering by Repo.registering.collectAsState()
    when (val s = state) {
        UserState.Loading -> Loading()
        UserState.Missing -> if (registering) Loading() else MissingProfileScreen()
        is UserState.Error -> Centered {
            Text(s.message, textAlign = TextAlign.Center)
            Spacer(Modifier.height(12.dp))
            OutlinedButton(onClick = { Repo.logout() }) { Text("Log out") }
        }
        is UserState.Loaded -> when (s.profile.status) {
            AccountStatus.PENDING -> PendingScreen(s.profile)
            AccountStatus.BLOCKED -> BlockedScreen(s.profile)
            AccountStatus.ACTIVE -> {
                var firstRunDone by remember { mutableStateOf(activity.prefs.firstRunDone) }
                if (!firstRunDone) FirstRunScreen { activity.prefs.firstRunDone = true; firstRunDone = true }
                else MainShell(activity, s.profile)
            }
        }
    }
}

@Composable
private fun LockScreen(activity: MainActivity) {
    LaunchedEffect(Unit) { activity.unlock() }
    Centered {
        Image(painterResource(R.drawable.logo_mark), null, Modifier.size(96.dp))
        Spacer(Modifier.height(16.dp))
        Text("TravelBuddy is locked", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(16.dp))
        Button(onClick = { activity.unlock() }) { Text("Unlock with fingerprint / face") }
        TextButton(onClick = { activity.fallbackToPassword("Log in with your password.") }) { Text("Use password instead") }
    }
}

/** First run: permissions + battery-optimisation link (for Xiaomi/Oppo/Vivo/Samsung). */
@Composable
fun FirstRunScreen(onDone: () -> Unit) {
    val ctx = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }
    Column(
        Modifier.fillMaxSize().systemBarsPadding().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("Welcome to TravelBuddy", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("Three quick things so ride alerts work reliably:")
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("1. Notifications and location", fontWeight = FontWeight.SemiBold)
                Text("Notifications tell you when your driver is ~2 minutes away. Location sorts pickup stops nearest-first and, for drivers, shares your position with your passengers only during a started ride.")
                Button(onClick = {
                    val perms = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
                    if (Build.VERSION.SDK_INT >= 33) perms += Manifest.permission.POST_NOTIFICATIONS
                    launcher.launch(perms.toTypedArray())
                }) { Text("Allow") }
            }
        }
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("2. Battery settings", fontWeight = FontWeight.SemiBold)
                Text("Some phones (Xiaomi, Oppo, Vivo, Samsung) stop apps in the background. Set TravelBuddy to \"Unrestricted\" / \"Don't optimise\" so the ride notification keeps working with the screen off.")
                OutlinedButton(onClick = { openBatterySettings(ctx) }) { Text("Open battery settings") }
            }
        }
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("3. How it works", fontWeight = FontWeight.SemiBold)
                Text("Drivers post a ride offer; passengers ask for a seat or post a request. Everything is free and between colleagues.")
            }
        }
        Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text("Continue") }
    }
}

fun openBatterySettings(ctx: android.content.Context) {
    val tries = listOf(
        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}")),
    )
    for (i in tries) if (runCatching { ctx.startActivity(i) }.isSuccess) return
}

// ---------------------------------------------------------------- main shell

/** Saves the screen stack as plain strings so it survives activity recreation. */
private val RouteStackSaver = androidx.compose.runtime.saveable.listSaver<androidx.compose.runtime.snapshots.SnapshotStateList<Route>, String>(
    save = { list ->
        list.map {
            when (it) {
                is Route.Ride -> "ride:${it.id}"
                Route.AdminStops -> "stops"
                Route.AdminAudit -> "audit"
                Route.AdminReports -> "reports"
            }
        }
    },
    restore = { saved ->
        mutableStateListOf<Route>().apply {
            saved.forEach { s ->
                when {
                    s.startsWith("ride:") -> add(Route.Ride(s.removePrefix("ride:")))
                    s == "stops" -> add(Route.AdminStops)
                    s == "audit" -> add(Route.AdminAudit)
                    s == "reports" -> add(Route.AdminReports)
                }
            }
        }
    },
)

sealed interface Route {
    data class Ride(val id: String) : Route
    data object AdminStops : Route
    data object AdminAudit : Route
    data object AdminReports : Route
}

private enum class Tab(val label: String, val icon: ImageVector) {
    BOARD("Board", Icons.Default.DirectionsCar),
    MY_RIDES("My rides", Icons.Default.EventNote),
    HISTORY("History", Icons.Default.History),
    ADMIN("Admin", Icons.Default.AdminPanelSettings),
    SETTINGS("Settings", Icons.Default.Settings),
}

@Composable
private fun MainShell(activity: MainActivity, me: UserProfile) {
    val ctx = LocalContext.current
    var tab by rememberSaveable { mutableStateOf(Tab.BOARD) }
    val stack = rememberSaveable(saver = RouteStackSaver) { mutableStateListOf<Route>() }
    val openRide by activity.openRide

    LaunchedEffect(openRide) {
        openRide?.let { stack.add(Route.Ride(it)); activity.openRide.value = null }
    }
    LaunchedEffect(me.uid) {
        runCatching { Repo.loadStops() }
        AutoWait.checkOnOpen(ctx, me.uid)
    }

    val push: (Route) -> Unit = { stack.add(it) }
    val pop: () -> Unit = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
    BackHandler(enabled = stack.isNotEmpty()) { pop() }
    BackHandler(enabled = stack.isEmpty() && tab != Tab.BOARD) { tab = Tab.BOARD }

    when (val top = stack.lastOrNull()) {
        is Route.Ride -> { RideScreen(top.id, me, onBack = pop); return }
        Route.AdminStops -> { StopsEditorScreen(onBack = pop); return }
        Route.AdminAudit -> { AuditScreen(me, onBack = pop); return }
        Route.AdminReports -> { ReportsScreen(onBack = pop); return }
        null -> Unit
    }

    val tabs = Tab.entries.filter { it != Tab.ADMIN || me.isAdmin }
    Scaffold(
        contentWindowInsets = WindowInsets(0),
        bottomBar = {
            NavigationBar {
                tabs.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t,
                        onClick = { tab = t },
                        icon = { Icon(t.icon, null) },
                        label = { Text(t.label, maxLines = 1) },
                    )
                }
            }
        },
    ) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            when (tab) {
                Tab.BOARD -> BoardScreen(me, openRide = { push(Route.Ride(it)) })
                Tab.MY_RIDES -> MyRidesScreen(me, openRide = { push(Route.Ride(it)) })
                Tab.HISTORY -> HistoryScreen(me, openRide = { push(Route.Ride(it)) })
                Tab.ADMIN -> if (me.isAdmin) AdminHome(me, push) else Unit
                Tab.SETTINGS -> SettingsScreen(activity, me)
            }
        }
    }
}

@Composable
fun ScreenColumn(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        horizontalAlignment = Alignment.Start,
    ) { content() }
}
