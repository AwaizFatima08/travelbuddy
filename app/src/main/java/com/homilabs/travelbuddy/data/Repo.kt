package com.homilabs.travelbuddy.data

import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.firestore.AggregateSource
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.homilabs.travelbuddy.model.AccountStatus
import com.homilabs.travelbuddy.model.Direction
import com.homilabs.travelbuddy.model.DriverLoc
import com.homilabs.travelbuddy.model.Ride
import com.homilabs.travelbuddy.model.RideStatus
import com.homilabs.travelbuddy.model.RideType
import com.homilabs.travelbuddy.model.SeatStatus
import com.homilabs.travelbuddy.model.Slot
import com.homilabs.travelbuddy.model.SlotClock
import com.homilabs.travelbuddy.model.SlotInstance
import com.homilabs.travelbuddy.model.Stop
import com.homilabs.travelbuddy.model.UserProfile
import com.homilabs.travelbuddy.model.toDriverLoc
import com.homilabs.travelbuddy.model.toMap
import com.homilabs.travelbuddy.model.toRide
import com.homilabs.travelbuddy.model.toStops
import com.homilabs.travelbuddy.model.toUserProfile
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.time.LocalDate

/** A user-facing error with a plain-English message. */
class AppError(message: String) : Exception(message)

sealed interface UserState {
    data object Loading : UserState
    data object Missing : UserState
    data class Loaded(val profile: UserProfile) : UserState
    data class Error(val message: String) : UserState
}

data class RegisterForm(
    val name: String,
    val email: String,
    val password: String,
    val employeeId: String,
    val department: String,
    val phone: String,
    val townshipLocation: String,
)

data class Report(
    val fromDate: String,
    val ridesPosted: Long,
    val completed: Int,
    val cancelled: Long,
    val seatsShared: Int,
    val completedBySlot: Map<Slot, Int>,
    val topVolunteers: List<Pair<String, Int>>,
    val activeMembers: Long,
    val pendingMembers: Long,
    val blockedMembers: Long,
)

/**
 * All Firestore / Auth access. Read budget rules:
 *  - listeners only on: own user doc, ride board query, one ride doc, its live loc doc, pending users
 *  - everything else is a one-time get
 *  - every listener is removed in awaitClose when the screen stops collecting
 */
object Repo {
    private val auth get() = FirebaseAuth.getInstance()
    private val db get() = FirebaseFirestore.getInstance()
    private val users get() = db.collection("users")
    private val rides get() = db.collection("rides")
    private val stopsDoc get() = db.collection("settings").document("stops")
    private fun locDoc(rideId: String) = rides.document(rideId).collection("live").document("loc")

    // ------------------------------------------------------------------ auth

    val currentUser: FirebaseUser? get() = auth.currentUser

    fun authFlow(): Flow<FirebaseUser?> = callbackFlow {
        val l = FirebaseAuth.AuthStateListener { trySend(it.currentUser) }
        auth.addAuthStateListener(l)
        awaitClose { auth.removeAuthStateListener(l) }
    }

    private val _registering = MutableStateFlow(false)
    val registering: StateFlow<Boolean> = _registering.asStateFlow()

    /** Kept in memory so an interrupted profile save can be retried from the "setup not finished" screen. */
    var lastRegisterForm: RegisterForm? = null
        private set

    // NonCancellable: creating the Auth user swaps the screen (the register screen leaves
    // composition), which would otherwise cancel the profile write half-way.
    suspend fun register(f: RegisterForm) = withContext(NonCancellable) {
        lastRegisterForm = f.copy(password = "") // never keep the password
        _registering.value = true
        try {
            val result = auth.createUserWithEmailAndPassword(f.email.trim(), f.password).await()
            val uid = result.user?.uid ?: throw AppError("Registration failed. Please try again.")
            users.document(uid).set(
                mapOf(
                    "name" to f.name.trim(),
                    "email" to f.email.trim().lowercase(),
                    "phone" to f.phone.trim(),
                    "employeeId" to f.employeeId.trim(),
                    "department" to f.department.trim(),
                    "townshipLocation" to f.townshipLocation.trim(),
                    "accountStatus" to AccountStatus.PENDING.name,
                    "role" to "USER",
                )
            ).await()
        } finally {
            _registering.value = false
        }
    }

    /** Retry the profile write for an already-created Auth user (same form, same session). */
    suspend fun finishRegistration() {
        val f = lastRegisterForm ?: throw AppError("Please log out and contact the admin.")
        val uid = auth.currentUser?.uid ?: throw AppError("Please log in again.")
        users.document(uid).set(
            mapOf(
                "name" to f.name.trim(), "email" to f.email.trim().lowercase(), "phone" to f.phone.trim(),
                "employeeId" to f.employeeId.trim(), "department" to f.department.trim(),
                "townshipLocation" to f.townshipLocation.trim(),
                "accountStatus" to AccountStatus.PENDING.name, "role" to "USER",
            )
        ).await()
    }

