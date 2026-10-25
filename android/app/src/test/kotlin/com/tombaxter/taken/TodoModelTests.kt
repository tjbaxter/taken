package com.tombaxter.taken

import com.tombaxter.taken.core.demo.TodoDemo
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.todo.ChunkSorting
import com.tombaxter.taken.core.todo.FallbackSorter
import com.tombaxter.taken.core.todo.RawTodo
import com.tombaxter.taken.core.todo.TodoCapture
import com.tombaxter.taken.core.todo.TodoChunk
import com.tombaxter.taken.core.todo.TodoCodec
import com.tombaxter.taken.core.todo.TodoCopy
import com.tombaxter.taken.core.todo.TodoDraft
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoNotifications
import com.tombaxter.taken.core.todo.TodoSorting
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoTask
import com.tombaxter.taken.data.MemoryPersistence
import com.tombaxter.taken.data.MemoryTodoPersistence
import com.tombaxter.taken.voice.VoiceCapture
import com.tombaxter.taken.voice.VoiceHost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/TodoModelTests.swift: the To-do tab's model wired together. Keep as one comes only after a short
 * note a model split and goes on any change; every note, typed to-do and quick capture lands on the one list; a note is
 * saved at once as said and hidden until its tasks replace it, then brought into view; a tapped due-time notification
 * scrolls to its task; a long note is sorted in parts; the demo's listening screens hold a fixed time. An in-memory
 * todos.json and canned model answers stand in for the file and a model. The voice note log cases are left out with the
 * log (SPEC-ANDROID 8.2).
 *
 * The cases after "Android" drive the real capture path through a fake [com.tombaxter.taken.voice.VoiceHost]: the
 * microphone asked in context, the rationale, the blockers, a busy microphone, a tap, quiet, leaving the app, back, the
 * Pro rule, links, the notification seam and a failed save.
 *
 * Every call runs on one thread, the model's, as on the phone's main thread.
 */
@RunWith(RobolectricTestRunner::class)
class TodoModelTests {
    private val dispatcher: ExecutorCoroutineDispatcher = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    @After
    fun tearDown() {
        scope.cancel()
        dispatcher.close()
    }

    private fun test(body: suspend () -> Unit) = runBlocking(dispatcher) { body() }

    /** Sorts every part with canned answers, as a model would, through the real checks. */
    private class Canned(val raw: List<RawTodo>, val delayMs: Long = 0) : ChunkSorting {
        override val unavailable: TodoSorting? = null

        override suspend fun prepare() = Unit

        override suspend fun answer(chunk: TodoChunk, prompt: String): List<RawTodo> {
            if (delayMs > 0) delay(delayMs)
            // Only the tasks said in this part.
            return raw.filter { chunk.text.lowercase().contains((it.spoken ?: it.title).lowercase()) }
        }
    }

    private val split = listOf(RawTodo(spoken = "call the dentist", title = "Call the dentist"), RawTodo(spoken = "buy milk", title = "Buy milk"))
    private val note = "call the dentist and buy milk"

    private class Rig(val model: TodoModel, val file: MemoryTodoPersistence, val app: AppModel) {
        val effects = mutableListOf<Effect>()

        init {
            app.onEffect = { effects += it }
        }

        val announced: List<String> get() = effects.filterIsInstance<Effect.Announce>().map { it.text }
    }

    private fun rig(
        raw: List<RawTodo> = split,
        delayMs: Long = 0,
        seed: TodoState = TodoState(),
        isDemo: Boolean = true,
        host: FakeHost? = null,
        sorter: (() -> ChunkSorting)? = null,
        pro: ProSource = ProSource.untilBilling,
        clock: () -> Instant = { Instant.now() },
        notifications: com.tombaxter.taken.core.todo.TodoNotificationScheduler = com.tombaxter.taken.core.todo.TodoNotificationScheduler.none,
    ): Rig {
        val file = MemoryTodoPersistence(seed)
        val model = TodoModel(
            persistence = file,
            initialState = seed,
            clockNow = clock,
            zone = { london },
            locale = { Locale.UK },
            isDemo = isDemo,
            makeSorter = sorter ?: { Canned(raw, delayMs) },
            notifications = notifications,
            scope = scope,
        )
        if (host != null) model.host = host
        val app = AppModel(
            persistence = MemoryPersistence(),
            initialState = StackState(),
            initialLedger = ProLedger(firstSeenAt = Instant.now()),
            initialProfile = Profile(),
            initialPhoto = null,
            pro = pro,
            clockNow = clock,
            zone = { london },
            locale = { Locale.UK },
            isDemo = isDemo,
            todoModel = model,
        )
        return Rig(model, file, app)
    }

