package com.tombaxter.taken

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.ItemDraft
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.PendingLog
import com.tombaxter.taken.core.pro.PlanPrice
import com.tombaxter.taken.core.pro.PlayEntitlement
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProLedgers
import com.tombaxter.taken.core.pro.ProPendingAction
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProRoute
import com.tombaxter.taken.core.pro.of
import com.tombaxter.taken.core.reminders.TrialReminder
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.retention.RetentionCopy
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.retention.TodayPrompts
import com.tombaxter.taken.core.stack.Adherence
import com.tombaxter.taken.core.stack.CsvExport
import com.tombaxter.taken.core.stack.DaySummary
import com.tombaxter.taken.core.stack.HistoryCell
import com.tombaxter.taken.core.stack.ItemDay
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.TodayRules
import com.tombaxter.taken.core.stack.addItems
import com.tombaxter.taken.core.stack.deleteItem
import com.tombaxter.taken.core.stack.doseAt
import com.tombaxter.taken.core.stack.eraseAll
import com.tombaxter.taken.core.stack.insertDose
import com.tombaxter.taken.core.stack.logNextDoseIfPending
import com.tombaxter.taken.core.stack.moveActiveItems
import com.tombaxter.taken.core.stack.removeDoses
import com.tombaxter.taken.core.stack.restore
import com.tombaxter.taken.core.stack.setArchived
import com.tombaxter.taken.core.stack.setDoseTime
import com.tombaxter.taken.core.stack.takeAllPending
import com.tombaxter.taken.core.stack.updateItem
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.core.weight.WeighIn
import com.tombaxter.taken.core.weight.WeightOffer
import com.tombaxter.taken.data.Persistence
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The tabs (SPEC-ANDROID 6.2). To-do joins with its phase (NEXT 5). Weight is last and shows only while the person has
 * turned it on (SPEC 3.12, [AppModel.visibleTabs]).
 */
enum class AppTab { TODAY, HISTORY, WEIGHT }

/** One sheet at a time, presented from the root, so one place can close it. */
sealed interface Sheet {
    data object Add : Sheet
    data class Day(val day: DayKey) : Sheet
    data class SetTime(val itemId: UUID) : Sheet
    data class EditItem(val itemId: UUID) : Sheet

    /** All weigh-ins, with its editor page (`WeightModel.editing`). */
    data object WeighIns : Sheet

    /** Set goal or Change goal, from the Weight tab's More options menu. */
    data object WeightGoal : Sheet
}

/** Navigation 3's back stack: the tabs, then Profile, then an item opened from Profile's Stack list. */
sealed interface Route {
    data object Main : Route
    data object Profile : Route
    data class ProfileItem(val itemId: UUID) : Route
}

/** What Undo on a toast puts back. */
sealed interface UndoStep {
    /** Remove doses that were just logged. */
    data class Remove(val ids: Set<UUID>) : UndoStep
    /** Put doses back exactly as they were: a removed dose, or a dose before its time was changed. */
    data class Restore(val doses: List<Dose>) : UndoStep

    /** A weigh-in just saved on the Weight tab: Undo removes it, and the point it lit. */
    data class RemoveWeighIn(val id: UUID) : UndoStep

    /** A weigh-in as it was before it was deleted or edited. */
    data class RestoreWeighIn(val weighIn: WeighIn) : UndoStep

    /** Bring the Weight tab back after Hide Weight tab. */
    data object ShowWeightTab : UndoStep

    /** The goal as it was before Clear goal, start included. */
    data class RestoreWeightGoal(val goal: com.tombaxter.taken.core.weight.WeightGoal) : UndoStep
}

/** The toast: a message, a time in Geist Mono after it, Undo, and the sentence TalkBack says for it. */
data class Toast(
    val id: Long,
    val message: String,
    val time: String? = null,
    val undo: UndoStep? = null,
    val spoken: String? = null,
)

/** A demo capture's Add sheet: chips already picked, how often each is taken, and text already typed (debug only). */
data class AddSeed(
    val selected: List<String> = emptyList(),
    val choices: Map<String, com.tombaxter.taken.core.catalog.FrequencyChoice> = emptyMap(),
    val query: String = "",
)

/** The haptics Taken plays (SPEC-ANDROID 6.2): CONFIRM for a take, a tick for choices, a soft key for undo and times. */
enum class Haptic { CONFIRM, TICK, SOFT }

/** Things the screen does for the model: a haptic, or a sentence for TalkBack. */
sealed interface Effect {
    data class Feel(val haptic: Haptic) : Effect
    data class Announce(val text: String) : Effect
}

enum class PaywallOrigin { INTRO, ACTION, BAR, SETTINGS, LINK }

/** The paywall was asked for; `pending` runs once Pro is on. */
class PaywallRequest(val origin: PaywallOrigin, val pending: (() -> Unit)?)

