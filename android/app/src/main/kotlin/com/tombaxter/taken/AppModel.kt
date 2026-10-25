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
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProLedgers
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProRoute
import com.tombaxter.taken.core.pro.ProStatus
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
import com.tombaxter.taken.core.stack.moveActiveItems
import com.tombaxter.taken.core.stack.removeDoses
import com.tombaxter.taken.core.stack.restore
import com.tombaxter.taken.core.stack.setArchived
import com.tombaxter.taken.core.stack.setDoseTime
import com.tombaxter.taken.core.stack.takeAllPending
import com.tombaxter.taken.core.stack.updateItem
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.core.todo.TodoCapture
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.data.MemoryTodoPersistence
import com.tombaxter.taken.data.Persistence
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * The tabs (SPEC-ANDROID 6.2), in the iPhone's order: Today, To-do, History. Weight joins last with its phase (NEXT 6),
 * only while it is on.
 */
enum class AppTab { TODAY, TODO, HISTORY }

/** One sheet at a time, presented from the root, so one place can close it. */
sealed interface Sheet {
    data object Add : Sheet
    data class Day(val day: DayKey) : Sheet
    data class SetTime(val itemId: UUID) : Sheet
    data class EditItem(val itemId: UUID) : Sheet

    /** A to-do's words and when it is due (SPEC 3.10). */
    data class TodoEdit(val taskId: UUID) : Sheet

    /** Typing instead of talking: the same save onto the one list. */
    data object TodoType : Sheet
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
 * Where Taken Pro's answer comes from. Google Play Billing arrives with NEXT 2 (SPEC-ANDROID 17); until then the app
 * uses [ProSource.untilBilling], so a CORE build never locks anyone out, and tests use a locked source to drive locked
 * mode through the real gate.
 */
interface ProSource {
    val status: ProStatus?
    val settled: Boolean
    /** The yearly trial is still open to this person (null until the store says). */
    val introEligible: Boolean?