    /** Waits for the note being saved. */
    private suspend fun settle(model: TodoModel) {
        val end = System.currentTimeMillis() + 8_000
        while (model.phase != TodoCapture.Phase.IDLE && System.currentTimeMillis() < end) delay(10)
    }

    private suspend fun waitForListening(model: TodoModel) {
        val end = System.currentTimeMillis() + 5_000
        while (model.phase != TodoCapture.Phase.LISTENING && System.currentTimeMillis() < end) delay(10)
    }

    private suspend fun waitFor(what: String, condition: () -> Boolean) {
        val end = System.currentTimeMillis() + 5_000
        while (!condition()) {
            check(System.currentTimeMillis() < end) { "timed out waiting for $what" }
            delay(10)
        }
    }

    /** A typed note the canned model splits in two, saved: Keep as one is offered. */
    private suspend fun offered(rig: Rig): TodoModel.KeepOffer {
        rig.model.submitTyped(note)
        settle(rig.model)
        return assertNotNull(rig.model.keepOffer, "two to-dos from one note: Keep as one is offered")
    }

    private fun titles(tasks: List<TodoTask>): Set<String> = tasks.map { it.title }.toSet()

    @Test
    fun testKeepAsOneIsOfferedForASplitNoteAndPutsItBack() = test {
        val rig = rig()
        val offer = offered(rig)
        assertEquals(2, offer.ids.size)
        assertEquals(note, offer.transcript)
        assertEquals(setOf("Call the dentist", "Buy milk"), titles(rig.model.openTasks))

        rig.model.keepAsOne()
        assertNull(rig.model.keepOffer, "once only")
        assertEquals(listOf("Call the dentist and buy milk"), rig.model.openTasks.map { it.title })
        assertEquals(listOf("Call the dentist and buy milk"), rig.file.state.tasks.map { it.title }, "and saved")
    }

    @Test
    fun testKeepAsOneIsNotOfferedForANoteOfOneToDo() = test {
        val rig = rig(listOf(RawTodo(spoken = "call the dentist", title = "Call the dentist")))
        rig.model.submitTyped("call the dentist")
        settle(rig.model)
        assertEquals(listOf("Call the dentist"), rig.model.openTasks.map { it.title })
        assertNull(rig.model.keepOffer)
    }

    @Test
    fun testKeepAsOneGoesOnAnyChangeAMicTapOrLeavingTheTab() = test {
        val deleted = rig()
        val deleting = offered(deleted)
        deleted.model.delete(assertNotNull(deleted.model.state.task(deleting.ids[1])))
        assertNull(deleted.model.keepOffer, "a task deleted")

        val edited = rig()
        val offer = offered(edited)
        edited.model.edit(offer.ids[0], "Call the dentist about the filling", null)
        assertNull(edited.model.keepOffer, "a write")

        val ticked = rig()
        val ticking = offered(ticked)
        val task = assertNotNull(ticked.model.state.task(ticking.ids[0]))
        ticked.model.toggle(task)
        delay(700)
        assertTrue(ticked.model.state.task(task.id)?.isDone ?: false)
        assertNull(ticked.model.keepOffer, "a task done")

        val elsewhere = rig()
        offered(elsewhere)
        val changed = elsewhere.file.state.clone().also { it.add(listOf(TodoDraft("From a widget")), at = Instant.now()) }
        elsewhere.file.state = changed
        elsewhere.model.adopt(changed)
        assertNull(elsewhere.model.keepOffer, "the file changed elsewhere")

        val tapped = rig()
        offered(tapped)
        tapped.model.micTapped()
        assertNull(tapped.model.keepOffer, "the mic")

        val left = rig()
        left.app.tab = AppTab.TODO
        offered(left)
        left.app.tab = AppTab.TODAY
        assertNull(left.model.keepOffer, "the tab was left")
        left.model.keepAsOne()
        assertEquals(2, left.model.openTasks.size, "nothing to keep once it has gone")
    }

