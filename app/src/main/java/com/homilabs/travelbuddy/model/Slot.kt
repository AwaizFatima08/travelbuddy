package com.homilabs.travelbuddy.model

import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/** The 4 commute windows, Pakistan time. */
enum class Slot(
    val label: String,
    val start: LocalTime,
    val end: LocalTime,
    val defaultDirection: Direction,
) {
    MORNING("Morning", LocalTime.of(7, 15), LocalTime.of(8, 0), Direction.TO_PLANT),
    LUNCH_OUT("Lunch out", LocalTime.of(12, 45), LocalTime.of(13, 15), Direction.TO_TOWNSHIP),
    LUNCH_IN("Lunch in", LocalTime.of(13, 45), LocalTime.of(14, 30), Direction.TO_PLANT),
    EVENING("Evening", LocalTime.of(17, 0), LocalTime.of(18, 30), Direction.TO_TOWNSHIP);

    val window: String get() = "${start.format(HM)}–${end.format(HM)}"
}

private val HM: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

/** One slot on one date, e.g. "Lunch in on 2026-10-01". */
data class SlotInstance(val date: LocalDate, val slot: Slot) {
    val dateKey: String get() = date.toString() // YYYY-MM-DD
    val startAt: ZonedDateTime get() = date.atTime(slot.start).atZone(SlotClock.ZONE)
    val endAt: ZonedDateTime get() = date.atTime(slot.end).atZone(SlotClock.ZONE)

    fun label(today: LocalDate = SlotClock.today()): String {
        val day = when (date) {
            today -> "Today"
            today.plusDays(1) -> "Tomorrow"
            else -> date.format(DateTimeFormatter.ofPattern("EEE d MMM"))
        }
        return "$day · ${slot.label} ${slot.window}"
    }

    fun next(): SlotInstance {
        val all = Slot.entries
        val i = all.indexOf(slot)
        return if (i < all.lastIndex) SlotInstance(date, all[i + 1]) else SlotInstance(date.plusDays(1), all.first())
    }
}

object SlotClock {
    val ZONE: ZoneId = ZoneId.of("Asia/Karachi")

    fun now(): ZonedDateTime = ZonedDateTime.now(ZONE)
    fun today(): LocalDate = now().toLocalDate()

    /** The slot running now, or — outside the windows — the NEXT slot. */
    fun current(now: ZonedDateTime = now()): SlotInstance {
        val date = now.toLocalDate()
        val t = now.toLocalTime()
        for (s in Slot.entries) if (t.isBefore(s.end)) return SlotInstance(date, s)
        return SlotInstance(date.plusDays(1), Slot.MORNING)
    }

    /** The current slot followed by the next [count]-1 slots. */
    fun upcoming(count: Int = 4, now: ZonedDateTime = now()): List<SlotInstance> =
        generateSequence(current(now)) { it.next() }.take(count).toList()

    fun isValidTime(text: String): Boolean =
        runCatching { LocalTime.parse(text, HM) }.isSuccess

    fun formatTime(t: LocalTime): String = t.format(HM)
}
