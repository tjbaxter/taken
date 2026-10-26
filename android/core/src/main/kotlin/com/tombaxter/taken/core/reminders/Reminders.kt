package com.tombaxter.taken.core.reminders

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.NudgeWindow
import com.tombaxter.taken.core.stack.StackEngine
import java.time.Instant
import java.time.ZoneId

/**
 * One global nudge, planned for the next 14 days and rebuilt after every change, so a finished day never gets a
 * notification. The pure plan from Shared/Reminders.swift; Android's delivery (alarms, channels, receivers) is NEXT.
 */
object Reminders {
    const val REQUEST_PREFIX = "taken.nudge.day."
    /** The one-off note that a TAKE ALL on an earlier day's nudge logged nothing. */
    const val STALE_IDENTIFIER = "taken.nudge.stale"
    /** The one-off note that a nudge's TAKE ALL logged nothing because logging needs Taken Pro. */
    const val LOCKED_IDENTIFIER = "taken.pro.locked"
    const val HORIZON_DAYS = 14

    data class Plan(val identifier: String, val day: DayKey, val fireDate: Instant, val body: String)

    /**
     * Which nudges should exist right now. Without Taken Pro there are none, and a plan set not to renew is nudged only
     * until it ends. A weekly item is nudged on its due day only (SPEC 3.3, R4).
     */
    fun plan(state: StackState, now: Instant, zone: ZoneId = ZoneId.systemDefault(), window: NudgeWindow = NudgeWindow.Open): List<Plan> {
        if (window == NudgeWindow.Closed || !state.settings.reminderEnabled || state.items.isEmpty()) return emptyList()
        val clock = DayClock(state.settings.dayStartHour, zone)
        val engine = StackEngine(state, clock)
        val today = clock.day(now)
        val hour = state.settings.reminderMinutes / 60
        val minute = state.settings.reminderMinutes % 60
        val plans = ArrayList<Plan>()
        for (offset in 0 until HORIZON_DAYS) {
            val day = today.adding(offset)
            val fire = clock.date(day, hour, minute)
            if (fire <= now) continue
            if (window is NudgeWindow.Until && fire >= window.end) break
            val summary = if (offset == 0) engine.todaySummary(now) else engine.summary(day)
            val pending = summary.items.filter { it.isPending && !it.item.archived }
            if (pending.isEmpty()) continue
            plans.add(Plan(REQUEST_PREFIX + day.ordinal, day, fire, body(pending.map { it.item.code })))
        }
        return plans
    }

    /** The logical day a nudge was for: from its extra, else from its identifier ("taken.nudge.day.20738"). */
    fun nudgeDay(identifier: String, dayExtra: Int? = null): DayKey? {
        if (dayExtra != null) return DayKey(dayExtra)
        if (!identifier.startsWith(REQUEST_PREFIX)) return null
        return identifier.removePrefix(REQUEST_PREFIX).toIntOrNull()?.let { DayKey(it) }
    }

    /**
     * A nudge's TAKE ALL logs only on the day the nudge was for, so last night's nudge tapped this morning never logs
     * today's doses. A nudge with no day counts as today's.
     */
    fun isCurrent(nudgeDay: DayKey?, state: StackState, now: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (nudgeDay == null) return true
        return nudgeDay == DayClock(state.settings.dayStartHour, zone).day(now)
    }

    /**
     * Delivered nudges to withdraw: every earlier day's, and today's once nothing is pending. Today's stays while
     * something is still pending, so its TAKE ALL keeps working.
     */
    fun staleDelivered(identifiers: List<String>, state: StackState, now: Instant, zone: ZoneId = ZoneId.systemDefault()): List<String> {
        val clock = DayClock(state.settings.dayStartHour, zone)
        val today = clock.day(now)
        val todayDone = StackEngine(state, clock).todaySummary(now).pendingItems.isEmpty()
        return identifiers.filter { identifier ->
            val day = nudgeDay(identifier)
            if (day == null) {
                identifier == STALE_IDENTIFIER || identifier == LOCKED_IDENTIFIER
            } else {
                day < today || (day == today && todayDone)
            }
        }
    }

    /** "Nothing logged. That nudge was for MON 12 OCT. Tap to open that day." */
    fun staleBody(day: DayKey): String = "Nothing logged. That nudge was for ${Fmt.dayHeader(day)}. Tap to open that day."

    /** "2 pending: VD3, FSH" */
    fun body(codes: List<String>): String {
        val shown = codes.take(4).joinToString(", ")
        val extra = if (codes.size > 4) " +${codes.size - 4}" else ""
        return "${codes.size} pending: $shown$extra"
    }
}
