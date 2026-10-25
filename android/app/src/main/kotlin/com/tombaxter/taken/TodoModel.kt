package com.tombaxter.taken

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.demo.TodoDemo
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.todo.ChunkSorting
import com.tombaxter.taken.core.todo.FallbackSorter
import com.tombaxter.taken.core.todo.NoteSorter
import com.tombaxter.taken.core.todo.TodoCapture
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.core.todo.TodoContext
import com.tombaxter.taken.core.todo.TodoCopy
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoGate
import com.tombaxter.taken.core.todo.TodoMerge
import com.tombaxter.taken.core.todo.TodoNotificationScheduler
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoStopReason
import com.tombaxter.taken.core.todo.TodoTask
import com.tombaxter.taken.core.todo.TodoText
import com.tombaxter.taken.core.todo.TodoValidation
import com.tombaxter.taken.core.todo.TranscriptionVocabulary
import com.tombaxter.taken.core.todo.Words
import com.tombaxter.taken.data.TodoPersistence
import com.tombaxter.taken.voice.VoiceCapture
import com.tombaxter.taken.voice.VoiceHost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/**
 * The To-do tab (SPEC 3.10, SPEC-ANDROID 11), ported from Taken/Todo/TodoModel.swift: one tap starts listening, the words
 * show as they are said, a second tap finishes (30 s of quiet or 5 minutes stop it too), and the note lands on the one
 * list. Android 1.0 has no on-device model ([FallbackSorter]), so every note is saved as said, one line per sentence, and
 * says so; the whole pipeline still runs ([NoteSorter], [TodoValidation.assemble], Keep as one) so a model can come later
 * behind [ChunkSorting] with no new rules.
 *
 * Every field the screen reads is Compose snapshot state, as AppModel's are. Writes go through [write]: the screen at
 * once, the file after ([TodoPersistence]), and the screen ends on what the file holds. The microphone comes through
 * [host] ([VoiceHost]: RECORD_AUDIO, Android's prompt, the on-device recognizer), so the rules run in tests with a fake.
 */
