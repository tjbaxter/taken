package com.tombaxter.taken

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.weight.GoalReadout
import com.tombaxter.taken.core.weight.WeightChangeLine
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightEntry
import com.tombaxter.taken.core.weight.WeightFigure
import com.tombaxter.taken.core.weight.WeightFormat
import com.tombaxter.taken.core.weight.WeightGoal
import com.tombaxter.taken.core.weight.WeightGoalCopy
import com.tombaxter.taken.core.weight.WeightGoals
import com.tombaxter.taken.core.weight.WeightLine
import com.tombaxter.taken.core.weight.WeightMoment
import com.tombaxter.taken.core.weight.WeightPoint
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightTicks
import com.tombaxter.taken.core.weight.WeightTrend
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.core.weight.WeightWindow
import com.tombaxter.taken.core.weight.day
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Locale
import java.util.UUID

// The app model's Weight tab actions (SPEC 3.12, SPEC-ANDROID 12), ported from the `AppModel` extension in
// Taken/Weight/WeightModel.swift. Weigh-ins follow the dose rule (the first one needs no Pro); weight never opens the
// paywall on its own.

/** Whether a weigh-in may be logged, edited, backdated or imported right now: Taken Pro, or the first weigh-in ever. */
val AppModel.weightAccess: ProAccess
    get() = weight.access(pro.status, pro.settled, legacyLog = false, now = now)

/**
 * Runs `action` while weigh-ins are open; otherwise opens the paywall and runs it once Pro is on, as `requirePro` does for
 * doses. `keepSheet`: asked from inside a sheet (All weigh-ins), which stays under the paywall.
 */
fun AppModel.requireWeightPro(keepSheet: Boolean = false, action: () -> Unit) {
    when (weightAccess) {
        ProAccess.PRO, ProAccess.FIRST_SESSION, ProAccess.PENDING -> action()
        ProAccess.LOCKED -> presentPaywall(PaywallOrigin.ACTION, action, keepSheet = keepSheet)
        ProAccess.CHECKING -> scope.launch {
            pro.settle()
            requireWeightPro(keepSheet, action)
        }
    }
}

/** A tap on the big number: the keyboard, once Pro allows it (the first weigh-in needs none). */
fun AppModel.requestWeightEntry() {
    requireWeightPro { weight.entryRequested = true }
}

/** Edit… on today's number: All weigh-ins, open straight at this weigh-in (editing follows the weigh-in rule). */
fun AppModel.editWeighIn(id: UUID) {
    requireWeightPro {
        weight.editOnOpen = id
        weight.editing = id
        sheet = Sheet.WeighIns
    }
}

/** All weigh-ins closes: the next time it opens on its list. */
fun AppModel.closeWeighIns() {
    weight.editing = null
    weight.editOnOpen = null
    if (sheet == Sheet.WeighIns) sheet = null
}

/** A row in All weigh-ins: its editor, once Pro allows it; without Pro the paywall comes over the sheet. */
fun AppModel.openWeighInEditor(id: UUID) {
    requireWeightPro(keepSheet = true) { weight.editing = id }
}

/** The big number right now (`WeightEntry.figure`). */
val AppModel.weightFigure: WeightFigure
    get() = WeightEntry.figure(weight.state.last, today.day, clock, weight.draft, weight.entryFocused)

/** The small line under it right now (`WeightEntry.line`). */
fun AppModel.weightLine(locale: Locale = Locale.getDefault()): WeightLine {
    val readout = if (weight.goal == null) null else weightPicture(weight.range).readout
    return WeightEntry.line(
        focused = weight.entryFocused, draft = weight.draft, unit = weight.unit, locale = locale,
        hasGoal = weight.goal != null, justSaved = weight.justSaved != null, justReached = weight.justReached,
        readout = readout,
    )
}

/**
 * Weigh in on the page: the number stays as today's, the trend moves, and "Weighed in" with Undo. If this weigh-in lights
 * a goal point dated its own day (`WeightGoals.fresh`), the small line shows its sentence for this visit; reaching the
 * goal plays the All taken haptic (CONFIRM) 0.35 s later, in place of the soft one. TalkBack hears the toast's sentence:
 * "Weighed in, 88.35 kilograms." and the moment, if any.
 */
fun AppModel.saveWeighIn(kg: Double, locale: Locale = Locale.getDefault()) {
    val clock = this.clock
    val before = weight.moments(clock)
    val saved = weight.log(kg, clock.zone)
    val fresh = WeightGoals.fresh(before, weight.moments(clock), clock.day(saved))
    weight.justReached = fresh
    weight.justSaved = saved.id
    weight.momentPlayed = false
    val unit = weight.unit
    if (fresh?.isGoal == true) {
        scope.launch {
            delay(350)
            feel(Haptic.CONFIRM)
        }
    } else {
        feel(Haptic.SOFT)
    }
    var spoken = "${WeightCopy.WEIGHED_IN}, ${WeightFormat.spoken(saved.kg, unit, locale)}."
    val goal = weight.goal
    if (fresh != null && goal != null) spoken += " " + WeightGoalCopy.spokenMoment(fresh, goal.kg, unit, locale)
    show(Toast(nextToastId(), WeightCopy.WEIGHED_IN, undo = UndoStep.RemoveWeighIn(saved.id), spoken = spoken))
}

/** Set goal or Change goal in the More options menu: the Goal sheet. Open in every Pro state, like the unit and the range. */
fun AppModel.openWeightGoal() {
    sheet = Sheet.WeightGoal
}

