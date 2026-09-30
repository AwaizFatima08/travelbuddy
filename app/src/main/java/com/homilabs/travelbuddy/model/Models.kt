package com.homilabs.travelbuddy.model

import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentSnapshot

enum class AccountStatus { PENDING, ACTIVE, BLOCKED }
enum class RideType { OFFER, REQUEST }
enum class RideStatus { OPEN, FULL, STARTED, COMPLETED, CANCELLED }
enum class SeatStatus { ASKED, ACCEPTED, DECLINED }

enum class Direction(val label: String, val short: String) {
    TO_PLANT("Township → Plant", "To Plant"),
    TO_TOWNSHIP("Plant → Township", "To Township"),
}

data class AuditEntry(
    val action: String,
    val by: String,
    val byName: String,
    val at: Timestamp?,
    val reason: String,
)

data class UserProfile(
    val uid: String,
    val name: String,
    val email: String,
    val phone: String,
    val employeeId: String,
    val department: String,
    val townshipLocation: String,
    val status: AccountStatus,
    val role: String,
    val audit: List<AuditEntry>,
    val lastAdminActionAt: Timestamp?,
) {
    val isAdmin get() = role == "ADMIN" && status == AccountStatus.ACTIVE
    val lastAudit get() = audit.lastOrNull()
}

data class SeatRequest(
    val uid: String,
    val name: String,
    val phone: String,
    val stopId: String,
    val status: SeatStatus,
)

data class Stop(
    val id: String,
    val name: String,
    val lat: Double,
    val lng: Double,
    val active: Boolean,
    val order: Int,
)

data class DriverLoc(val lat: Double, val lng: Double, val at: Timestamp?)

data class Ride(
    val id: String,
    val type: RideType,
    val driverId: String,
    val driverName: String,
    val driverPhone: String,
    val posterId: String,
    val posterName: String,
    val posterPhone: String,
    val date: String,
    val slot: Slot,
    val direction: Direction,
    val departTime: String,
    val stopId: String,
    val stopName: String,
    val note: String,
    val totalSeats: Int,
    val status: RideStatus,
    val requests: Map<String, SeatRequest>,
    val participantIds: List<String>,
    val startedAt: Timestamp?,
    val completedAt: Timestamp?,
) {
    val acceptedCount get() = requests.values.count { it.status == SeatStatus.ACCEPTED }
    val seatsLeft get() = (totalSeats - acceptedCount).coerceAtLeast(0)
    val isFinished get() = status == RideStatus.COMPLETED || status == RideStatus.CANCELLED
    val hasDriver get() = driverId.isNotEmpty()

    fun isDriver(uid: String) = driverId == uid
    fun isPoster(uid: String) = posterId == uid

    /** True if [uid] rides as a confirmed passenger (accepted seat, or the poster of a taken REQUEST). */
    fun isConfirmedPassenger(uid: String) =
        !isDriver(uid) && uid in participantIds

    /** The stop where [uid] is picked up. */
    fun pickupStopId(uid: String): String = requests[uid]?.stopId?.takeIf { it.isNotEmpty() } ?: stopId

    /** Number of passengers the driver is sharing location with. */
    val passengerCount get() = participantIds.count { it != driverId }
}

// ---------- Firestore → model mapping (by hand, so R8 needs no keep rules) ----------

private inline fun <reified T : Enum<T>> enumOr(value: Any?, default: T): T =
    runCatching { enumValueOf<T>(value as String) }.getOrDefault(default)

@Suppress("UNCHECKED_CAST")
fun DocumentSnapshot.toUserProfile(): UserProfile? {
    if (!exists()) return null
    val audit = (get("audit") as? List<Map<String, Any?>>).orEmpty().map {
        AuditEntry(
            action = it["action"] as? String ?: "",
            by = it["by"] as? String ?: "",
            byName = it["byName"] as? String ?: "",
            at = it["at"] as? Timestamp,
            reason = it["reason"] as? String ?: "",
        )
    }
    return UserProfile(
        uid = id,
        name = getString("name").orEmpty(),
        email = getString("email").orEmpty(),
        phone = getString("phone").orEmpty(),
        employeeId = getString("employeeId").orEmpty(),
        department = getString("department").orEmpty(),
        townshipLocation = getString("townshipLocation").orEmpty(),
        status = enumOr(get("accountStatus"), AccountStatus.PENDING),
        role = getString("role") ?: "USER",
        audit = audit,
        lastAdminActionAt = getTimestamp("lastAdminActionAt"),
    )
}

@Suppress("UNCHECKED_CAST")
fun DocumentSnapshot.toRide(): Ride? {
    if (!exists()) return null
    val reqs = (get("requests") as? Map<String, Map<String, Any?>>).orEmpty().mapValues { (uid, m) ->
        SeatRequest(
            uid = uid,
            name = m["name"] as? String ?: "",
            phone = m["phone"] as? String ?: "",
            stopId = m["stopId"] as? String ?: "",
            status = enumOr(m["status"], SeatStatus.ASKED),
        )
    }
    return Ride(
        id = id,
        type = enumOr(get("type"), RideType.OFFER),
        driverId = getString("driverId").orEmpty(),
        driverName = getString("driverName").orEmpty(),
        driverPhone = getString("driverPhone").orEmpty(),
        posterId = getString("posterId").orEmpty(),
        posterName = getString("posterName").orEmpty(),
        posterPhone = getString("posterPhone").orEmpty(),
        date = getString("date").orEmpty(),
        slot = enumOr(get("slot"), Slot.MORNING),
        direction = enumOr(get("direction"), Direction.TO_PLANT),
        departTime = getString("departTime").orEmpty(),
        stopId = getString("stopId").orEmpty(),
        stopName = getString("stopName").orEmpty(),
        note = getString("note").orEmpty(),
        totalSeats = (getLong("totalSeats") ?: 1L).toInt(),
        status = enumOr(get("status"), RideStatus.OPEN),
        requests = reqs,
        participantIds = (get("participantIds") as? List<String>).orEmpty(),
        startedAt = getTimestamp("startedAt"),
        completedAt = getTimestamp("completedAt"),
    )
}

fun DocumentSnapshot.toDriverLoc(): DriverLoc? {
    if (!exists()) return null
    val lat = getDouble("lat") ?: return null
    val lng = getDouble("lng") ?: return null
    return DriverLoc(lat, lng, getTimestamp("at"))
}

@Suppress("UNCHECKED_CAST")
fun DocumentSnapshot.toStops(): List<Stop> =
    (get("stops") as? List<Map<String, Any?>>).orEmpty().map {
        Stop(
            id = it["id"] as? String ?: "",
            name = it["name"] as? String ?: "",
            lat = (it["lat"] as? Number)?.toDouble() ?: 0.0,
            lng = (it["lng"] as? Number)?.toDouble() ?: 0.0,
            active = it["active"] as? Boolean ?: true,
            order = (it["order"] as? Number)?.toInt() ?: 0,
        )
    }.sortedBy { it.order }

fun Stop.toMap(): Map<String, Any> =
    mapOf("id" to id, "name" to name, "lat" to lat, "lng" to lng, "active" to active, "order" to order)
