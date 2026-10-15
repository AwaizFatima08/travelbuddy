package com.homilabs.travelbuddy.util

import android.content.Context
import android.content.SharedPreferences

/** Small on-phone settings. Nothing secret is stored here (no passwords, no tokens). */
class Prefs(context: Context) {
    private val sp: SharedPreferences =
        context.applicationContext.getSharedPreferences("tb_prefs", Context.MODE_PRIVATE)

    var biometricEnabled: Boolean
        get() = sp.getBoolean("biometric", false)
        set(v) = sp.edit().putBoolean("biometric", v).apply()

    var firstRunDone: Boolean
        get() = sp.getBoolean("first_run_done", false)
        set(v) = sp.edit().putBoolean("first_run_done", v).apply()

    /** Consent accepted on this phone before registering. */
    var consentAccepted: Boolean
        get() = sp.getBoolean("consent", false)
        set(v) = sp.edit().putBoolean("consent", v).apply()

    fun alertFired(rideId: String) = sp.getBoolean("alert_$rideId", false)
    fun markAlertFired(rideId: String) = sp.edit().putBoolean("alert_$rideId", true).apply()

    /** Rides for which the passenger dismissed "I'm waiting" (so auto-start doesn't restart it). */
    fun waitDismissed(rideId: String) = sp.getBoolean("wait_off_$rideId", false)
    fun markWaitDismissed(rideId: String) = sp.edit().putBoolean("wait_off_$rideId", true).apply()
}