    companion object {
        /** No store yet: the gate reads Pro as on, for good, so logging is never locked before Billing exists. */
        val untilBilling: ProSource = fixed(ProStatus(isPro = true, reason = ProReason.NONE, checkedAt = Instant.EPOCH))

        /** No Pro, the store has answered: locked mode after the first dose. */
        val locked: ProSource = fixed(null)

        fun fixed(status: ProStatus?, eligible: Boolean? = true): ProSource = object : ProSource {
            override val status = status
            override val settled = true
            override val introEligible = eligible
        }
    }
}

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
    /** The To-do tab's model (todos.json); tests and screens without one get an empty list in memory. */
    todoModel: TodoModel? = null,
) {
    /** The To-do tab: the one list, the mic and its sheets. */
    val todo: TodoModel = todoModel ?: TodoModel(
        MemoryTodoPersistence(), TodoState(), clockNow = clockNow, zone = zone, locale = locale, isDemo = isDemo,
    )

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

    /** The tab in front. Leaving Today ends its edit mode; leaving To-do takes Keep as one away. */
    var tab: AppTab
        get() = frontTab
        set(value) {
            if (value != AppTab.TODAY && editingStack) editingStack = false
            if (frontTab == AppTab.TODO && value != AppTab.TODO) todo.dismissKeepOffer()
            frontTab = value
        }

    var sheet: Sheet? by mutableStateOf(null)
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
        todo.attach(this)
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

    val lockedBarText: String get() = ProCopy.lockedBar(eligible = pro.introEligible, intro = null)

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
                widgetPlaced = true, trialNotice = null, weightOffer = false, nudgeAvailable = NUDGE_AVAILABLE,
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

    /** Taken came to the front (`ON_START`): rebuild, since the time zone or the day may have changed while away. */
    fun didBecomeActive() {
        apply(state)
        todo.didBecomeActive()
    }

    /** Taken went to the background (`ON_STOP`): the stack's edit mode ends, so the next open is a tap that logs again. */
    fun didEnterBackground() {
        if (editingStack) editingStack = false
        todo.didEnterBackground()
    }

    /** The file changed under the screen (a later surface wrote it). Adopted only when no write of ours is on its way. */
    fun adopt(fresh: StackState) {
        if (persistence.busy || fresh == state) return
        apply(fresh)
    }

    fun adoptLedger(fresh: ProLedger?) {
        ledger = fresh
    }

    private fun apply(fresh: StackState) {
        state = fresh
        now = clockNow()
        engine = StackEngine(fresh, DayClock(fresh.settings.dayStartHour, zone()))
        today = engine.todaySummary(now)
        recomputeStats()
        // The last item archived or deleted: Today shows first run, with nothing left to edit.
        if (editingStack && !hasStack) editingStack = false
        // The To-do tab follows the wake-up time and the haptics switch.
        todo.refresh()
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
        }
    }

    // MARK: Tabs and routes

    /**
     * A `taken://` link (SPEC-ANDROID 10.3): today closes whatever is open; todo brings To-do to the front, and
     * todo/record starts listening there; pro opens the paywall.
     */
    fun handle(url: String) {
        if (!url.startsWith("taken://")) return
        val todoRoute = TodoCaptureRoute.route(url)
        if (todoRoute != null) {
            openTodoTab()
            if (todoRoute == TodoCaptureRoute.Route.RECORD) todo.requestRecording()
            return
        }
        val route = ProRoute.parse(url)
        if (route == null) {
            sheet = null
            if (url.removePrefix("taken://").substringBefore('?').substringBefore('/') == "today") {
                while (backStack.size > 1) backStack.removeAt(backStack.lastIndex)
                tab = AppTab.TODAY
            }
            return
        }
        if (!access.allowsLogging) presentPaywall(PaywallOrigin.LINK)
    }

    /**
     * A voice to-do request closes any sheet and Profile and brings To-do to the front (the iPhone's
     * `AppModel.openTodoTab`); a recording it asked for starts once the tab is uncovered.
     */
    fun openTodoTab() {
        sheet = null
        while (backStack.size > 1) backStack.removeAt(backStack.lastIndex)
        tab = AppTab.TODO
    }

    /** To-do is in front with nothing over it: Listening and the stop button are on screen when the mic opens. */
    val showsTodoTabUncovered: Boolean
        get() = tab == AppTab.TODO && sheet == null && paywall == null && backStack.size == 1 && !todo.askingMicrophone

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
     * System back on the tabs, in the spec's order (SPEC-ANDROID 6.2): edit mode ends, then listening stops (keeping the
     * words, as a tap on the mic would), then To-do or History returns to Today. False when back should leave the app
     * (Today is the start destination).
     */
    fun backOnTabs(): Boolean {
        if (editingStack) {
            setEditingStack(false)
            return true
        }
        if (todo.phase == TodoCapture.Phase.LISTENING) {
            todo.micTapped()
            return true
        }
        if (tab != AppTab.TODAY) {
            tab = AppTab.TODAY
            return true
        }
        return false
    }

    // MARK: Taken Pro

    /** Runs `action` while logging is open; otherwise opens the paywall and runs it once Pro is on. */
    fun requirePro(action: () -> Unit) {
        if (access.allowsLogging) action() else presentPaywall(PaywallOrigin.ACTION, action)
    }

    fun presentPaywall(origin: PaywallOrigin, pending: (() -> Unit)? = null) {
        if (paywall != null) return
        if (origin == PaywallOrigin.ACTION || origin == PaywallOrigin.LINK) sheet = null
        paywall = PaywallRequest(origin, pending)
    }

    fun closePaywall() {
        paywall = null
    }

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
     * Erase all data: the stack, every dose, the settings, the to-dos, the profile and any unreadable copy set aside. The
     * look stays, and so do pro.json and the to-dos' first note on the house.
     */
    fun eraseAll() {
        write { it.eraseAll() }
        todo.eraseAll()
        persistence.eraseExtras()
        profile = Profile()
        photo = null
        expandedItemId = null
        if (editingStack) editingStack = false
    }

    // MARK: Toast and feedback

    private fun nextToastId(): Long {
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

    private fun feel(haptic: Haptic) {
        if (hapticsOn) onEffect(Effect.Feel(haptic))
    }

    private fun announce(text: String) {
        onEffect(Effect.Announce(text))
    }

    companion object {
        /** This build can post the evening nudge. False until Reminders (NEXT 3), so Today never offers it before then. */
        const val NUDGE_AVAILABLE = false

        /** Erase all data's dialog, said before it acts (Android wording, SPEC-ANDROID 6.4). */
        const val ERASE_MESSAGE =
            "This removes your stack, every logged dose, all your to-dos, your weigh-ins, your weight goal and your profile from this phone. It cannot be undone."
    }
}