    // The iPhone's case seeds a file a 1.1 list build wrote, Work on top and in view, with Tom's "LinkedIn ICP" on Work.
    // Android reads past the list values and never writes them (SPEC-ANDROID 5.2): the former Work task is on the one
    // list, and the file Android writes holds no area.
    @Test
    fun testATypedToDoLandsOnTheOneListBesideFormerWorkTasks() = test {
        val written = Instant.now().minusSeconds(3_600).epochSecond
        val seed = TodoCodec.decode(
            """{"areaOrder":["work","personal"],"lastArea":"work","schemaVersion":1,"tasks":[{"area":"work",""" +
                """"createdAt":$written,"id":"0D1B2C3D-0000-4000-8000-000000000001","noteId":"0D1B2C3D-0000-4000-8000-000000000002",""" +
                """"order":0,"title":"LinkedIn ICP"}]}""",
            london,
        )
        val rig = rig(delayMs = 300, seed = seed)
        assertEquals(listOf("LinkedIn ICP"), rig.model.openTasks.map { it.title }, "a former Work task is on the one list")
        rig.model.submitTyped(note)
        assertEquals(TodoCapture.Phase.SORTING, rig.model.phase)
        settle(rig.model)
        assertEquals(setOf("Call the dentist", "Buy milk", "LinkedIn ICP"), titles(rig.model.openTasks))
        val file = TodoCodec.encode(rig.file.state)
        assertFalse("area" in file, "no list values written: $file")
        assertEquals(3, rig.file.state.tasks.size)
    }

    @Test
    fun testAVoiceNoteAndAQuickCaptureLandOnTheOneList() = test {
        val voice = rig()
        voice.model.micTapped()
        waitForListening(voice.model)
        assertEquals(TodoCapture.Phase.LISTENING, voice.model.phase, "the demo listens without a microphone")
        // The stop itself needs a microphone: the save it ends in stands in for it.
        voice.model.save(note, stoppedAtCap = false)
        assertEquals(TodoCapture.Phase.IDLE, voice.model.phase)
        assertEquals(setOf("Call the dentist", "Buy milk"), titles(voice.model.openTasks))

        val quick = rig()
        quick.model.startFromRequest()
        waitForListening(quick.model)
        assertEquals(TodoCapture.Phase.LISTENING, quick.model.phase)
        quick.model.save("call the dentist", stoppedAtCap = false)
        assertEquals(setOf("Call the dentist"), titles(quick.model.openTasks))
    }

    @Test
    fun testATappedNotificationScrollsToItsTaskAndWashesIt() = test {
        val work = TodoTask(
            title = "Send Priya the deck", due = TodoDue.Time(at(2026, 10, 20, 10)), createdAt = at(2026, 10, 19, 9),
            noteId = UUID.randomUUID(),
        )
        val rig = rig(emptyList(), seed = TodoState(tasks = listOf(work)))
        assertEquals(work.id, TodoNotifications.taskId(TodoNotifications.identifier(work.id)))
        assertNull(TodoNotifications.taskId("taken.nudge.2026-10-19"))

        rig.model.reveal(work.id)
        assertEquals(work.id, rig.model.scrollTarget, "the list brings it into view")
        assertEquals(setOf(work.id), rig.model.arrived, "and washes it for a moment")
        rig.model.scrollTarget = null
        rig.model.reveal(UUID.randomUUID())
        assertNull(rig.model.scrollTarget, "a to-do that has gone changes nothing")
    }

    @Test
    fun testANoteIsSavedAsSaidAtOnceHiddenWhileSortedThenBroughtIntoView() = test {
        val rig = rig(delayMs = 300)
        assertTrue(rig.model.hiddenTaskIds.isEmpty())
        rig.model.submitTyped("Call the dentist. Buy milk.")
        val end = System.currentTimeMillis() + 5_000
        while (rig.model.hiddenTaskIds.isEmpty() && rig.model.phase == TodoCapture.Phase.SORTING && System.currentTimeMillis() < end) delay(10)
        assertEquals(2, rig.model.hiddenTaskIds.size, "one line per sentence, saved at once")
        assertEquals(listOf("Call the dentist", "Buy milk"), rig.file.state.tasks.map { it.title }, "in the file already, so nothing said is lost")
        assertTrue(rig.model.openTasks.isEmpty(), "and out of the list while it is sorted")
        assertTrue(rig.model.isEmpty, "so the list shows nothing of it yet")
        settle(rig.model)
        assertTrue(rig.model.hiddenTaskIds.isEmpty())
        assertEquals(setOf("Call the dentist", "Buy milk"), titles(rig.model.openTasks))
        val first = assertNotNull(rig.file.state.tasks.firstOrNull { it.title == "Call the dentist" })
        assertEquals(first.id, rig.model.scrollTarget, "the list scrolls to the note's first task")
    }

