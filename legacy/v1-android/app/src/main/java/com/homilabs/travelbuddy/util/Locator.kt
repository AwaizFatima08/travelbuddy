package com.homilabs.travelbuddy.util

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

object Locator {
    fun hasPermission(context: Context) =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /** One location fix, or null if permission is missing / GPS is off / it takes too long. */
    @SuppressLint("MissingPermission")
    suspend fun current(context: Context, highAccuracy: Boolean = false): Location? {
        if (!hasPermission(context)) return null
        val client = LocationServices.getFusedLocationProviderClient(context)
        val priority = if (highAccuracy) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY
        val cts = CancellationTokenSource()
        return runCatching {
            withTimeoutOrNull(15_000) { client.getCurrentLocation(priority, cts.token).await() }
                ?: client.lastLocation.await()
        }.getOrNull().also { cts.cancel() }
    }
}
