package com.homilabs.travelbuddy.service

import android.content.Context
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.Ride
import com.homilabs.travelbuddy.model.SlotClock
import com.homilabs.travelbuddy.model.SlotInstance
import com.homilabs.travelbuddy.util.Prefs
import java.time.LocalDate

/**
 * Starts "I'm waiting" automatically from 10 min before the slot — but only while the
 * app is open (Android doesn't allow starting it from the background without exact alarms).
 */
object AutoWait {
    private const val LEAD_MIN = 10L

    fun inWindow(ride: Ride): Boolean {
        val date = runCatching { LocalDate.parse(ride.date) }.getOrNull() ?: return false
        val si = SlotInstance(date, ride.slot)
        val now = SlotClock.now()
        return !now.isBefore(si.startAt.minusMinutes(LEAD_MIN)) && now.isBefore(si.endAt)
    }

    fun maybeStart(context: Context, ride: Ride, uid: String) {
        if (!ride.isConfirmedPassenger(uid) || ride.isFinished || !inWindow(ride)) return
        if (Prefs(context).waitDismissed(ride.id)) return
        if (PassengerWaitService.waitingFor.value == ride.id) return
        if (!Notif.canPost(context)) return
        runCatching { PassengerWaitService.start(context, ride.id, uid) }
    }

    /** On app open: only queries Firestore when we're inside a slot's waiting window. */
    suspend fun checkOnOpen(context: Context, uid: String) {
        val cur = SlotClock.current()
        val now = SlotClock.now()
        if (now.isBefore(cur.startAt.minusMinutes(LEAD_MIN))) return
        val rides = runCatching { Repo.myUpcoming(uid, limit = 5) }.getOrDefault(emptyList())
        rides.filter { it.date == cur.dateKey && it.slot == cur.slot }.forEach { maybeStart(context, it, uid) }
    }
}