    @Test
    fun testALongTypedNoteIsSortedInPartsAndNotOfferedAsOne() = test {
        val actions = (0 until 6).map { "call person$it" }
        val raw = actions.map { RawTodo(spoken = it, title = it.replaceFirstChar { c -> c.uppercase() }) }
        val long = (0 until 6).joinToString(" ") { "Please ${actions[it]} about the thing number $it today, and then there are a few more words." }
        val rig = rig(raw)
        rig.model.submitTyped(long)
        settle(rig.model)
        assertEquals(6, rig.model.openTasks.size, "${rig.model.openTasks.map { it.title }}")
        assertNull(rig.model.keepOffer, "a long note's tasks are not one thought")
        assertNull(rig.model.notice, "every part was sorted")
    }

    /** Android 1.0's every note (SPEC-ANDROID 11): no model, so as said, one line per sentence, and the line says so. */
    @Test
    fun testNoModelSavesTheNoteOneLinePerSentenceAndSaysSo() = test {
        val rig = rig(sorter = { FallbackSorter() })
        rig.model.submitTyped("Call the dentist. Buy milk.")
        settle(rig.model)
        assertEquals(setOf("Call the dentist", "Buy milk"), titles(rig.model.openTasks))
        assertEquals(TodoCopy.ALL_UNSORTED, rig.model.notice)
        assertNull(rig.model.keepOffer, "Keep as one only follows a model's split")
    }

    // MARK: The demo's listening screens

    /** The original card (Tom 2026-10-21): no time while a note is young, one static "1 minute left" past 4:00. */
    @Test
    fun testTheDemoListeningScreensShowTheOriginalCard() = test {
        val recording = DemoScreens.make("todo-recording").todo
        assertEquals(TodoCapture.Phase.LISTENING, recording.phase)
        assertFalse(recording.inLastMinute, "no time on the card before 4:00")
        assertEquals(TodoDemo.LEVEL, recording.level)
        assertEquals(TodoDemo.TRANSCRIPT, recording.transcript)

        val cap = DemoScreens.make("todo-cap")
        assertEquals(TodoCapture.Phase.LISTENING, cap.todo.phase)
        assertTrue(cap.todo.inLastMinute, "a note past 4:00 says 1 minute left")
        assertEquals(AppTab.TODO, cap.tab, "the todo screens open on the To-do tab")

        // A tap in the demo listens on the same card, and the model follows the app's haptics setting.
        val tapped = rig()
        tapped.model.micTapped()
        waitForListening(tapped.model)
        assertEquals(TodoCapture.Phase.LISTENING, tapped.model.phase)
        assertEquals(tapped.app.hapticsOn, tapped.model.hapticsOn)
        assertFalse(tapped.model.inLastMinute)
    }

    // MARK: After a 5-minute stop

    @Test
    fun testAfterAFiveMinuteStopTheLineSaysSoAndTheNextTapKeepsGoing() = test {
        val rig = rig()
        // A note stopped at 5 minutes (the stop itself needs a microphone).
        rig.model.save(note, stoppedAtCap = true)
        assertEquals(TodoCopy.STOPPED_AT_CAP, rig.model.notice)
        assertNull(rig.model.keepOffer, "the 5-minute line comes first")
        assertEquals(setOf("Call the dentist", "Buy milk"), titles(rig.model.openTasks))
        rig.model.micTapped()
        waitForListening(rig.model)
        assertEquals(TodoCapture.Phase.LISTENING, rig.model.phase, "Tap the mic to keep going")

        val other = rig()
        other.model.save(note, stoppedAtCap = false)
        assertNotEquals(TodoCopy.STOPPED_AT_CAP, other.model.notice)
        assertNotNull(other.model.keepOffer, "a short note split in two offers Keep as one")
    }