    suspend fun login(email: String, password: String) {
        auth.signInWithEmailAndPassword(email.trim(), password).await()
    }

    suspend fun sendPasswordReset(email: String) {
        auth.sendPasswordResetEmail(email.trim()).await()
    }

    fun logout() {
        _stops.value = emptyList()
        stopsLoaded = false
        auth.signOut()
    }

    fun userFlow(uid: String): Flow<UserState> = callbackFlow {
        trySend(UserState.Loading)
        val reg = users.document(uid).addSnapshotListener { snap, e ->
            when {
                e != null -> trySend(UserState.Error(friendly(e)))
                snap == null || !snap.exists() -> trySend(UserState.Missing)
                else -> trySend(UserState.Loaded(snap.toUserProfile()!!))
            }
        }
        awaitClose { reg.remove() }
    }

    // ------------------------------------------------------------------ stops (read once, cached)

    private val _stops = MutableStateFlow<List<Stop>>(emptyList())
    val stops: StateFlow<List<Stop>> = _stops.asStateFlow()
    private var stopsLoaded = false

    suspend fun loadStops(force: Boolean = false): List<Stop> {
        if (stopsLoaded && !force) return _stops.value
        val snap = stopsDoc.get().await()
        _stops.value = snap.toStops()
        stopsLoaded = true
        return _stops.value
    }

    suspend fun saveStops(list: List<Stop>) {
        val ordered = list.mapIndexed { i, s -> s.copy(order = i) }
        stopsDoc.set(mapOf("stops" to ordered.map { it.toMap() })).await()
        _stops.value = ordered
        stopsLoaded = true
    }

    fun stopById(id: String): Stop? = _stops.value.firstOrNull { it.id == id }

    // ------------------------------------------------------------------ rides

    /** The ride board: ONE listener for (date, slot, direction, OPEN). */
    fun boardFlow(si: SlotInstance, dir: Direction): Flow<Result<List<Ride>>> = callbackFlow {
        val reg = rides
            .whereEqualTo("date", si.dateKey)
            .whereEqualTo("slot", si.slot.name)
            .whereEqualTo("direction", dir.name)
            .whereEqualTo("status", RideStatus.OPEN.name)
            .addSnapshotListener { snap, e ->
                if (e != null) trySend(Result.failure(AppError(friendly(e))))
                else trySend(Result.success(snap!!.documents.mapNotNull { it.toRide() }.sortedBy { it.departTime }))
            }
        awaitClose { reg.remove() }
    }

    fun rideFlow(id: String): Flow<Result<Ride?>> = callbackFlow {
        val reg = rides.document(id).addSnapshotListener { snap, e ->
            if (e != null) trySend(Result.failure(AppError(friendly(e))))
            else trySend(Result.success(snap?.toRide()))
        }
        awaitClose { reg.remove() }
    }

    /** Driver's live location. Readable only by the ride's driver and confirmed passengers. */
    fun locFlow(rideId: String): Flow<DriverLoc?> = callbackFlow {
        val reg = locDoc(rideId).addSnapshotListener { snap, e ->
            trySend(if (e != null) null else snap?.toDriverLoc())
        }
        awaitClose { reg.remove() }
    }

    private fun deleteAtFor(date: LocalDate): Timestamp =
        Timestamp(date.plusDays(30).atTime(12, 0).atZone(SlotClock.ZONE).toEpochSecond(), 0)

    suspend fun postRide(
        me: UserProfile,
        type: RideType,
        si: SlotInstance,
        direction: Direction,
        departTime: String,
        stop: Stop,
        seats: Int,
        note: String,
    ): String {
        val offer = type == RideType.OFFER
        val doc = rides.document()
        doc.set(
            hashMapOf(
                "type" to type.name,
                "driverId" to if (offer) me.uid else "",
                "driverName" to if (offer) me.name else "",
                "driverPhone" to if (offer) me.phone else "",
                "posterId" to me.uid,
                "posterName" to me.name,
                "posterPhone" to me.phone,
                "date" to si.dateKey,
                "slot" to si.slot.name,
                "direction" to direction.name,
                "departTime" to departTime,
                "stopId" to stop.id,
                "stopName" to stop.name,
                "note" to note.trim().take(140),
                "totalSeats" to if (offer) seats else 1,
                "status" to RideStatus.OPEN.name,
                "requests" to emptyMap<String, Any>(),
                "participantIds" to listOf(me.uid),
                "startedAt" to null,
                "completedAt" to null,
                "deleteAt" to deleteAtFor(si.date),
            )
        ).await()
        return doc.id
    }

