package com.homilabs.travelbuddy.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.homilabs.travelbuddy.BuildConfig
import com.homilabs.travelbuddy.MainActivity
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.UserProfile
import com.homilabs.travelbuddy.service.DriverLocationService
import com.homilabs.travelbuddy.service.PassengerWaitService
import com.homilabs.travelbuddy.util.BiometricGate

const val PRIVACY_URL = "https://travelbuddy.homilabs.org/privacy.html"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(activity: MainActivity, me: UserProfile) {
    val ctx = LocalContext.current
    var bio by remember { mutableStateOf(activity.prefs.biometricEnabled) }
    var confirmLogout by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    Scaffold(contentWindowInsets = WindowInsets(0), topBar = { TopAppBar(title = { Text("Settings") }) }) { pad ->
        ScreenColumn(Modifier.padding(pad)) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text(me.name, style = MaterialTheme.typography.titleMedium)
                    LabeledValue("Email", me.email)
                    LabeledValue("Phone", me.phone)
                    LabeledValue("Employee ID", me.employeeId)
                    LabeledValue("Department", me.department)
                    LabeledValue("Township", me.townshipLocation)
                    if (me.isAdmin) LabeledValue("Role", "Admin")
                }
            }

            SectionTitle("Security")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Unlock with fingerprint / face")
                    Text(
                        if (activity.biometric.available) "Asks for your fingerprint when the app opens. Your password is never stored."
                        else "Set up a fingerprint or face in your phone settings first.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = bio,
                    enabled = activity.biometric.available || bio,
                    onCheckedChange = { on ->
                        if (!on) {
                            activity.prefs.biometricEnabled = false; bio = false
                            activity.biometric.deleteKey()
                        } else {
                            // Confirm once before turning it on.
                            activity.biometric.authenticate("Turn on fingerprint unlock") { r ->
                                if (r == BiometricGate.Outcome.Success) {
                                    activity.prefs.biometricEnabled = true; bio = true
                                    ctx.toast("Fingerprint unlock is on")
                                } else if (r is BiometricGate.Outcome.UsePassword) ctx.toast(r.reason)
                            }
                        }
                    },
                )
            }

            SectionTitle("Reliable alerts")
            OutlinedButton(onClick = { openBatterySettings(ctx) }) { Text("Battery optimisation settings") }
            OutlinedButton(onClick = {
                ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}")))
            }) { Text("App permissions") }

            SectionTitle("About")
            TextButton(onClick = { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL))) } }) {
                Text("Privacy policy")
            }
            Text("TravelBuddy ${BuildConfig.VERSION_NAME} · free volunteer carpool, no payments.", style = MaterialTheme.typography.bodySmall)

            OutlinedButton(onClick = { confirmLogout = true }, modifier = Modifier.fillMaxWidth()) { Text("Log out") }
            TextButton(
                onClick = { confirmDelete = true },
                colors = androidx.compose.material3.ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) { Text("Delete my account") }
        }
    }
    if (confirmDelete) DeleteAccountDialog(onDismiss = { confirmDelete = false })
    if (confirmLogout) ConfirmDialog(
        "Log out?", "You'll need your email and password to log in again.", "Log out",
        onConfirm = {
            DriverLocationService.stop(ctx)
            PassengerWaitService.stop(ctx)
            Repo.logout()
        },
        onDismiss = { confirmLogout = false },
    )
}
