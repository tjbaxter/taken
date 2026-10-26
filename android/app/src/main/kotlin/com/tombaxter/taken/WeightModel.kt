package com.tombaxter.taken

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.weight.WeighIn
import com.tombaxter.taken.core.weight.WeightCSV
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightGate
import com.tombaxter.taken.core.weight.WeightGoal
import com.tombaxter.taken.core.weight.WeightGoals
import com.tombaxter.taken.core.weight.WeightImport
import com.tombaxter.taken.core.weight.WeightMoment
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightState
import com.tombaxter.taken.core.weight.WeightTrend
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.data.MemoryWeightPersistence
import com.tombaxter.taken.data.WeightPersistence
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/**
 * The Weight tab's state (SPEC 3.12, SPEC-ANDROID 12), ported from Taken/Weight/WeightModel.swift: weights.json through
 * [WeightPersistence], with the page's in-memory state (the draft, the visit's line), never stored. Every field the
 * screen reads is Compose snapshot state, as AppModel's are. Writes go through [write]: the screen at once, the file
 * after, and the screen ends on what the file holds (SPEC-ANDROID 5.1).
 */
class WeightModel(
    val persistence: WeightPersistence = MemoryWeightPersistence(),
    initialState: WeightState = WeightState(),
    private val clockNow: () -> Instant = { Instant.now() },
    private val locale: () -> Locale = { Locale.getDefault() },
    val isDemo: Boolean = false,
) {
    var state: WeightState by mutableStateOf(initialState)
        private set

    /**
     * The point the weigh-in just saved lit, for this visit only: the small line under the number shows its sentence
     * until the Weight tab is left, Taken goes to the background, Undo is tapped or the next weigh-in is saved.
     */
    var justReached: WeightMoment? by mutableStateOf(null)

    /** What is typed into the big number; cleared whenever typing ends. */
    var draft: String by mutableStateOf("")

    /** The number has the keyboard (the page sets it as its field gains and loses focus). */
    var entryFocused: Boolean by mutableStateOf(false)

    /** The weigh-in saved on this visit: the small line then says how close the trend is to the goal. */
    var justSaved: UUID? by mutableStateOf(null)

    /** The lit dot springs once per visit. */
    var momentPlayed: Boolean by mutableStateOf(false)

    /** Edit… on today's number: All weigh-ins opens straight at this weigh-in. */
    var editOnOpen: UUID? by mutableStateOf(null)

    /** All weigh-ins' editor page: the weigh-in open in it, or null for the list. */
    var editing: UUID? by mutableStateOf(null)

    /** A tap on the number asked for the keyboard and Pro allowed it (`requireWeightPro`): the page focuses the field. */
    var entryRequested: Boolean by mutableStateOf(false)

    /** Profile's line under Import weight CSV once a file was read. */
    var importNote: String? by mutableStateOf(null)

    /** Debug captures only: what the Goal sheet's field holds when it opens (`weight-goal-low`). */
    var demoTypedGoal: String? = null

    /** Debug captures only: the page opens scrolled to screen two (`weight-trend`, `weight-goal`). */
    var demoOpensOnTrend: Boolean = false

    /** A write that could not be saved: the app model shows "Could not save. Try again.". */
    var onWriteFailed: () -> Unit = {}

    // MARK: Reading

    /** The tab is on only once the person turned it on (null is off). */
    val showsTab: Boolean get() = state.showsTab == true

    val unit: WeightUnit get() = state.unit ?: WeightUnit.preferred(locale())

    val range: WeightRange get() = state.range ?: WeightRange.ALL

    val isEmpty: Boolean get() = state.weighIns.isEmpty()

    /** Profile > Data shows the weight CSV rows once the tab is on or there is anything to export. */
    val showsDataRows: Boolean get() = showsTab || !isEmpty

    val goal: WeightGoal? get() = state.goal

    /** Whether a weigh-in may be logged, edited, backdated or imported now (`WeightGate`): the first one ever needs no Pro. */
    fun access(status: ProStatus?, settled: Boolean, legacyLog: Boolean, now: Instant): ProAccess =
        WeightGate.access(state.firstWeighInAt, status, settled, legacyLog, now)

    /** The goal's points, worked out from the weigh-ins, the goal and the height (`WeightGoals.moments`). None without a goal. */
    fun moments(clock: DayClock): List<WeightMoment> {
        val goal = state.goal ?: return emptyList()
        val trend = WeightTrend.trend(state.weighIns, clock)
        return WeightGoals.moments(goal, trend, state.weighInDays(clock), state.heightCm)
    }

    /** The end of a visit to the tab (it is left, Taken goes to the background): the line's sentence and the draft go. */
    fun endVisit() {
        justReached = null
        justSaved = null
        momentPlayed = false
        draft = ""
    }

    /** taken-weight.csv as it is now, built when called. */
    fun csv(zone: ZoneId = ZoneId.systemDefault()): String = WeightCSV.make(state.weighIns, zone)

    /** The file changed under the screen. Adopted only when no write of the model's is on its way. */
    fun adopt(fresh: WeightState) {
        if (persistence.busy || fresh == state) return
        state = fresh
    }

    // MARK: Changing

    /** Every write goes through here: the screen at once, then the file. */
    private fun <T> write(body: (WeightState) -> T): T {
        val base = state
        val next = base.clone()
        val value = body(next)
        state = next
        persistence.save(base, next, { body(it) }, settled = { onDisk -> if (onDisk != state) state = onDisk }) {
            onWriteFailed()
        }
        return value
    }

    fun setShowsTab(on: Boolean) {
        write { it.showsTab = on }
    }

    fun setUnit(unit: WeightUnit) {
        if (unit == state.unit) return
        write { it.unit = unit }
    }

    fun setRange(range: WeightRange) {
        write { it.range = range }
    }

    /** Add tab or Not now on Today's offer: either answer is final, and Add tab turns the tab on. */
    fun answerOffer(addTab: Boolean) {
        write { s ->
            s.offerAnswered = true
            if (addTab) s.showsTab = true
        }
    }

    /** Saves a weigh-in now, where the phone is. Its id and moment are made before the write, so a replay stores the same. */
    fun log(kg: Double, zone: ZoneId = ZoneId.systemDefault()): WeighIn {
        val at = clockNow()
        val id = UUID.randomUUID()
        return write { it.log(kg, at, zone, id) }
    }

    /** Returns the weigh-in as it was before, for Undo. */
    fun update(id: UUID, kg: Double, at: Instant, zone: ZoneId = ZoneId.systemDefault()): WeighIn? =
        write { it.update(id, kg, at, zone) }

    fun delete(id: UUID): WeighIn? = write { it.delete(id) }

    fun restore(weighIn: WeighIn) {
        write { it.restore(weighIn) }
    }

    /** Weigh-ins read from a CSV (`WeightImport.parse`), merged by the minute. The line Profile shows after it. */
    fun importCsv(text: String, locale: Locale = this.locale(), zone: ZoneId = ZoneId.systemDefault()): String {
        val now = clockNow()
        return when (val result = WeightImport.parse(text, unit, locale, zone, now)) {
            is WeightImport.Result.Failed -> WeightCopy.NOT_FOUND
            is WeightImport.Result.Success -> {
                val merged = write { it.merge(result.parsed.weighIns, now) }
                WeightCopy.imported(merged.added, merged.already, result.parsed.unreadable, result.parsed.unit)
            }
        }
    }

    /** Set goal or Change goal: the goal and, if one was chosen, the height. */
    fun setGoal(goal: WeightGoal, heightCm: Double?) {
        write { s ->
            s.goal = goal
            if (heightCm != null) s.heightCm = heightCm
        }
    }

    /** Clear goal: the goal as it was, for Undo. The height stays for the next goal; Erase removes it. */
    fun clearGoal(): WeightGoal? {
        if (state.goal == null) return null
        justReached = null
        return write { s -> s.goal.also { s.goal = null } }
    }

    /** Undo on Goal cleared: the same goal, start included. */
    fun restoreGoal(goal: WeightGoal) {
        write { it.goal = goal }
    }

    /**
     * Erase all data: the weigh-ins, the goal and the height go; the tab setting, the unit, the offer's answer and the
     * first weigh-in's date stay. The set-aside copies go with the app's (`Persistence.eraseExtras`).
     */
    fun eraseAll() {
        justReached = null
        justSaved = null
        editing = null
        write { it.eraseAll() }
    }
}
