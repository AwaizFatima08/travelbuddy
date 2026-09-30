package com.homilabs.travelbuddy

import android.app.Application
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.PersistentCacheSettings
import com.google.firebase.firestore.firestoreSettings
import com.homilabs.travelbuddy.service.Notif

class TravelBuddyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG && BuildConfig.USE_EMULATOR) {
            // Local test mode only (debug builds). Release builds always use the real project.
            FirebaseFirestore.getInstance().useEmulator("127.0.0.1", 8185)
            FirebaseAuth.getInstance().useEmulator("127.0.0.1", 9199)
        }
        // Keep the offline cache on (saves reads, works with weak signal).
        FirebaseFirestore.getInstance().firestoreSettings = firestoreSettings {
            setLocalCacheSettings(PersistentCacheSettings.newBuilder().build())
        }
        Notif.createChannels(this)
    }
}