    // MARK: Android: the microphone, the recognizer and the stop rules

    @Test
    fun testTheFirstMicTapAsksForTheMicrophoneInContextThenListens() = test {
        val host = FakeHost(granted = false)
        val rig = rig(isDemo = false, host = host, sorter = { FallbackSorter() })
        rig.model.micTapped()
        waitFor("the prompt") { host.asked == 1 }
        assertEquals(TodoCapture.Phase.STARTING, rig.model.phase, "waiting on Android's prompt")
        assertTrue(host.captures.isEmpty(), "nothing listens before the answer")
        assertFalse(rig.model.askingMicrophone, "no rationale unless Android says one is due")

        host.granted = true
        rig.model.microphoneAnswered(true)
        waitForListening(rig.model)
        val capture = host.captures.single()
        assertEquals("en-GB", capture.language, "the phone's language")
        assertTrue(capture.vocabulary.isNotEmpty(), "the names to expect")
        assertTrue(TodoCapture.keepsScreenOn(rig.model.phase, rig.model.isDemo), "the screen stays on while listening")
    }

    @Test
    fun testARationaleComesOnlyWhenAndroidSaysOneIsDueAndNotNowChangesNothing() = test {
        val host = FakeHost(granted = false, rationale = true)
        val rig = rig(isDemo = false, host = host)
        rig.model.micTapped()
        waitFor("the rationale") { rig.model.askingMicrophone }
        assertEquals(TodoCapture.Phase.IDLE, rig.model.phase)
        assertEquals(0, host.asked, "Taken's sentence first")
        assertTrue(TodoCopy.MIC_RATIONALE.contains("never saved"), "SPEC-ANDROID 6.4's sentence")

        rig.model.answerMicrophoneRationale(proceed = false)
        assertFalse(rig.model.askingMicrophone)
        assertEquals(0, host.asked, "Not now asks nothing")
        assertNull(rig.model.blocker, "and blocks nothing")

        rig.model.micTapped()
        waitFor("the rationale again") { rig.model.askingMicrophone }
        rig.model.answerMicrophoneRationale(proceed = true)
        assertEquals(1, host.asked, "Continue shows Android's prompt")
        assertEquals(TodoCapture.Phase.STARTING, rig.model.phase)
        rig.model.microphoneAnswered(false)
        assertEquals(TodoModel.Blocker.MICROPHONE, rig.model.blocker, "denied: the card with Open Settings and Type it instead")
        assertEquals(TodoCapture.Phase.IDLE, rig.model.phase)
    }

    @Test
    fun testADeniedMicrophoneShowsTheBlockerAndTypingStillSaves() = test {
        val host = FakeHost(granted = false)
        val rig = rig(isDemo = false, host = host, sorter = { FallbackSorter() })
        rig.model.micTapped()
        waitFor("the prompt") { host.asked == 1 }
        rig.model.microphoneAnswered(false)
        assertEquals(TodoModel.Blocker.MICROPHONE, rig.model.blocker)
        rig.model.submitTyped("Call the dentist")
        settle(rig.model)
        assertEquals(listOf("Call the dentist"), rig.model.openTasks.map { it.title }, "typing is the way round it")
    }

    @Test
    fun testNoOnDeviceRecognitionOrALanguageDownloadShowsTheBlocker() = test {
        val host = FakeHost(next = { FakeCapture(answer = VoiceCapture.Start.UNAVAILABLE) })
        val rig = rig(isDemo = false, host = host)
        rig.model.micTapped()
        waitFor("the blocker") { rig.model.blocker != null }
        assertEquals(TodoModel.Blocker.UNAVAILABLE, rig.model.blocker)
        assertEquals(TodoCapture.Phase.IDLE, rig.model.phase)
        assertTrue(TodoCopy.UNAVAILABLE.contains("this phone"), "Android's wording (SPEC-ANDROID 6.4)")

        host.next = { FakeCapture(answer = VoiceCapture.Start.DOWNLOADING) }
        rig.model.micTapped()
        waitFor("the download") { rig.model.blocker == TodoModel.Blocker.DOWNLOADING }
        assertEquals(TodoCapture.Phase.IDLE, rig.model.phase)
    }

