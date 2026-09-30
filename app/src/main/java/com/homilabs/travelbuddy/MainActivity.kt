package com.homilabs.travelbuddy

import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.service.Notif
import com.homilabs.travelbuddy.ui.AppRoot
import com.homilabs.travelbuddy.ui.theme.TravelBuddyTheme
import com.homilabs.travelbuddy.util.BiometricGate
import com.homilabs.travelbuddy.util.Prefs

/** FragmentActivity (not ComponentActivity) because BiometricPrompt needs it. */
class MainActivity : FragmentActivity() {

    lateinit var prefs: Prefs
    lateinit var biometric: BiometricGate

    /** True while the biometric lock screen should cover the app. */
    val locked = mutableStateOf(false)

    /** A ride to open (from a notification tap). */
    val openRide = mutableStateOf<String?>(null)

    /** Message shown on the login screen after a biometric fallback. */
    val loginNotice = mutableStateOf<String?>(null)

    private var stoppedAt = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        prefs = Prefs(this)
        biometric = BiometricGate(this)
        locked.value = savedInstanceState?.getBoolean("locked")
            ?: (prefs.biometricEnabled && Repo.currentUser != null)
        handleIntent(intent)
        setContent {
            TravelBuddyTheme {
                // Surface sets the right text colour for light and dark mode.
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { AppRoot(this) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent?.getStringExtra(Notif.EXTRA_OPEN_RIDE)?.let { openRide.value = it }
    }

    override fun onStop() {
        super.onStop()
        stoppedAt = SystemClock.elapsedRealtime()
    }

    override fun onStart() {
        super.onStart()
        // Lock again if the app was in the background for more than a minute.
        if (stoppedAt != 0L && SystemClock.elapsedRealtime() - stoppedAt > 60_000 &&
            prefs.biometricEnabled && Repo.currentUser != null
        ) locked.value = true
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean("locked", locked.value)
    }

    fun unlock() {
        biometric.authenticate("Unlock TravelBuddy") { outcome ->
            when (outcome) {
                BiometricGate.Outcome.Success -> locked.value = false
                BiometricGate.Outcome.Dismissed -> Unit
                is BiometricGate.Outcome.UsePassword -> fallbackToPassword(outcome.reason)
            }
        }
    }

    fun fallbackToPassword(reason: String) {
        loginNotice.value = reason
        Repo.logout()
        locked.value = false
    }
}