class TodoModel(
    private val persistence: TodoPersistence,
    initialState: TodoState,
    private val clockNow: () -> Instant = { Instant.now() },
    private val zone: () -> ZoneId = { ZoneId.systemDefault() },
    private val locale: () -> Locale = { Locale.getDefault() },
    val isDemo: Boolean = false,
    /** What sorts each note: Android 1.0 has no on-device model (SPEC-ANDROID 11), tests give canned answers. */
    private val makeSorter: () -> ChunkSorting = { FallbackSorter() },
    private val budget: NoteSorter.Budget = NoteSorter.Budget.STANDARD,
    /**
     * The due-time notifications' seam (SPEC-ANDROID 10.4, the Reminders step): every write that changed a task and
     * every return to the front hand the tasks to it, one rebuild at a time, the newest winning. Until that step it posts
     * nothing ([TodoNotificationScheduler.none]).
     */
    private val notifications: TodoNotificationScheduler = TodoNotificationScheduler.none,
    scope: CoroutineScope? = null,
) {
    /** Why voice capture cannot run right now: the blocker card. */
    enum class Blocker {
        /** RECORD_AUDIO was denied. */
        MICROPHONE,

        /** No on-device speech recognition for the phone's language (or below Android 12). */
        UNAVAILABLE,

        /** Android 13 and later: the phone's language is being downloaded for next time. */
        DOWNLOADING,
    }

    /** A note split into several to-dos, offered back as one ("Keep as one"). */
    data class KeepOffer(val noteId: UUID, val ids: List<UUID>, val transcript: String)

    /** After the stop, the part of a long note being sorted: "part 2 of 5". */
    data class SortingProgress(val part: Int, val of: Int)

    private val givenScope = scope

    /** The app's main-thread scope: a note being saved outlives the activity (a rotation, a trip home). */
    private val scope: CoroutineScope by lazy { givenScope ?: CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }

    var state: TodoState by mutableStateOf(initialState)
        private set
    var phase: TodoCapture.Phase by mutableStateOf(TodoCapture.Phase.IDLE)
        private set

    /** What has been heard so far. */
    var transcript: String by mutableStateOf("")
        private set

    /** The latest input level from 0 to 1, for the ring around the stop button. */
    var level: Double by mutableDoubleStateOf(0.0)
        private set

    /** A one-line note under the list ("Nothing heard...", "Saved as you said it..."). */
    var notice: String? by mutableStateOf(null)
        private set
    var blocker: Blocker? by mutableStateOf(null)
        private set

    /** Tasks that just came in from a note, drawn with a short wash. */
    var arrived: Set<UUID> by mutableStateOf(emptySet())
        private set

    /** Tasks whose check is filling before they move to Done today. */
    var completing: Set<UUID> by mutableStateOf(emptySet())
        private set

    /** A swiped-away task, offered back for a few seconds. */
    var deleted: TodoTask? by mutableStateOf(null)
        private set

    /** "3 to-dos from your note, Keep as one": 10 s, or until the list changes, the mic is tapped or the tab is left. */
    var keepOffer: KeepOffer? by mutableStateOf(null)
        private set

    /** The notes being sorted: saved as said already, kept out of the list until their tasks replace them. */
    var sortingNotes: Set<UUID> by mutableStateOf(emptySet())
        private set

    /** A task the list should bring into view; the list clears it once it has scrolled there. */
    var scrollTarget: UUID? by mutableStateOf(null)

    /** The note being heard has reached 4:00: the Listening card says "1 minute left", once. */
    var inLastMinute: Boolean by mutableStateOf(false)
        private set
    var sortingProgress: SortingProgress? by mutableStateOf(null)
        private set

    /** The moment the list reads from (due labels, Done today). Moves with the clock while the tab is open. */
    var now: Instant by mutableStateOf(clockNow())
        private set

    /** Android asked for a rationale before its microphone prompt: Taken's sentence with Continue and Not now. */
    var askingMicrophone: Boolean by mutableStateOf(false)
        private set

    /** A quick capture (`taken://todo/record`) asked to listen at this moment; the To-do tab takes it once in front. */
    var pendingRecording: Instant? by mutableStateOf(null)
        private set

    /** The microphone and the recognizer: the activity while it is on screen. */
    var host: VoiceHost = VoiceHost.none

    var dayStartHour: Int = 4
        private set
    var hapticsOn: Boolean = true
        private set

    private var app: AppModel? = null
    private var capture: VoiceCapture? = null
    private var sorter: NoteSorter? = null

    /** The moment, zone and day-start the note is sorted against, taken at the tap. */
    private var noteContext: TodoContext? = null
    private var watchJob: Job? = null
    private var noticeJob: Job? = null
    private var deletedJob: Job? = null
    private var keepJob: Job? = null
    private var startedAt: Instant = Instant.EPOCH
    private var lastVoiceAt: Instant = Instant.EPOCH

    /** The room's level: null until the first reading, which is where it starts (Android's RMS scale is the recognizer's). */
    private var noiseFloor: Float? = null
    private var wordCount = 0
    private var levelTick = 0

    /** Busy retries for a start that waits on Android's microphone prompt. */
    private var waitingRetries = 0
    private var foreground = true

    // MARK: Reading

    val clock: DayClock get() = DayClock(dayStartHour, zone())
    val isListening: Boolean get() = phase == TodoCapture.Phase.LISTENING

    /** The lines of each note still being sorted, kept out of the list until its tasks replace them. */
    val hiddenTaskIds: Set<UUID>
        get() {
            val notes = sortingNotes
            if (notes.isEmpty()) return emptySet()
            return state.tasks.filter { it.noteId in notes }.map { it.id }.toSet()
        }

    /** The one list's open tasks, due first, without the notes still being sorted. */
    val openTasks: List<TodoTask>
        get() {
            val hidden = hiddenTaskIds
            return state.openTasks(clock).filter { it.id !in hidden }
        }

    /** Done on the day being lived, newest first. */
    val doneToday: List<TodoTask>
        get() {
            val hidden = hiddenTaskIds
            val clock = clock
            return state.doneTasks(clock.day(now), clock).filter { it.id !in hidden }
        }

    /** Nothing open and nothing done today: the tab shows the one line that teaches it. */
    val isEmpty: Boolean get() = openTasks.isEmpty() && doneToday.isEmpty()

    fun dueParts(task: TodoTask): TodoText.DueParts? = TodoText.dueParts(task, now, clock)

    fun isOverdue(task: TodoTask): Boolean = TodoText.isOverdue(task, now, clock)

    /** "16:00" for a done task: when it was done. */
    fun doneLabel(task: TodoTask): String? = task.completedAt?.let { TodoText.clockTime(it, clock) }

    /** "Call the dentist, due tomorrow at 9:00 AM", "Buy milk, done at 4:40 PM": what TalkBack reads for a row. */
    fun spoken(task: TodoTask): String {
        val done = task.completedAt
        if (done != null) return "${task.title}, done at ${Fmt.spokenTime(done, clock.zone, locale())}"
        val due = TodoText.spokenDue(task, now, clock, locale())?.let { ", $it" } ?: ""
        return "${task.title}$due"
    }

    // MARK: Lifecycle

    /** Follows the app's day-start hour (from the wake-up time) and its haptics setting. */
    fun attach(app: AppModel) {
        this.app = app
        refresh()
    }

    /** Re-reads the clock and the app's settings (on appear, on return to the front, every 30 s on the tab). */
    fun refresh() {
        now = clockNow()
        app?.let {
            dayStartHour = it.settings.dayStartHour
            hapticsOn = it.hapticsOn
        }
    }

    /** The file changed under the screen (a widget, later). Adopted only when no write of ours is on its way. */
    fun adopt(fresh: TodoState) {
        if (persistence.busy || fresh == state) return
        state = fresh
        // Changed elsewhere: the note's tasks may not be the ones offered.
        dismissKeepOffer()
    }

    /** Taken came to the front (`ON_START`): the clock, and the due-time notifications rebuilt. */
    fun didBecomeActive() {
        foreground = true
        refresh()
        if (!isDemo) reschedule(state.tasks)
    }

    /** Taken went to the background (`ON_STOP`, not a configuration change): a note being heard stops and is saved. */
    fun didEnterBackground() {
        foreground = false
        dismissKeepOffer()
        stopIfListening()
    }

    /** Voice to-dos need Taken Pro after the first note (REDESIGN.md); the first note is on the house. */
    fun access(): ProAccess {
        val pro = app?.pro ?: return ProAccess.PRO
        return TodoGate.access(state.firstNoteAt, pro.status, pro.settled, legacyLog = false, now = clockNow())
    }

    // MARK: Capture

    /** The mic button: start, or finish and sort. */
    fun micTapped() {
        dismissKeepOffer()
        refresh()
        when (phase) {
            TodoCapture.Phase.LISTENING -> scope.launch { finishListening(TodoStopReason.TAP) }
            TodoCapture.Phase.STARTING, TodoCapture.Phase.SORTING -> Unit
            TodoCapture.Phase.IDLE -> whenAllowed { scope.launch { startListening() } }
        }
    }

    /** `taken://todo/record` (and later the widget's mic and the shortcut): listen once the To-do tab is in front. */
    fun requestRecording(at: Instant = clockNow()) {
        pendingRecording = at
    }

    /** Takes the pending recording: true when it was asked for at most 90 s ago (`TodoCaptureRoute`). */
    fun takePendingRecording(): Boolean {
        val at = pendingRecording ?: return false
        pendingRecording = null
        return TodoCaptureRoute.isFresh(at, clockNow())
    }

    /** A quick capture asked to start listening. */
    fun startFromRequest() {
        dismissKeepOffer()
        refresh()
        if (phase != TodoCapture.Phase.IDLE) return
        // The microphone may still be on its way back from whatever opened the link: a busy one gets two more tries.
        whenAllowed { scope.launch { startListening(busyRetries = 2) } }
    }

    /** Runs `action` when voice capture is open, otherwise opens the paywall and runs it once Pro is on. */
    fun whenAllowed(action: () -> Unit) {
        when (access()) {
            ProAccess.PRO, ProAccess.FIRST_SESSION, ProAccess.PENDING -> action()
            ProAccess.LOCKED -> app?.presentPaywall(PaywallOrigin.ACTION, action)
            ProAccess.CHECKING -> scope.launch {
                // Play's first answer of this launch comes within 4 s (SPEC-ANDROID 9.5).
                var waited = 0L
                while (access() == ProAccess.CHECKING && waited < CHECKING_WAIT_MS) {
                    delay(100)
                    waited += 100
                }
                if (access() == ProAccess.CHECKING) app?.presentPaywall(PaywallOrigin.ACTION, action) else whenAllowed(action)
            }
        }
    }

    private suspend fun startListening(busyRetries: Int = 0) {
        if (phase != TodoCapture.Phase.IDLE) return
        if (isDemo) {
            // CI has no microphone: the demo shows the listening state a tap opens on.
            showDemoRecording(lastMinute = false)
            return
        }
        phase = TodoCapture.Phase.STARTING
        blocker = null
        clearNotice()
        transcript = ""
        level = 0.0
        val host = host
        if (!host.microphoneGranted) {
            // In context, at the first mic tap (https://developer.android.com/training/permissions/requesting): a
            // rationale only when Android says one is due, with a way to say no.
            if (host.microphoneRationaleDue) {
                phase = TodoCapture.Phase.IDLE
                askingMicrophone = true
            } else {
                waitingRetries = busyRetries
                host.requestMicrophone()
            }
            return
        }
        begin(busyRetries)
    }

    /** Android's microphone prompt was answered. */
    fun microphoneAnswered(granted: Boolean) {
        if (phase != TodoCapture.Phase.STARTING || capture != null) return
        if (granted) {
            val retries = waitingRetries
            scope.launch { begin(retries) }
        } else {
            blocker = Blocker.MICROPHONE
            phase = TodoCapture.Phase.IDLE
        }
    }

    /** The rationale's Continue (Android's prompt next) or Not now (nothing changes; the mic asks again next time). */
    fun answerMicrophoneRationale(proceed: Boolean) {
        askingMicrophone = false
        if (!proceed || phase != TodoCapture.Phase.IDLE) return
        phase = TodoCapture.Phase.STARTING
        waitingRetries = 0
        host.requestMicrophone()
    }

    private suspend fun begin(busyRetries: Int) {
        // One sorter and one moment per note, from the tap.
        val chunkSorter = makeSorter()
        val context = TodoContext(clockNow(), zone(), dayStartHour)
        noteContext = context
        sorter = makeNoteSorter(chunkSorter, context)
        scope.launch { chunkSorter.prepare() }
        val capture = host.newVoiceCapture()
        val vocabulary = app?.let { TranscriptionVocabulary.current(it.state) } ?: emptyList()
        val started = capture.start(locale().toLanguageTag(), vocabulary, captureListener)
        if (started == VoiceCapture.Start.LISTENING && (phase != TodoCapture.Phase.STARTING || !foreground)) {
            // Taken left the front, or the data was erased, while the microphone came up: nothing is heard.
            capture.cancel()
            dropNote()
            phase = TodoCapture.Phase.IDLE
            return
        }
        when (started) {
            VoiceCapture.Start.LISTENING -> Unit
            VoiceCapture.Start.UNAVAILABLE, VoiceCapture.Start.DOWNLOADING, VoiceCapture.Start.NO_PERMISSION -> {
                dropNote()
                blocker = when (started) {
                    VoiceCapture.Start.DOWNLOADING -> Blocker.DOWNLOADING
                    VoiceCapture.Start.NO_PERMISSION -> Blocker.MICROPHONE
                    else -> Blocker.UNAVAILABLE
                }
                phase = TodoCapture.Phase.IDLE
                return
            }
            VoiceCapture.Start.BUSY -> {
                // A call or another app has the microphone.
                dropNote()
                phase = TodoCapture.Phase.IDLE
                if (busyRetries > 0) {
                    delay(BUSY_RETRY_MS)
                    startListening(busyRetries - 1)
                } else {
                    show(TodoCopy.MICROPHONE_BUSY)
                }
                return
            }
        }
        this.capture = capture
        startedAt = Instant.now()
        lastVoiceAt = startedAt
        noiseFloor = null
        wordCount = 0
        levelTick = 0
        inLastMinute = false
        phase = TodoCapture.Phase.LISTENING
        // No spoken "listening" for TalkBack: the microphone would hear it. The haptic and the button say it.
        feel(Haptic.SOFT)
        watchJob = scope.launch {
            while (isActive) {
                delay(WATCH_MS)
                if (phase != TodoCapture.Phase.LISTENING) return@launch
                val at = Instant.now()
                tick(at)
                val reason = TodoCapture.shouldStop(at, startedAt, lastVoiceAt)
                if (reason != null) {
                    // A coroutine of its own: finishing cancels this one.
                    scope.launch { finishListening(reason) }
                    return@launch
                }
            }
        }
    }

    private fun dropNote() {
        sorter = null
        noteContext = null
    }

    private val captureListener = object : VoiceCapture.Listener {
        override fun onText(text: String) {
            if (phase != TodoCapture.Phase.LISTENING) return
            val words = Words.split(text).size
            if (words > wordCount) {
                wordCount = words
                lastVoiceAt = Instant.now()
            }
            transcript = text
        }

        override fun onLevel(rms: Float) {
            if (phase != TodoCapture.Phase.LISTENING) return
            // A slow-rising noise floor: speech is anything clearly above the room.
            val floor = noiseFloor?.let { TodoCapture.nextNoiseFloor(it, rms) } ?: rms
            noiseFloor = floor
            if (TodoCapture.isVoice(rms, floor)) lastVoiceAt = Instant.now()
            levelTick += 1
            if (levelTick % 2 != 0) return
            level = TodoCapture.relativeRingLevel(rms, floor)
        }

        override fun onInterrupted() {
            // The model's scope, not the constructor's parameter of the same name.
            if (phase == TodoCapture.Phase.LISTENING) this@TodoModel.scope.launch { finishListening(TodoStopReason.INTERRUPTED) }
        }
    }

    /** Every 150 ms while listening: at 4:00 "1 minute left" appears on the card with one soft haptic. */
    private fun tick(at: Instant) {
        if (!inLastMinute && TodoCapture.capWarning(Duration.between(startedAt, at))) {
            inLastMinute = true
            // A haptic only: no sound and no TalkBack speech, the microphone is on.
            feel(Haptic.SOFT)
        }
    }

    /** Stops listening and saves what was said. Leaving Taken mid-note lands here too. */
    suspend fun finishListening(reason: TodoStopReason = TodoStopReason.TAP) {
        if (phase != TodoCapture.Phase.LISTENING) return
        val capture = capture ?: return
        phase = TodoCapture.Phase.SORTING
        watchJob?.cancel()
        inLastMinute = false
        feel(Haptic.SOFT)
        val live = Words.trimAll(transcript)
        val finalText = capture.finish()
        this.capture = null
        val heard = Words.trimAll(finalText)
        val words = heard.ifEmpty { live }
        if (words.isEmpty()) {
            dropNote()
            transcript = ""
            phase = TodoCapture.Phase.IDLE
            show(TodoCopy.NOTHING_HEARD)
            return
        }
        transcript = words
        save(words, stoppedAtCap = reason == TodoStopReason.CAP)
    }

    /** Typed instead of said: the same saving, the same Pro rule, onto the one list. */
    fun submitTyped(text: String) {
        val words = Words.trimAll(text)
        if (words.isEmpty() || phase != TodoCapture.Phase.IDLE) return
        dismissKeepOffer()
        refresh()
        whenAllowed {
            if (phase != TodoCapture.Phase.IDLE) return@whenAllowed
            phase = TodoCapture.Phase.SORTING
            transcript = words
            val chunkSorter = makeSorter()
            val context = TodoContext(clockNow(), zone(), dayStartHour)
            noteContext = context
            sorter = makeNoteSorter(chunkSorter, context)
            scope.launch { chunkSorter.prepare() }
            scope.launch { save(words, stoppedAtCap = false) }
        }
    }

    /**
     * Saves a finished note onto the one list (the stop and typing come here; tests call it to stand in for a note that
     * stopped at 5 minutes, which needs a microphone).
     */
    suspend fun save(note: String, stoppedAtCap: Boolean) {
        val context = noteContext ?: TodoContext(clockNow(), zone(), dayStartHour)
        val sorter = this.sorter ?: makeNoteSorter(makeSorter(), context)
        this.sorter = null
        noteContext = null
        // Saved at once as said, out of sight, so nothing said is lost if Android ends Taken before the sorting is done.
        // The sorted tasks replace those lines. Every id is made before its write, so a replay stores the same ones.
        val noteId = UUID.randomUUID()
        val lines = TodoValidation.asSaid(note)
        val lineIds = lines.map { UUID.randomUUID() }
        val savedAt = clockNow()
        val saved = write { it.add(lines, noteId, savedAt) { index -> lineIds[index] } }
        if (saved.isNotEmpty()) sortingNotes = sortingNotes + noteId
        val parts = sorter.finish(note)
        val sorted = TodoValidation.assemble(note, parts, context)
        val ids = sorted.drafts.map { UUID.randomUUID() }
        val at = clockNow()
        val added = if (saved.isNotEmpty()) {
            write { it.replaceNote(noteId, saved, sorted.drafts, at) { index -> ids[index] } }
        } else {
            write { it.add(sorted.drafts, noteId, at) { index -> ids[index] } }
        }
        sortingNotes = sortingNotes - noteId
        transcript = ""
        sortingProgress = null
        phase = TodoCapture.Phase.IDLE
        if (added.isEmpty()) return
        val fresh = added.map { it.id }.toSet()
        arrived = fresh
        scrollTarget = added.first().id
        feel(Haptic.CONFIRM)
        announce(if (added.size == 1) "1 to-do added: ${added[0].title}." else "${added.size} to-dos added.")
        // One line under the list: the 5-minute stop first, then Keep as one (a short note a model split), then how the
        // note was saved when no model sorted all of it (every note on Android 1.0).
        when {
            stoppedAtCap -> show(TodoCopy.STOPPED_AT_CAP, TodoCapture.CAP_NOTICE_DURATION)
            sorted.keepable -> offerKeep(KeepOffer(added[0].noteId, added.map { it.id }, note))
            else -> TodoCopy.sortingNote(sorted.sorting)?.let { show(it, TodoCapture.CAP_NOTICE_DURATION) }
        }
        scope.launch {
            delay(WASH_MS)
            if (arrived == fresh) arrived = emptySet()
        }
    }

    private fun makeNoteSorter(chunkSorter: ChunkSorting, context: TodoContext): NoteSorter =
        NoteSorter(chunkSorter, context, budget, onProgress = { part, total ->
            // The sorter reports from its own thread: the screen's state changes on the model's.
            scope.launch {
                if (phase == TodoCapture.Phase.SORTING) sortingProgress = if (total > 1) SortingProgress(part, total) else null
            }
        })

    /** Stops listening and keeps what was said (Taken went to the background mid-note). */
    fun stopIfListening() {
        if (phase != TodoCapture.Phase.LISTENING) return
        scope.launch { finishListening(TodoStopReason.LEFT_APP) }
    }

    // MARK: Tasks

    /** The circle: done (the check fills, then the task moves to Done today), or back to open. */
    fun toggle(task: TodoTask) {
        if (task.isDone) {
            write { it.reopen(task.id) }
            feel(Haptic.SOFT)
            announce("${task.title}, not done.")
            return
        }
        if (task.id in completing) return
        completing = completing + task.id
        feel(Haptic.CONFIRM)
        announce("${task.title}, done.")
        val at = clockNow()
        scope.launch {
            delay(COMPLETE_MS)
            write { it.complete(task.id, at) }
            completing = completing - task.id
        }
    }

    /** The edit sheet: the words, and when it is due. */
    fun edit(id: UUID, title: String, due: TodoDue?) {
        write { it.update(id, title, due) }
    }

    /** A tapped due-time notification: the list scrolls to its task and washes it. Left alone while a note is heard. */
    fun reveal(id: UUID) {
        refresh()
        if (phase != TodoCapture.Phase.IDLE || state.task(id) == null) return
        scrollTarget = id
        val only = setOf(id)
        arrived = only
        scope.launch {
            delay(WASH_MS)
            if (arrived == only) arrived = emptySet()
        }
    }

    fun delete(task: TodoTask) {
        val removed = write { it.delete(task.id) } ?: return
        feel(Haptic.SOFT)
        deletedJob?.cancel()
        deleted = removed
        announce("${removed.title}, deleted.")
        deletedJob = scope.launch {
            delay(UNDO_MS)
            deleted = null
        }
    }

    fun undoDelete() {
        val task = deleted ?: return
        deletedJob?.cancel()
        write { it.restore(task) }
        deleted = null
        feel(Haptic.SOFT)
    }

    /** Erase all data: the tasks go; the first note on the house stays used. */
    fun eraseAll() {
        write { it.eraseAll() }
        deletedJob?.cancel()
        deleted = null
    }

    // MARK: Keep as one

    /**
     * The note's tasks become one task again: the words said for a short note, without filler or the day and time
     * (otherwise the titles joined), the earliest due, the same note. Nothing changes when one was done or deleted.
     */
    fun keepAsOne() {
        val offer = keepOffer ?: return
        dismissKeepOffer()
        val tasks = offer.ids.mapNotNull { state.task(it) }
        val due = TodoMerge.earliestDue(tasks.map { it.due }, clock)
        if (tasks.size != offer.ids.size) return
        val title = TodoMerge.title(offer.transcript, tasks.map { it.title }, hasDue = due != null) ?: return
        val merged = write { it.mergeNote(offer.ids, title, due) } ?: return
        feel(Haptic.SOFT)
        val only = setOf(merged.id)
        arrived = only
        announce(TodoCopy.KEPT_AS_ONE)
        scope.launch {
            delay(WASH_MS)
            if (arrived == only) arrived = emptySet()
        }
    }

    /** Takes Keep as one away: any change to the list, a mic tap, leaving the tab, or its time running out. */
    fun dismissKeepOffer() {
        keepJob?.cancel()
        keepJob = null
        keepOffer = null
    }

    private fun offerKeep(offer: KeepOffer) {
        clearNotice()
        keepJob?.cancel()
        keepOffer = offer
        keepJob = scope.launch {
            delay(TodoCapture.KEEP_OFFER_DURATION.toMillis())
            keepOffer = null
        }
    }

    // MARK: Writing

    /**
     * Every change to todos.json goes through here: the screen at once, then the file. A failed save shows "Could not
     * save" and the screen goes back to what the file holds. Any change takes Keep as one away.
     */
    private fun <T> write(body: (TodoState) -> T): T {
        val base = state
        val next = base.clone()
        val value = body(next)
        state = next
        now = clockNow()
        dismissKeepOffer()
        persistence.save(base, next, { body(it) }, ::settle) { show(TodoCopy.COULD_NOT_SAVE) }
        if (!isDemo && next.tasks != base.tasks) reschedule(next.tasks)
        return value
    }

    /** No write of ours is on its way: the screen ends on exactly what the file holds. */
    private fun settle(onDisk: TodoState) {
        if (onDisk == state) return
        state = onDisk
        dismissKeepOffer()
    }

    private fun reschedule(tasks: List<TodoTask>) {
        scope.launch { notifications.reschedule(tasks) }
    }

    // MARK: Notice and feedback

    private fun show(text: String, duration: Duration = TodoCapture.NOTICE_DURATION) {
        // One line under the list at a time.
        dismissKeepOffer()
        noticeJob?.cancel()
        notice = text
        noticeJob = scope.launch {
            delay(duration.toMillis())
            notice = null
        }
    }

    private fun clearNotice() {
        noticeJob?.cancel()
        notice = null
    }

    private fun feel(haptic: Haptic) {
        val app = app ?: return
        if (hapticsOn) app.onEffect(Effect.Feel(haptic))
    }

    /** Says `text` to TalkBack, never in the demo. Never while a note is heard: the microphone would hear it. */
    private fun announce(text: String) {
        if (isDemo) return
        app?.onEffect(Effect.Announce(text))
    }

    // MARK: Demo (debug captures only; DemoScreens stages these)

    /** The listening screens: words on the card and the ring at a speaking level; past 4:00 with "1 minute left". */
    internal fun showDemoRecording(lastMinute: Boolean) {
        if (!isDemo) return
        phase = TodoCapture.Phase.LISTENING
        transcript = TodoDemo.TRANSCRIPT
        level = TodoDemo.LEVEL
        inLastMinute = lastMinute
    }

    /** A dock state for a capture: a notice, a blocker, the undo bar, the rationale. */
    internal fun stageDemo(notice: String? = null, blocker: Blocker? = null, deleted: TodoTask? = null, askingMicrophone: Boolean = false) {
        if (!isDemo) return
        this.notice = notice
        this.blocker = blocker
        this.deleted = deleted
        this.askingMicrophone = askingMicrophone
    }

    /** A capture of a note just saved: its tasks washed. */
    internal fun stageArrived(ids: Set<UUID>) {
        if (isDemo) arrived = ids
    }

    companion object {
        /** The watch while listening. */
        const val WATCH_MS = 150L

        /** A busy microphone is tried again after this, for a quick capture. */
        const val BUSY_RETRY_MS = 700L

        /** The check fills before the task moves to Done today. */
        const val COMPLETE_MS = 420L

        /** New tasks wash in the signal this long. */
        const val WASH_MS = 1_600L

        /** The undo bar after a swipe. */
        const val UNDO_MS = 4_000L

        /** Play's first answer of a launch (SPEC-ANDROID 9.5). */
        const val CHECKING_WAIT_MS = 4_000L
    }
}