    @Test
    fun testABusyMicrophoneSaysSoAndAQuickCaptureTriesTwiceMore() = test {
        val host = FakeHost(next = { FakeCapture(answer = VoiceCapture.Start.BUSY) })
        val rig = rig(isDemo = false, host = host)
        rig.model.micTapped()
        waitFor("the notice") { rig.model.notice != null }
        assertEquals(TodoCopy.MICROPHONE_BUSY, rig.model.notice)
        assertEquals(1, host.captures.size, "a tap tries once")

        rig.model.startFromRequest()
        waitFor("three tries") { host.captures.size == 4 && rig.model.phase == TodoCapture.Phase.IDLE }
        assertEquals(TodoCopy.MICROPHONE_BUSY, rig.model.notice)
    }

    @Test
    fun testATapFinishesAndTheNoteIsSavedAsSaidOneLinePerSentence() = test {
        val host = FakeHost()
        val rig = rig(isDemo = false, host = host, sorter = { FallbackSorter() })
        rig.model.micTapped()
        waitForListening(rig.model)
        val capture = host.captures.single()
        capture.listener?.onText("Call the dentist. Buy")
        assertEquals("Call the dentist. Buy", rig.model.transcript, "the words as they are said")
        capture.finalText = "Call the dentist. Buy milk."
        rig.model.micTapped()
        settle(rig.model)
        assertTrue(capture.finished)
        assertEquals(listOf("Call the dentist", "Buy milk"), rig.model.openTasks.map { it.title }, "in the order said")
        assertEquals(TodoCopy.ALL_UNSORTED, rig.model.notice)
        assertNotNull(rig.model.state.firstNoteAt, "the first note is noted")
        assertTrue("2 to-dos added." in rig.announced)
        assertFalse(TodoCapture.keepsScreenOn(rig.model.phase, rig.model.isDemo), "the screen may sleep again")
    }

    @Test
    fun testNothingHeardSaysSoAndSavesNothing() = test {
        val host = FakeHost()
        val rig = rig(isDemo = false, host = host)
        rig.model.micTapped()
        waitForListening(rig.model)
        rig.model.micTapped()
        settle(rig.model)
        assertEquals(TodoCopy.NOTHING_HEARD, rig.model.notice)
        assertTrue(rig.model.state.tasks.isEmpty())
        assertNull(rig.model.state.firstNoteAt, "an empty note is not the first note")
    }

    @Test
    fun testTheWordsHeardAreKeptWhenTheRecognizerEndsWithNone() = test {
        val host = FakeHost()
        val rig = rig(isDemo = false, host = host, sorter = { FallbackSorter() })
        rig.model.micTapped()
        waitForListening(rig.model)
        host.captures.single().listener?.onText("Buy milk")
        rig.model.micTapped()
        settle(rig.model)
        assertEquals(listOf("Buy milk"), rig.model.openTasks.map { it.title })
    }

    @Test
    fun testLeavingTheAppOrAnInterruptionStopsListeningAndKeepsTheWords() = test {
        val host = FakeHost()
        val left = rig(isDemo = false, host = host, sorter = { FallbackSorter() })
        left.model.micTapped()
        waitForListening(left.model)
        host.captures.last().listener?.onText("Renew the passport")
        left.app.didEnterBackground()
        settle(left.model)
        assertEquals(listOf("Renew the passport"), left.model.openTasks.map { it.title }, "a trip home saves the note")

        val cut = rig(isDemo = false, host = host, sorter = { FallbackSorter() })
        cut.model.micTapped()
        waitForListening(cut.model)
        host.captures.last().listener?.onText("Book the gym")
        host.captures.last().listener?.onInterrupted()
        settle(cut.model)
        assertEquals(listOf("Book the gym"), cut.model.openTasks.map { it.title }, "a call taking the microphone saves it too")
    }

    /** SPEC-ANDROID 6.2's back order: stop listening (keeping the words, as a tap would), then Today, then leave. */
    @Test
    fun testBackStopsListeningKeepingTheWordsThenReturnsToToday() = test {
        val host = FakeHost()
        val rig = rig(isDemo = false, host = host, sorter = { FallbackSorter() })
        rig.app.tab = AppTab.TODO
        rig.model.micTapped()
        waitForListening(rig.model)
        host.captures.single().listener?.onText("Water the plants")
        assertTrue(rig.app.backOnTabs(), "back stops listening")
        settle(rig.model)
        assertEquals(listOf("Water the plants"), rig.model.openTasks.map { it.title })
        assertEquals(AppTab.TODO, rig.app.tab, "and stays on To-do")
        assertTrue(rig.app.backOnTabs())
        assertEquals(AppTab.TODAY, rig.app.tab)
        assertFalse(rig.app.backOnTabs(), "then Taken goes")
    }