    /** Passenger asks for a seat: ONE update to requests.<uid>. */
    suspend fun askSeat(rideId: String, me: UserProfile, stopId: String) {
        rides.document(rideId).update(
            FieldPath.of("requests", me.uid),
            mapOf("name" to me.name, "phone" to me.phone, "stopId" to stopId, "status" to SeatStatus.ASKED.name),
        ).await()
    }

    suspend fun withdrawSeat(rideId: String, uid: String) {
        rides.document(rideId).update(FieldPath.of("requests", uid), FieldValue.delete()).await()
    }

    /** Driver accepts or declines. A transaction so two accepts can't overfill the car. */
    suspend fun decideSeat(rideId: String, passengerUid: String, accept: Boolean) {
        val ref = rides.document(rideId)
        db.runTransaction { tx ->
            val ride = tx.get(ref).toRide() ?: throw AppError("This ride no longer exists.")
            if (ride.status != RideStatus.OPEN && ride.status != RideStatus.FULL)
                throw AppError("This ride can no longer be changed.")
            val req = ride.requests[passengerUid] ?: throw AppError("That request was withdrawn.")
            val newStatus = if (accept) SeatStatus.ACCEPTED else SeatStatus.DECLINED
            if (accept && req.status != SeatStatus.ACCEPTED && ride.seatsLeft <= 0)
                throw AppError("No seats left.")
            val updated = ride.requests.mapValues { (uid, r) -> if (uid == passengerUid) r.copy(status = newStatus) else r }
            val accepted = updated.values.filter { it.status == SeatStatus.ACCEPTED }.map { it.uid }
            tx.update(
                ref,
                mapOf(
                    "requests.$passengerUid.status" to newStatus.name,
                    "participantIds" to listOf(ride.driverId) + accepted,
                    "status" to (if (accepted.size >= ride.totalSeats) RideStatus.FULL else RideStatus.OPEN).name,
                )
            )
            null
        }.await()
    }

    /** "Take this passenger" on a REQUEST. Only the driver fields change. */
    suspend fun takeRequest(rideId: String, me: UserProfile) {
        val ref = rides.document(rideId)
        db.runTransaction { tx ->
            val ride = tx.get(ref).toRide() ?: throw AppError("This request no longer exists.")
            if (ride.hasDriver || ride.status != RideStatus.OPEN) throw AppError("Someone already took this passenger.")
            if (ride.posterId == me.uid) throw AppError("You can't take your own request.")
            tx.update(
                ref,
                mapOf(
                    "driverId" to me.uid,
                    "driverName" to me.name,
                    "driverPhone" to me.phone,
                    "participantIds" to listOf(ride.posterId, me.uid),
                    "status" to RideStatus.FULL.name,
                )
            )
            null
        }.await()
    }

    suspend fun setRideStatus(rideId: String, status: RideStatus) {
        val m = mutableMapOf<String, Any>("status" to status.name)
        if (status == RideStatus.STARTED) m["startedAt"] = FieldValue.serverTimestamp()
        if (status == RideStatus.COMPLETED) m["completedAt"] = FieldValue.serverTimestamp()
        rides.document(rideId).update(m).await()
    }

    suspend fun deleteRide(rideId: String) {
        rides.document(rideId).delete().await()
    }

    /** Called by the driver's foreground service. Not awaited — Firestore queues it offline. */
    fun writeDriverLoc(rideId: String, lat: Double, lng: Double) {
        val oneDay = Timestamp(Timestamp.now().seconds + 24 * 3600, 0)
        locDoc(rideId).set(mapOf("lat" to lat, "lng" to lng, "at" to FieldValue.serverTimestamp(), "deleteAt" to oneDay))
    }

    suspend fun clearDriverLoc(rideId: String) {
        runCatching { locDoc(rideId).delete().await() }
    }

    /** Rides I'm part of from today on (one-time get). */
    suspend fun myUpcoming(uid: String, limit: Long = 20): List<Ride> =
        rides.whereArrayContains("participantIds", uid)
            .whereGreaterThanOrEqualTo("date", SlotClock.today().toString())
            .orderBy("date", Query.Direction.ASCENDING)
            .limit(limit)
            .get().await()
            .documents.mapNotNull { it.toRide() }

    /** Own history, newest first, 20 per page. */
    suspend fun history(uid: String, after: DocumentSnapshot?): Pair<List<Ride>, DocumentSnapshot?> {
        var q = rides.whereArrayContains("participantIds", uid)
            .orderBy("date", Query.Direction.DESCENDING)
            .limit(20)
        if (after != null) q = q.startAfter(after)
        val snap = q.get().await()
        return snap.documents.mapNotNull { it.toRide() } to snap.documents.lastOrNull()
    }

    // ------------------------------------------------------------------ admin