/**
 * The app's single source of screen state, mirroring the iPhone's Taken/AppModel.swift (with the tap-row change of
 * `feat/tap-row-to-log`). Every field the screens read is Compose snapshot state; every rule comes from :core. Writes go
 * through [write]: the screen updates at once, the file follows ([Persistence]), and the screen then ends on what the file
 * holds ([settle]).
 */
class AppModel(
    private val persistence: Persistence,
    initialState: StackState,
    initialLedger: ProLedger?,
    initialProfile: Profile,
    initialPhoto: ByteArray?,
    val pro: ProSource = ProSource.untilBilling,
    private val clockNow: () -> Instant = { Instant.now() },
    private val zone: () -> ZoneId = { ZoneId.systemDefault() },
    private val locale: () -> Locale = { Locale.getDefault() },
    val isDemo: Boolean = false,
    launchTab: AppTab = AppTab.TODAY,
    launchEditing: Boolean = false,
    demoPrompt: TodayPrompt? = null,
    /** Where the model's timed work runs (the intro paywall's 1.5 s, the wait for Play): the view model's scope. */
    internal val scope: CoroutineScope = MainScope(),
    /** The Weight tab's model (weights.json); tests and screens without one get an empty file in memory. */
    weightModel: WeightModel? = null,
) {
    /** The Weight tab (SPEC 3.12, SPEC-ANDROID 12): weights.json, off until the person turns the tab on. */
    val weight: WeightModel = weightModel ?: WeightModel(clockNow = clockNow, locale = locale, isDemo = isDemo)

    var state: StackState by mutableStateOf(initialState)
        private set
    var ledger: ProLedger? by mutableStateOf(initialLedger)
        private set
    var profile: Profile by mutableStateOf(initialProfile)
        private set
    /** The profile photo as JPEG bytes: the centre square, at most 600 px. */
    var photo: ByteArray? by mutableStateOf(initialPhoto)
        private set
    var now: Instant by mutableStateOf(clockNow())
        private set
    var engine: StackEngine by mutableStateOf(StackEngine(initialState, DayClock(initialState.settings.dayStartHour, zone())))
        private set
    var today: DaySummary by mutableStateOf(engine.todaySummary(now))
        private set
    var history: List<List<HistoryCell>> by mutableStateOf(emptyList())
        private set
    var streak: Int by mutableStateOf(0)
        private set
    var adherence: Adherence by mutableStateOf(Adherence(0, 0))
        private set
    /** Yesterday, while Today offers to fill it in (`TodayPrompts.repairDay`). */
    var repairDay: DayKey? by mutableStateOf(null)
        private set

    private var frontTab: AppTab by mutableStateOf(launchTab)

    /** The tab in front. Leaving Today ends its edit mode. */
    var tab: AppTab
        get() = frontTab
        set(value) {
            if (value != AppTab.TODAY && editingStack) editingStack = false
            // Leaving the Weight tab ends its visit: the line's sentence and the draft go (the iPhone's onDisappear).
            if (frontTab == AppTab.WEIGHT && value != AppTab.WEIGHT) weight.endVisit()
            frontTab = value
        }

    /** The tabs on the bar: Weight, last, only while it is on. */
    val visibleTabs: List<AppTab>
        get() = AppTab.entries.filter { it != AppTab.WEIGHT || weight.showsTab }

    private var shownSheet: Sheet? by mutableStateOf(null)

    /** The sheet in front. Closing it lets the intro paywall that waited for it come up. */
    var sheet: Sheet?
        get() = shownSheet
        set(value) {
            shownSheet = value
            if (value == null && introWaitsForSheet) {
                introWaitsForSheet = false
                scheduleIntro(INTRO_AFTER_SHEET_MS)
            }
        }

    var toast: Toast? by mutableStateOf(null)
        private set
    var expandedItemId: UUID? by mutableStateOf(null)
        private set

    /**
     * Today's stack is being edited (the pencil beside "+"): a tap on a row opens its item sheet instead of logging, and
     * Take all steps aside. It ends on the check, on leaving Today, when Taken goes to the background, when the stack
     * empties, and on system back (SPEC-ANDROID 7.2).
     */
    // The private setter takes another JVM name so it does not clash with setEditingStack below.
    @set:JvmName("assignEditingStack")
    var editingStack: Boolean by mutableStateOf(launchEditing)
        private set

    /**
     * How many doses a tap on each row has logged, by item: the row washes and its ring lifts each time its count goes up,
     * so the moment plays where the finger is and not for Take all, a widget or the nudge.
     */
    var rowLogs: Map<UUID, Int> by mutableStateOf(emptyMap())
        private set

    var paywall: PaywallRequest? by mutableStateOf(null)
        private set

    /** What the paywall was opened for, run once it has closed with Pro on. */
    private var afterPaywall: (() -> Unit)? = null
    private var introJob: Job? = null
    private var introWaitsForSheet = false

    // MARK: Seams for the Reminders and Widgets phases (SPEC-ANDROID 10, NEXT 3 and 4)

    /**
     * Pro itself changed (a purchase, a renewal seen, a cancellation, a refund): the widgets, the tile and the reminders
     * follow it. The integrator sets this to refresh widgets (`updateAll`), the tile and the alarms.
     */
    var onProChanged: () -> Unit = {}

    /**
     * A trial just started in the paywall, which has closed: the Reminders phase shows its one notification ask here
     * (`TrialAsk.shows`, SPEC-ANDROID 10.4) and plans the reminder (`trialReminderPlan`).
     */
    var onTrialStarted: () -> Unit = {}

    /**
     * Whether the trial reminder can reach the person as a notification (Reminders built and notifications allowed).
     * Until the Reminders phase sets it, Today carries the reminder's words instead, as the iPhone does while
     * notifications are off.
     */
    var trialReminderDeliverable: () -> Boolean = { false }

    /** Goes up each time a tap finishes the day (All taken), to play its check once. */
    var lockInCount: Int by mutableStateOf(0)
        private set

    /** Demo captures show a one-time row only when their screen asks for it. */
    private var demoPrompt: TodayPrompt? by mutableStateOf(demoPrompt)

    /** Navigation 3's back stack. */
    val backStack: SnapshotStateList<Route> = mutableStateListOf(Route.Main)

    /** The screen's side of a haptic or a TalkBack sentence. */
    var onEffect: (Effect) -> Unit = {}

    /** Demo captures only: what the Add sheet opens with. */
    var addSeed: AddSeed? = null

    private var toastCounter = 0L

    init {
        recomputeStats()
        pro.listen { proDidChange() }
        pro.adoptLedger(initialLedger)
        weight.onWriteFailed = { show(Toast(nextToastId(), com.tombaxter.taken.core.weight.WeightCopy.COULD_NOT_SAVE)) }
    }

    // MARK: Derived

    val clock: DayClock get() = engine.clock
    val settings: StackSettings get() = state.settings
    val theme: ThemeID get() = state.settings.theme
    val hapticsOn: Boolean get() = state.settings.hapticsEnabled
    val activeItems: List<Item> get() = engine.orderedItems.filter { !it.archived }
    val archivedItems: List<Item> get() = engine.orderedItems.filter { it.archived }
    val hasStack: Boolean get() = activeItems.isNotEmpty()

    /** Items Take all logs right now: pending, and not logged in the last hour. */
    val takeAllCount: Int get() = TodayRules.takeAllCount(engine, today, now)

    /** Whether a dose may be logged right now (PRO.md). The first session ends with the first dose ever. */
    val access: ProAccess
        get() = ProGate.access(
            status = pro.status, settled = pro.settled, legacyLog = false,
            hasLogged = ProGate.hasLogged(state, ledger), now = now,
        )

    /** Locked mode: the log stays readable, logging opens the paywall. */
    val isLocked: Boolean get() = access == ProAccess.LOCKED

    val lockedBarText: String get() = ProCopy.lockedBar(eligible = pro.introEligible, intro = pro.offers[ProPlan.YEARLY]?.intro)

    /** Cached Pro holds now. */
    val proActive: Boolean get() = pro.status?.isActive(now) == true

    /**
     * The price the current subscription renews at: the plan it renews to when Play named one, else its own plan, from
     * this launch's plans or the last ones Play gave (pro.json).
     */
    val renewalPrice: PlanPrice?
        get() {
            val status = pro.status ?: return null
            val plan = status.renewsTo ?: status.plan ?: return null
            if (!plan.isSubscription) return null
            return pro.offers[plan]?.let { PlanPrice.of(it) } ?: ledger?.prices?.get(plan.productId)
        }

    /**
     * The trial reminder that should exist now, for the Reminders phase to hand to its alarm (SPEC-ANDROID 10.4): its
     * moment and its words, or null. Taken Pro never posts it itself.
     */
    fun trialReminderPlan(at: Instant = clockNow()): TrialReminder.Plan? =
        TrialReminder.plan(pro.status, renewalPrice, state, at, clock.zone, ledger?.trialReminder)

    /** Today's line with the reminder's words, while notifications cannot carry it. */
    private val trialNotice: String?
        get() = if (trialReminderDeliverable()) null else TrialReminder.notice(pro.status, renewalPrice, state, now, clock.zone)

    /**
     * The one quiet row under Today's progress line, if any. In CORE no widget exists yet, so the widget invite waits
     * (the iPhone waits the same way until WidgetKit has answered); the trial notice and the weight offer come with their
     * phases. The nudge offer waits for Reminders (NEXT 3): until this build can post the nudge, Today never offers one.
     */
    val todayPrompt: TodayPrompt?
        get() {
            if (isDemo) return demoPrompt
            return TodayPrompts.pick(
                settings = settings, hasStack = hasStack, today = today, repairDay = repairDay, locked = isLocked,
                widgetPlaced = true, trialNotice = trialNotice,
                // The Weight tab's one-time offer comes last, after every other row (SPEC 3.12).
                weightOffer = WeightOffer.shows(weight.state, state, today, clock), nudgeAvailable = NUDGE_AVAILABLE,
            )
        }

    fun nextLabel(row: ItemDay): String = TodayRules.nextLabel(engine, row.item, today.day)

    fun notTodayRow(row: ItemDay): TodayRules.NotTodayRow = TodayRules.notTodayRow(engine, row, today.day)

    fun sheetSummary(day: DayKey): DaySummary = engine.sheetSummary(day, asOf = today.day)

    fun setTimeDose(item: Item): Dose? = TodayRules.setTimeDose(state, item, today.day, clock)

    fun offersSetTime(row: ItemDay): Boolean = TodayRules.offersSetTime(row, today.day, clock)

    fun item(id: UUID): Item? = state.items.firstOrNull { it.id == id }

    /** taken-log.csv for the stack as it is now, built when called: the export builds it off the main thread. */
    fun csvExport(): () -> String {
        val snapshot = state
        val zone = clock.zone
        return { CsvExport.make(snapshot, zone) }
    }

    /** "7:42 AM" in this phone's language, for TalkBack. */
    fun spoken(instant: Instant): String = Fmt.spokenTime(instant, clock.zone, locale())

    // MARK: Lifecycle

    /** The 20 s ticker: keeps `now` and Today current, and the stats when the day changes. */
    fun tick() {
        val fresh = clockNow()
        val dayChanged = clock.day(fresh) != today.day || clock.zone != zone()
        now = fresh
        if (clock.zone != zone()) {
            apply(state)
            return
        }
        today = engine.todaySummary(fresh)
        if (dayChanged) recomputeStats()
    }

    /**
     * Taken came to the front (`ON_START`): rebuild, since the time zone or the day may have changed while away; offer a
     * log a widget, the tile or a nudge was refused while locked; and the one intro paywall, if a first dose logged
     * elsewhere has not had it yet.
     */
    fun didBecomeActive() {
        apply(state)
        if (isDemo) return
        consumePendingLog()
        if (state.doses.isNotEmpty() && !introShown) scheduleIntro()
    }

    /** Taken went to the background (`ON_STOP`): the stack's edit mode ends, so the next open is a tap that logs again. */
    fun didEnterBackground() {
        if (editingStack) editingStack = false
        // The Weight tab's visit ends when Taken leaves the foreground, as on the iPhone.
        weight.endVisit()
    }

    /** The file changed under the screen (a later surface wrote it). Adopted only when no write of ours is on its way. */
    fun adopt(fresh: StackState) {
        if (persistence.busy || fresh == state) return
        apply(fresh)
    }

    fun adoptLedger(fresh: ProLedger?) {
        ledger = fresh
        pro.adoptLedger(fresh)
    }

    /** pro.json's small writes: the screen's copy at once, the file after. */
    private fun updateLedger(transform: (ProLedger?) -> ProLedger?) {
        ledger = transform(ledger)
        if (!isDemo) persistence.updateLedger(transform)
    }

    private fun apply(fresh: StackState) {
        state = fresh
        now = clockNow()
        engine = StackEngine(fresh, DayClock(fresh.settings.dayStartHour, zone()))
        today = engine.todaySummary(now)
        recomputeStats()
        // The last item archived or deleted: Today shows first run, with nothing left to edit.
        if (editingStack && !hasStack) editingStack = false
    }

    private fun recomputeStats() {
        history = engine.history(today.day)
        streak = engine.streak(today.day)
        adherence = engine.adherence(today.day)
        repairDay = TodayPrompts.repairDay(engine, today.day)
    }

    /**
     * Every write goes through here: the screen at once, then the file. A body that makes something new (a dose, an item)
     * takes ids made before it runs, so a replay onto a file that moved on stores the ids the screen and its Undo hold.
     */
    private fun <T> write(body: (StackState) -> T): T {
        val base = state
        val next = base.clone()
        val value = body(next)
        apply(next)
        persistence.saveStack(base, next, { body(it) }, settled = ::settle) {
            show(Toast(nextToastId(), "Could not save. Try again."))
        }
        return value
    }

    /**
     * Every write of the app's is done (saved or failed): the screen ends on exactly what the file holds. After a failed
     * save that puts back what was there, so a dose that was not saved never shows as taken and a tap logs it again, as
     * on the iPhone, where a write that fails never reaches the screen. The first dose ever is noted in pro.json once it
     * is on disk (the iPhone notes it as it applies a saved state).
     */
    private fun settle(onDisk: StackState) {
        if (onDisk != state) apply(onDisk)
        val current = ledger ?: return
        if (current.firstDoseAt == null && onDisk.doses.isNotEmpty()) {
            val at = onDisk.doses.minOf { it.takenAt }
            ledger = ProLedgers.noteFirstDose(current, at)
            persistence.updateLedger { ProLedgers.noteFirstDose(it, at) }
            // The first dose ever: the moment Taken makes sense. The paywall follows it once (PRO.md).
            scheduleIntro()
        }
    }

    // MARK: Tabs and routes

    /** A `taken://` link (SPEC-ANDROID 10.3): today closes whatever is open; pro opens the paywall. */
    fun handle(url: String) {
        if (!url.startsWith("taken://")) return
        val route = ProRoute.parse(url)
        if (route == null) {
            sheet = null
            val host = url.removePrefix("taken://").substringBefore('?').substringBefore('/')
            if (host == "today" || host == "weight") {
                while (backStack.size > 1) backStack.removeAt(backStack.lastIndex)
                // taken://weight: the Weight tab, or Today while it is off.
                if (host == "weight") openWeightTab() else tab = AppTab.TODAY
            }
            return
        }
        // A locked widget or tile sends `taken://pro`, with the log it was asked for: the paywall, and the log once Pro
        // is on. If Pro is on by now (Play answered since), the log simply happens.
        val pending = route.then?.let { PendingLog(it, clockNow()) }
        when (access) {
            ProAccess.PRO, ProAccess.FIRST_SESSION, ProAccess.PENDING -> pending?.let(::applyPending)
            ProAccess.LOCKED -> presentPaywall(PaywallOrigin.LINK, pending?.let { log -> { applyPending(log) } })
            ProAccess.CHECKING -> scope.launch {
                pro.settle()
                handle(url)
            }
        }
    }

    /** The avatar: Profile, as a full screen with Up and back (SPEC-ANDROID 6.3). */
    fun openProfile() {
        if (backStack.lastOrNull() != Route.Profile) backStack.add(Route.Profile)
    }

    fun openProfileItem(id: UUID) {
        backStack.add(Route.ProfileItem(id))
    }

    /** Up and system back on a pushed screen. */
    fun back() {
        if (backStack.size > 1) backStack.removeAt(backStack.lastIndex)
    }

    /**
     * System back on the tabs, in the spec's order (SPEC-ANDROID 6.2): edit mode ends, then History returns to Today.
     * False when back should leave the app (Today is the start destination).
     */
    fun backOnTabs(): Boolean {
        if (editingStack) {
            setEditingStack(false)
            return true
        }
        if (tab != AppTab.TODAY) {
            tab = AppTab.TODAY
            return true
        }
        return false
    }

    // MARK: Taken Pro

    /** The one automatic paywall after the first dose has been shown. */
    val introShown: Boolean get() = ledger?.introShownAt != null

    /**
     * Runs `action` while logging is open; otherwise opens the paywall and runs it once Pro is on. While Play's first
     * answer of this launch is on its way (at most 4 s) it waits for it, so a payer never sees a lock flash.
     */
    fun requirePro(action: () -> Unit) {
        when (access) {
            ProAccess.PRO, ProAccess.FIRST_SESSION, ProAccess.PENDING -> action()
            ProAccess.LOCKED -> presentPaywall(PaywallOrigin.ACTION, action)
            ProAccess.CHECKING -> scope.launch {
                pro.settle()
                requirePro(action)
            }
        }
    }

    /**
     * `keepSheet`: the paywall comes over the sheet in use (All weigh-ins asking to edit a weigh-in), as the iPhone
     * presents it over the sheet's level, so the sheet is still there once it closes.
     */
    fun presentPaywall(origin: PaywallOrigin, pending: (() -> Unit)? = null, keepSheet: Boolean = false) {
        if (paywall != null) return
        // Any paywall counts as the one after the first dose, so it never comes up on its own a second time. Plans looked
        // at from Profile before anything was logged do not: the first dose still brings it up once.
        if (origin != PaywallOrigin.SETTINGS || state.doses.isNotEmpty()) {
            val at = clockNow()
            if (!introShown) updateLedger { ProLedgers.markIntroShown(it, at) }
        }
        if ((origin == PaywallOrigin.ACTION || origin == PaywallOrigin.LINK) && !keepSheet) sheet = null
        afterPaywall = null
        paywall = PaywallRequest(origin, pending)
        // Prices, periods and the trial are read from Play each time the paywall opens (SPEC-ANDROID 9.3).
        scope.launch { pro.loadOffers(force = pro.offersPhase == OffersPhase.FAILED) }
    }

    /** Pro just came on in the paywall: what opened it runs once it has closed, and a trial gets its ask after it. */
    fun paywallUnlocked(trialStarted: Boolean) {
        afterPaywall = paywall?.pending
        if (trialStarted) trialAskDue = true
    }

    private var trialAskDue = false

    /** The paywall closed: with Pro on, the tap that opened it runs now. */
    fun closePaywall() {
        paywall = null
        val action = afterPaywall
        afterPaywall = null
        if (trialAskDue) {
            trialAskDue = false
            onTrialStarted()
        }
        if (action != null && access.allowsLogging) action()
    }

    /** About 1.5 s after the first dose the paywall slides up, once, never over a sheet in use (PRO.md). */
    private fun scheduleIntro(delayMillis: Long = INTRO_DELAY_MS) {
        if (isDemo || introShown || introJob != null) return
        introJob = scope.launch {
            delay(delayMillis)
            pro.settle()
            introJob = null
            showIntroIfDue()
        }
    }

    private fun showIntroIfDue() {
        if (introShown || paywall != null || access != ProAccess.LOCKED) return
        if (sheet != null) {
            introWaitsForSheet = true
            return
        }
        presentPaywall(PaywallOrigin.INTRO)
    }

    /** A log a widget, the tile or a nudge could not make while locked, offered now Taken is open (10 minutes). */
    private fun consumePendingLog() {
        if (ledger?.pending == null) return
        val (_, pending) = ProLedgers.takePending(ledger, PENDING_LOG_MAX_AGE, clockNow())
        updateLedger { ProLedgers.takePending(it, PENDING_LOG_MAX_AGE, clockNow()).first }
        if (pending == null) return
        scope.launch {
            pro.refresh()
            requirePro { applyPending(pending) }
        }
    }

    /** Logs what was asked for, at the time it was asked for. */
    private fun applyPending(pending: PendingLog) {
        when (val action = pending.action) {
            ProPendingAction.TakeAll -> takeAll(pending.at)
            is ProPendingAction.Log -> logIfPending(action.itemId, pending.at)
        }
    }

    /** A widget row's log, refused while locked and offered again: only while that dose is still pending. */
    private fun logIfPending(itemId: UUID, at: Instant) {
        val wasAllTaken = today.allTaken
        val clock = this.clock
        val id = UUID.randomUUID()
        val dose = write { it.logNextDoseIfPending(itemId, at, clock, id) } ?: return
        val item = item(dose.itemId) ?: return
        afterTake(wasAllTaken)
        show(Toast(nextToastId(), "${item.name} taken at", Fmt.clock(at, clock), UndoStep.Remove(setOf(dose.id)), "${item.name} taken at ${spoken(at)}."))
    }

    private fun proDidChange() {
        if (isDemo) return
        onProChanged()
    }

    /** Profile's Manage subscription: Play's subscription center, at the subscription held (SPEC-ANDROID 9.5). */
    val manageSubscriptionUrl: String
        get() = PlayEntitlement.manageUrl(pro.heldSubscription?.productId, PLAY_PACKAGE)

    // MARK: Editing the stack

    /** The pencil and the check beside the Stack title. Editing closes any row's times, so every row shows its chevron. */
    fun setEditingStack(editing: Boolean) {
        if (editing == editingStack) return
        editingStack = editing
        if (editing) expandedItemId = null
    }

    // MARK: Taking

    /**
     * A tap anywhere on a row: pending logs a dose, taken shows the times. Never un-takes. While the stack is being
     * edited a tap opens the item sheet and never logs.
     */
    fun tap(row: ItemDay) {
        when (TodayRules.tap(row, editingStack)) {
            TodayRules.Tap.OPEN_ITEM -> sheet = Sheet.EditItem(row.item.id)
            TodayRules.Tap.LOG -> {
                val item = row.item
                requirePro {
                    if (log(item)) rowLogs = rowLogs + (item.id to (rowLogs[item.id] ?: 0) + 1)
                }
            }
            TodayRules.Tap.SHOW_TIMES -> {
                feel(Haptic.SOFT)
                expandedItemId = if (expandedItemId == row.item.id) null else row.item.id
            }
        }
    }

    /** Logs a dose now (or at `time`), with the haptic and the toast. False when nothing was written. */
    fun log(item: Item, at: Instant? = null): Boolean {
        val time = at ?: clockNow()
        val wasAllTaken = today.allTaken
        val made = doseAt(item.id, time, clock.zone)
        val dose = write { it.insertDose(made) } ?: return false
        afterTake(wasAllTaken)
        val spokenLine = "${item.name} taken at ${spoken(time)}."
        show(Toast(nextToastId(), "${item.name} taken at", Fmt.clock(time, clock), UndoStep.Remove(setOf(dose.id)), spokenLine))
        return true
    }

    /** Take all: one dose for every quick-loggable pending row, at one moment. Undo removes them all. */
    fun takeAll(at: Instant? = null) {
        val time = at ?: clockNow()
        val wasAllTaken = today.allTaken
        val clock = this.clock
        // One id per item, made once: a replay of this write logs the same doses the toast's Undo removes.
        val ids = ConcurrentHashMap<UUID, UUID>()
        val logged = write { it.takeAllPending(time, clock) { item -> ids.getOrPut(item) { UUID.randomUUID() } } }
        if (logged.isEmpty()) return
        afterTake(wasAllTaken)
        val spokenLine = "${logged.size} taken at ${spoken(time)}."
        show(Toast(nextToastId(), "${logged.size} taken at", Fmt.clock(time, clock), UndoStep.Remove(logged.map { it.id }.toSet()), spokenLine))
    }

    private fun afterTake(wasAllTaken: Boolean) {
        if (!wasAllTaken && today.allTaken) lockInCount += 1
        feel(Haptic.CONFIRM)
    }

    fun undo(toast: Toast) {
        when (val step = toast.undo ?: return) {
            is UndoStep.Remove -> write { it.removeDoses(step.ids) }
            is UndoStep.Restore -> write { s -> step.doses.forEach { s.restore(it) } }
            is UndoStep.RemoveWeighIn, is UndoStep.RestoreWeighIn, UndoStep.ShowWeightTab, is UndoStep.RestoreWeightGoal ->
                undoWeight(step)
        }
        feel(Haptic.SOFT)
        dismissToast(toast)
        announce("Undone.")
    }

    /**
     * Removes the row's latest dose: today's on a Stack row, and on a weekly row the one that counts for its week. The
     * toast's Undo puts it back with its original time.
     */
    fun undoLastDose(row: ItemDay) {
        val last = row.lastDose ?: return
        write { it.removeDoses(setOf(last.id)) }
        feel(Haptic.SOFT)
        show(Toast(nextToastId(), "${row.item.name}: last dose removed", undo = UndoStep.Restore(listOf(last)), spoken = "${row.item.name}, last dose removed."))
    }

    /** The moment a wall-clock time means on a logical day, and whether it is still to come. */
    fun moment(day: DayKey, minutes: Int): Pair<Instant, Boolean> {
        val date = clock.date(day, minutes / 60, minutes % 60)
        return date to (date > clockNow())
    }

    /** Set time: corrects today's latest dose, or logs one at that time. A time still to come is never used. */
    fun setTime(item: Item, hour: Int, minute: Int) {
        val (at, isFuture) = moment(today.day, hour * 60 + minute)
        if (isFuture) return
        val zone = clock.zone
        val existing = setTimeDose(item)
        val wasAllTaken = today.allTaken
        if (existing != null) {
            write { it.setDoseTime(existing.id, at, zone) }
            feel(Haptic.CONFIRM)
            show(Toast(nextToastId(), "${item.name} set to", Fmt.clock(at, clock), UndoStep.Restore(listOf(existing)), "${item.name} set to ${spoken(at)}."))
        } else {
            val made = doseAt(item.id, at, zone)
            val dose = write { it.insertDose(made) } ?: return
            afterTake(wasAllTaken)
            show(Toast(nextToastId(), "${item.name} taken at", Fmt.clock(at, clock), UndoStep.Remove(setOf(dose.id)), "${item.name} taken at ${spoken(at)}."))
        }
    }

    // MARK: Backfill (day sheet)

    /** Logs a dose at a time on a day. A time still to come is never used (the sheet disables it). */
    fun logDose(item: Item, day: DayKey, minutes: Int) {
        val (at, isFuture) = moment(day, minutes)
        if (isFuture) return
        val made = doseAt(item.id, at, clock.zone)
        write { it.insertDose(made) } ?: return
        feel(Haptic.CONFIRM)
        announce("${item.name} logged at ${spoken(at)}.")
    }

    fun removeDose(dose: Dose) {
        write { it.removeDoses(setOf(dose.id)) }
        feel(Haptic.SOFT)
    }

    // MARK: Stack editing

    fun addItems(drafts: List<ItemDraft>) {
        val at = clockNow()
        val ids = drafts.map { UUID.randomUUID() }
        val added = write { it.addItems(drafts, at) { index -> ids[index] } }
        if (added.isEmpty()) return
        feel(Haptic.CONFIRM)
        show(Toast(nextToastId(), if (added.size == 1) "${added[0].name} added" else "${added.size} added to your stack"))
    }

    fun updateItem(id: UUID, name: String, code: String, frequency: Frequency, archived: Boolean) {
        val at = clockNow()
        write { s ->
            s.updateItem(id, name, code, frequency, at)
            s.setArchived(id, archived, at)
        }
    }

    /** The item sheet's save rule: an empty name keeps the old one; a new name takes its code; nothing when unchanged. */
    fun saveItem(id: UUID, typedName: String, frequency: Frequency, archived: Boolean) {
        val item = item(id) ?: return
        val clean = typedName.trim()
        val newName = clean.ifEmpty { item.name }
        val code = if (newName == item.name) item.code else Catalog.code(newName)
        val changed = newName != item.name || frequency != item.frequency || archived != item.archived
        if (!changed) return
        updateItem(id, newName, code, frequency, archived)
    }

    fun deleteItem(id: UUID) {
        write { it.deleteItem(id) }
        if (expandedItemId == id) expandedItemId = null
    }

    /** Profile's reorder, as SwiftUI's onMove describes it. */
    fun moveItems(from: Set<Int>, to: Int) {
        write { it.moveActiveItems(from, to) }
    }

    // MARK: One-time rows

    /**
     * Turn on or Not now on the evening nudge offer. Either answer is kept, so the row never comes back. Until Reminders
     * (NEXT 3) the offer shows only in demo captures ([NUDGE_AVAILABLE]); with Reminders, Turn on asks for
     * POST_NOTIFICATIONS first and keeps `reminderEnabled` only once it is granted, as the iPhone's setReminderEnabled does.
     */
    fun answerNudgeOffer(turnOn: Boolean) {
        if (isDemo) demoPrompt = null
        if (!turnOn) {
            write { it.settings.nudgeOfferDone = true }
            return
        }
        requirePro {
            write { it.settings.setReminder(true) }
            show(Toast(nextToastId(), RetentionCopy.NUDGE_ON, Fmt.minutes(settings.reminderMinutes)))
        }
    }

    /**
     * Add tab or Not now on Today's weight offer (SPEC 3.12). Either answer is final, and Add tab turns the tab on without
     * switching to it.
     */
    fun answerWeightOffer(addTab: Boolean) {
        if (isDemo) demoPrompt = null
        weight.answerOffer(addTab)
        if (addTab) {
            feel(Haptic.TICK)
            announce(com.tombaxter.taken.core.weight.WeightCopy.TAB_ADDED)
        }
    }

    /** The repair line's close: hidden for the day it was about. It never says the streak broke. */
    fun closeRepair(day: DayKey) {
        if (isDemo) {
            demoPrompt = null
            return
        }
        write { it.settings.repairClosedDay = day.ordinal }
    }

    // MARK: Settings

    /** Profile > Wake-up time: the day rolls over 4 hours before it, so every view follows at once. */
    fun setWakeMinutes(minutes: Int) {
        write { it.settings.wakeMinutes = StackSettings.clampMinutes(minutes) }
    }

    fun setHaptics(enabled: Boolean) {
        write { it.settings.hapticsEnabled = enabled }
        if (enabled) onEffect(Effect.Feel(Haptic.TICK))
    }

    /** One tap in Profile > Look. The app recolours at once. */
    fun setLook(look: ThemeID) {
        if (look == theme) return
        feel(Haptic.TICK)
        write { it.settings.theme = look }
    }

    // MARK: Profile

    fun setProfileName(name: String) {
        val next = Profile(Profile.clean(name))
        if (next == profile) return
        profile = next
        if (!isDemo) persistence.saveProfile(next)
    }

    /** A photo from the photo picker, already the centre square at most 600 px as JPEG. */
    fun setProfilePhoto(jpeg: ByteArray) {
        photo = jpeg
        if (!isDemo) persistence.savePhoto(jpeg)
    }

    fun removeProfilePhoto() {
        photo = null
        if (!isDemo) persistence.savePhoto(null)
    }

    /**
     * Erase all data: the stack, every dose, the settings, the profile and any unreadable copy set aside. The look stays,
     * and so does pro.json.
     */
    fun eraseAll() {
        write { it.eraseAll() }
        weight.eraseAll()
        persistence.eraseExtras()
        profile = Profile()
        photo = null
        expandedItemId = null
        if (editingStack) editingStack = false
    }

    // MARK: Toast and feedback

    internal fun nextToastId(): Long {
        toastCounter += 1
        return toastCounter
    }

    fun show(next: Toast) {
        toast = next
    }

    /** The toast went: timed out, swiped away, or replaced. */
    fun dismissToast(which: Toast? = null) {
        if (which == null || toast?.id == which.id) toast = null
    }

    internal fun feel(haptic: Haptic) {
        if (hapticsOn) onEffect(Effect.Feel(haptic))
    }

    internal fun announce(text: String) {
        onEffect(Effect.Announce(text))
    }

    /** A haptic for a screen of its own (the paywall's plans and its success), under Profile's Haptics switch. */
    fun feedback(haptic: Haptic) = feel(haptic)

    /** A sentence for TalkBack from a screen of its own ("Taken Pro is on."). */
    fun say(text: String) = announce(text)

    companion object {
        /** This build can post the evening nudge. False until Reminders (NEXT 3), so Today never offers it before then. */
        const val NUDGE_AVAILABLE = false

        /** The package Play knows: debug builds add `.debug`, which Play sells nothing to. */
        const val PLAY_PACKAGE = "com.tombaxter.taken"

        /** The intro paywall, after the first dose (PRO.md: about 1.5 s). */
        const val INTRO_DELAY_MS = 1_500L
        const val INTRO_AFTER_SHEET_MS = 500L

        /** A refused log is offered again for 10 minutes (the iPhone's `takePendingLog(maxAge:)`). */
        val PENDING_LOG_MAX_AGE: java.time.Duration = java.time.Duration.ofMinutes(10)

        /** Erase all data's dialog, said before it acts (Android wording, SPEC-ANDROID 6.4). */
        const val ERASE_MESSAGE =
            "This removes your stack, every logged dose, all your to-dos, your weigh-ins, your weight goal and your profile from this phone. It cannot be undone."
    }
}