    /** REDESIGN.md: the first voice note needs no Pro, then the mic and typing do; finishing and editing never. */
    @Test
    fun testTheFirstNoteIsOnTheHouseThenTheMicNeedsPro() = test {
        val host = FakeHost()
        val rig = rig(isDemo = false, host = host, sorter = { FallbackSorter() }, pro = ProSource.locked)
        rig.model.micTapped()
        waitForListening(rig.model)
        host.captures.single().finalText = "Call the bank"
        rig.model.micTapped()
        settle(rig.model)
        assertEquals(listOf("Call the bank"), rig.model.openTasks.map { it.title }, "the first note needs no Pro")
        assertNull(rig.app.paywall)

        rig.model.micTapped()
        assertNotNull(rig.app.paywall, "after it the mic opens the paywall")
        assertEquals(TodoCapture.Phase.IDLE, rig.model.phase)
        assertEquals(1, host.captures.size, "and nothing listens")
        rig.app.closePaywall()
        rig.model.submitTyped("Buy milk")
        assertNotNull(rig.app.paywall, "typing too")
        rig.app.closePaywall()

        val task = rig.model.openTasks.single()
        rig.model.toggle(task)
        waitFor("done") { rig.model.state.task(task.id)?.isDone == true }
        rig.model.edit(task.id, "Call the bank about the card", null)
        assertEquals("Call the bank about the card", rig.model.state.task(task.id)?.title, "finishing and editing are never locked")
    }

    @Test
    fun testALinkBringsToDoForwardAndRecordListensOnlyWithin90Seconds() = test {
        var now = at(2026, 10, 21, 9)
        val rig = rig(clock = { now })
        rig.app.openProfile()
        rig.app.sheet = Sheet.Add
        rig.app.handle("taken://todo")
        assertEquals(AppTab.TODO, rig.app.tab)
        assertEquals(listOf<Route>(Route.Main), rig.app.backStack.toList(), "over Profile")
        assertNull(rig.app.sheet)
        assertNull(rig.model.pendingRecording, "the list only")
        assertTrue(rig.app.showsTodoTabUncovered)

        rig.app.tab = AppTab.HISTORY
        rig.app.handle("taken://todo/record")
        assertEquals(AppTab.TODO, rig.app.tab)
        assertTrue(rig.model.takePendingRecording(), "listening asked for now")
        assertFalse(rig.model.takePendingRecording(), "once")

        rig.app.handle("taken://todo/record")
        now = now.plusSeconds(91)
        assertFalse(rig.model.takePendingRecording(), "a request more than 90 s old is dropped")
    }

    /** The due-time notifications' seam (SPEC-ANDROID 10.4): every change to a task and every return to the front. */
    @Test
    fun testEveryChangeHandsTheTasksToTheDueTimeNotifications() = test {
        val rebuilt = mutableListOf<List<TodoTask>>()
        val scheduler = com.tombaxter.taken.core.todo.TodoNotificationScheduler { rebuilt += it }
        val task = TodoTask(title = "Call the dentist", createdAt = Instant.now(), noteId = UUID.randomUUID())
        val rig = rig(isDemo = false, seed = TodoState(tasks = listOf(task)), notifications = scheduler)
        rig.model.edit(task.id, "Call the dentist", TodoDue.Time(Instant.now().plusSeconds(3_600)))
        waitFor("a rebuild") { rebuilt.size == 1 }
        assertEquals(rig.model.state.tasks, rebuilt.last())
        rig.model.edit(task.id, "Call the dentist", rig.model.state.task(task.id)?.due)
        delay(50)
        assertEquals(1, rebuilt.size, "a write that changed no task rebuilds nothing")
        rig.app.didBecomeActive()
        waitFor("a rebuild on return") { rebuilt.size == 2 }
    }