    fun pendingFlow(): Flow<Result<List<UserProfile>>> = callbackFlow {
        val reg = users.whereEqualTo("accountStatus", AccountStatus.PENDING.name)
            .addSnapshotListener { snap, e ->
                if (e != null) trySend(Result.failure(AppError(friendly(e))))
                else trySend(Result.success(snap!!.documents.mapNotNull { it.toUserProfile() }.sortedBy { it.name }))
            }
        awaitClose { reg.remove() }
    }

    /** APPROVED → ACTIVE, BLOCKED → BLOCKED, UNBLOCKED → ACTIVE. Adds an audit entry (last 20 kept). */
    suspend fun adminAction(targetUid: String, action: String, reason: String, admin: UserProfile) {
        val newStatus = when (action) {
            "APPROVED", "UNBLOCKED" -> AccountStatus.ACTIVE
            "BLOCKED" -> AccountStatus.BLOCKED
            else -> throw AppError("Unknown action")
        }
        if (targetUid == admin.uid) throw AppError("You can't change your own account.")
        val ref = users.document(targetUid)
        db.runTransaction { tx ->
            val snap = tx.get(ref)
            if (!snap.exists()) throw AppError("That user no longer exists.")
            @Suppress("UNCHECKED_CAST")
            val old = (snap.get("audit") as? List<Map<String, Any?>>).orEmpty()
            val entry = mapOf(
                "action" to action,
                "by" to admin.uid,
                "byName" to admin.name,
                "at" to Timestamp.now(),
                "reason" to reason.trim().take(200),
            )
            tx.update(
                ref,
                mapOf(
                    "accountStatus" to newStatus.name,
                    "audit" to (old + entry).takeLast(20),
                    "lastAdminActionAt" to FieldValue.serverTimestamp(),
                )
            )
            null
        }.await()
    }

    suspend fun recentAdminActions(): List<UserProfile> =
        users.orderBy("lastAdminActionAt", Query.Direction.DESCENDING).limit(30)
            .get().await().documents.mapNotNull { it.toUserProfile() }

    suspend fun findUserByEmail(email: String): List<UserProfile> =
        users.whereEqualTo("email", email.trim().lowercase()).limit(5)
            .get().await().documents.mapNotNull { it.toUserProfile() }

    suspend fun loadReport(): Report {
        val from = SlotClock.today().minusDays(29).toString()
        suspend fun count(q: Query) = q.count().get(AggregateSource.SERVER).await().count

        val posted = count(rides.whereGreaterThanOrEqualTo("date", from))
        val cancelled = count(rides.whereEqualTo("status", RideStatus.CANCELLED.name).whereGreaterThanOrEqualTo("date", from))
        val completed = rides.whereEqualTo("status", RideStatus.COMPLETED.name)
            .whereGreaterThanOrEqualTo("date", from)
            .get().await().documents.mapNotNull { it.toRide() }

        val seats = completed.sumOf { if (it.type == RideType.REQUEST) 1 else it.acceptedCount }
        val bySlot = Slot.entries.associateWith { s -> completed.count { it.slot == s } }
        val top = completed.filter { it.hasDriver }
            .groupBy { it.driverId }
            .map { (_, list) -> list.first().driverName to list.size }
            .sortedByDescending { it.second }
            .take(10)

        return Report(
            fromDate = from,
            ridesPosted = posted,
            completed = completed.size,
            cancelled = cancelled,
            seatsShared = seats,
            completedBySlot = bySlot,
            topVolunteers = top,
            activeMembers = count(users.whereEqualTo("accountStatus", AccountStatus.ACTIVE.name)),
            pendingMembers = count(users.whereEqualTo("accountStatus", AccountStatus.PENDING.name)),
            blockedMembers = count(users.whereEqualTo("accountStatus", AccountStatus.BLOCKED.name)),
        )
    }

    // ------------------------------------------------------------------ errors

    fun friendly(e: Throwable): String {
        val msg = e.message.orEmpty()
        return when {
            e is AppError -> msg
            e.cause is AppError -> e.cause!!.message.orEmpty()
            "PERMISSION_DENIED" in msg || "permission" in msg.lowercase() -> "Not allowed. Your account may not be approved yet."
            "password is invalid" in msg || "INVALID_LOGIN_CREDENTIALS" in msg || "credential is incorrect" in msg ->
                "Wrong email or password."
            "no user record" in msg -> "No account with that email."
            "already in use" in msg -> "An account with this email already exists. Try logging in."
            "badly formatted" in msg -> "That email address doesn't look right."
            "at least 6 characters" in msg || "WEAK_PASSWORD" in msg -> "Password must be at least 6 characters."
            "network" in msg.lowercase() || "UNAVAILABLE" in msg -> "No internet connection. Please try again."
            "blocked all requests" in msg -> "Too many attempts. Please wait a few minutes."
            "FAILED_PRECONDITION" in msg -> "Database index is still building. Try again in a few minutes."
            else -> msg.ifBlank { "Something went wrong." }
        }
    }
}