/** Save in the Goal sheet: the goal (with the height, if new), the soft haptic and "Goal set, 87.0 kilograms." No toast. */
fun AppModel.saveWeightGoal(kg: Double, startDay: DayKey, startPicked: Boolean, heightCm: Double?, locale: Locale = Locale.getDefault()) {
    weight.justReached = null
    weight.setGoal(WeightGoal(kg, startDay, startPicked), heightCm)
    feel(Haptic.SOFT)
    announce(WeightGoalCopy.goalSet(kg, weight.unit, locale))
}

/** Clear goal: at once, "Goal cleared" with Undo, nothing asked, because nothing is deleted. */
fun AppModel.clearWeightGoal() {
    val removed = weight.clearGoal() ?: return
    feel(Haptic.SOFT)
    show(Toast(nextToastId(), WeightGoalCopy.CLEARED, undo = UndoStep.RestoreWeightGoal(removed), spoken = WeightGoalCopy.CLEARED_SPOKEN))
}

/** A new weight, day or time from All weigh-ins, with Undo back to what it was. */
fun AppModel.updateWeighIn(id: UUID, kg: Double, at: Instant) {
    val before = weight.update(id, kg, at, clock.zone) ?: return
    feel(Haptic.SOFT)
    show(Toast(nextToastId(), WeightCopy.UPDATED, undo = UndoStep.RestoreWeighIn(before)))
}

/** A swipe in All weigh-ins, Delete in its editor or on today's number: always allowed, as removing a dose is, with Undo. */
fun AppModel.deleteWeighIn(id: UUID) {
    val removed = weight.delete(id) ?: return
    if (weight.editing == id) weight.editing = null
    feel(Haptic.SOFT)
    show(
        Toast(
            nextToastId(), WeightCopy.DELETED, time = WeightFormat.withUnit(removed.kg, weight.unit),
            undo = UndoStep.RestoreWeighIn(removed), spoken = "Weigh-in deleted.",
        ),
    )
}

/**
 * Hide Weight tab in the More options menu: Today comes to the front first (a hidden tab must not stay selected), then
 * the tab goes, and the toast says where it comes back. Nothing is deleted, so nothing is asked.
 */
fun AppModel.hideWeightTab() {
    tab = AppTab.TODAY
    weight.setShowsTab(false)
    show(Toast(nextToastId(), WeightCopy.HIDDEN, undo = UndoStep.ShowWeightTab))
}

/** Profile > Weight > Weight tab. Off while the tab is in front brings Today forward first; on never switches tabs. */
fun AppModel.setWeightTab(on: Boolean) {
    if (!on && tab == AppTab.WEIGHT) tab = AppTab.TODAY
    weight.setShowsTab(on)
}

/** The More options menu's Kilograms and Pounds. */
fun AppModel.setWeightUnit(unit: WeightUnit) {
    feel(Haptic.TICK)
    weight.setUnit(unit)
}

/** The chart's W, 30D, 90D, Y and All, remembered in weights.json. */
fun AppModel.setWeightRange(range: WeightRange) {
    if (range == weight.range) return
    feel(Haptic.TICK)
    weight.setRange(range)
}

/** taken://weight: the tab, or Today when it is off. */
fun AppModel.openWeightTab() {
    tab = if (weight.showsTab) AppTab.WEIGHT else AppTab.TODAY
}

/**
 * Profile > Data > Import weight CSV, once the file is read (`WeightImport.text`, null when it could not be read): the
 * line under the row says what happened.
 */
fun AppModel.importWeights(text: String?, locale: Locale = Locale.getDefault()): String {
    val line = if (text == null) WeightCopy.COULD_NOT_OPEN else weight.importCsv(text, locale, clock.zone)
    if (text != null) feel(Haptic.SOFT)
    weight.importNote = line
    return line
}

/** Undo on a weight toast. */
internal fun AppModel.undoWeight(step: UndoStep) {
    when (step) {
        is UndoStep.RemoveWeighIn -> {
            // The point that weigh-in lit, and its line, go with it; saving the same number again lights it again.
            weight.justReached = null
            weight.justSaved = null
            weight.delete(step.id)
        }
        is UndoStep.RestoreWeightGoal -> weight.restoreGoal(step.goal)
        is UndoStep.RestoreWeighIn -> weight.restore(step.weighIn)
        UndoStep.ShowWeightTab -> {
            weight.setShowsTab(true)
            tab = AppTab.WEIGHT
        }
        else -> Unit
    }
}

/**
 * The Weight tab's trend, chart window, goal points, slot reading and change line, worked out from the file and the
 * stack's weekly doses.
 */
fun AppModel.weightPicture(range: WeightRange): WeightPicture {
    val state = weight.state
    val trend = WeightTrend.trend(state.weighIns, clock)
    val window = WeightWindow.make(state.weighIns, trend, WeightTicks.days(engine), range, today.day, clock, state.goal?.kg)
    var moments: List<WeightMoment> = emptyList()
    var readout: GoalReadout? = null
    val goal = state.goal
    if (goal != null) {
        moments = WeightGoals.moments(goal, trend, state.weighInDays(clock), state.heightCm)
        readout = WeightGoals.readout(goal, trend, moments, weight.unit)
    }
    return WeightPicture(trend, window, moments, readout, WeightChangeLine.make(range, trend, window))
}

/** Everything the Weight tab draws for one range. */
data class WeightPicture(
    val trend: List<WeightPoint>,
    val window: WeightWindow,
    /** Every goal point, oldest first. */
    val moments: List<WeightMoment>,
    /** The slot's reading; null without a goal. */
    val readout: GoalReadout?,
    /** The change line for the range; null with fewer than two trend days in view. */
    val change: WeightChangeLine.Change?,
) {
    /** The points inside the range. */
    val momentsInView: List<WeightMoment> get() = moments.filter { window.contains(it.day) }
}