    @Test
    fun testAFailedSaveSaysSoAndNothingUnsavedShows() = test {
        val rig = rig(sorter = { FallbackSorter() })
        rig.file.failNext = true
        rig.model.submitTyped("Call the dentist")
        settle(rig.model)
        assertEquals(TodoCopy.COULD_NOT_SAVE, rig.model.notice)
        assertTrue(rig.model.openTasks.isEmpty(), "a task that was not saved never shows")
        assertTrue(rig.file.state.tasks.isEmpty())
    }

    @Test
    fun testTheCircleFinishesATaskOnceTheCheckFillsAndATapReopensIt() = test {
        val task = TodoTask(title = "Buy milk", createdAt = Instant.now(), noteId = UUID.randomUUID())
        val rig = rig(seed = TodoState(tasks = listOf(task)))
        rig.model.toggle(task)
        assertTrue(task.id in rig.model.completing, "the check fills first")
        assertFalse(rig.model.state.task(task.id)?.isDone ?: true)
        waitFor("done") { rig.model.doneToday.any { it.id == task.id } }
        assertTrue(rig.model.openTasks.isEmpty(), "it moved to Done today")
        assertTrue(rig.model.completing.isEmpty())
        rig.model.toggle(assertNotNull(rig.model.state.task(task.id)))
        assertEquals(listOf("Buy milk"), rig.model.openTasks.map { it.title }, "back to open")
    }

    @Test
    fun testADeleteOffersUndoThatPutsTheTaskBack() = test {
        val task = TodoTask(title = "Buy milk", createdAt = Instant.now(), noteId = UUID.randomUUID())
        val rig = rig(seed = TodoState(tasks = listOf(task)))
        rig.model.delete(task)
        assertEquals(task, rig.model.deleted)
        assertTrue(rig.model.openTasks.isEmpty())
        assertEquals(TodoCopy.deleted("Buy milk"), "Deleted: Buy milk")
        rig.model.undoDelete()
        assertNull(rig.model.deleted)
        assertEquals(listOf(task), rig.file.state.tasks, "back as it was, and saved")
    }

    @Test
    fun testEraseAllDataEmptiesTheListAndKeepsTheFirstNote() = test {
        val first = Instant.now().minusSeconds(86_400)
        val task = TodoTask(title = "Buy milk", createdAt = first, noteId = UUID.randomUUID())
        val rig = rig(seed = TodoState(tasks = listOf(task), firstNoteAt = first))
        rig.app.eraseAll()
        assertTrue(rig.model.state.tasks.isEmpty())
        assertEquals(first, rig.file.state.firstNoteAt, "the first note on the house stays used")
    }

    companion object {
        val london: ZoneId = ZoneId.of("Europe/London")

        fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0): Instant =
            ZonedDateTime.of(year, month, day, hour, minute, 0, 0, london).toInstant()
    }
}

/** A recognizer that hears what a test says it heard. */
internal class FakeCapture(var answer: VoiceCapture.Start = VoiceCapture.Start.LISTENING, var finalText: String = "") : VoiceCapture {
    var listener: VoiceCapture.Listener? = null
    var language: String? = null
    var vocabulary: List<String> = emptyList()
    var finished = false
    var cancelled = false

    override suspend fun start(languageTag: String, vocabulary: List<String>, listener: VoiceCapture.Listener): VoiceCapture.Start {
        this.listener = listener
        this.language = languageTag
        this.vocabulary = vocabulary
        return answer
    }

    override suspend fun finish(): String {
        finished = true
        return finalText
    }

    override fun cancel() {
        cancelled = true
    }
}

/** Android's side of the microphone: RECORD_AUDIO as the test sets it, the prompts counted, captures made on demand. */
internal class FakeHost(
    var granted: Boolean = true,
    var rationale: Boolean = false,
    var next: () -> FakeCapture = { FakeCapture() },
) : VoiceHost {
    var asked = 0
    var settingsOpened = 0
    val captures = mutableListOf<FakeCapture>()

    override val microphoneGranted: Boolean get() = granted
    override val microphoneRationaleDue: Boolean get() = rationale

    override fun requestMicrophone() {
        asked += 1
    }

    override fun openAppSettings() {
        settingsOpened += 1
    }

    override fun newVoiceCapture(): VoiceCapture = next().also { captures += it }
}
