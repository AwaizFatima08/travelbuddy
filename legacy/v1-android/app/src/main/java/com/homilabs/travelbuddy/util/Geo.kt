package com.homilabs.travelbuddy.util

import com.google.firebase.Timestamp
import java.util.Locale
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

object Geo {
    /** Assumed average speed for the straight-line ETA. */
    private const val SPEED_KMH = 25.0
    const val APPROACH_METERS = 500.0
    const val APPROACH_MINUTES = 2.0
    const val STALE_AFTER_MS = 2 * 60 * 1000L

    /** Straight-line distance in metres (haversine). */
    fun distanceMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val r = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = sin(dLat / 2).pow(2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLng / 2).pow(2)
        return 2 * r * asin(sqrt(a))
    }

    fun etaMinutes(meters: Double): Double = meters / 1000.0 / SPEED_KMH * 60.0

    fun isApproaching(meters: Double) =
        meters < APPROACH_METERS || etaMinutes(meters) < APPROACH_MINUTES

    /** "~1.2 km, ~3 min" */
    fun etaText(meters: Double): String {
        val dist = if (meters < 1000) "~${(meters / 10).roundToInt() * 10} m"
        else "~${String.format(Locale.US, "%.1f", meters / 1000)} km"
        val min = etaMinutes(meters).roundToInt().coerceAtLeast(1)
        return "$dist, ~$min min"
    }

    /** "last updated 3 min ago" when the location is older than 2 minutes, else null. */
    fun staleText(at: Timestamp?, nowMs: Long = System.currentTimeMillis()): String? {
        at ?: return null
        val age = nowMs - at.toDate().time
        if (age < STALE_AFTER_MS) return null
        return "last updated ${age / 60_000} min ago"
    }
}
