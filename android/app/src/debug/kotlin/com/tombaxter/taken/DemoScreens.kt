package com.tombaxter.taken

import com.tombaxter.taken.core.catalog.FrequencyChoice
import com.tombaxter.taken.core.demo.DemoData
import com.tombaxter.taken.core.demo.DemoStack
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.core.demo.TodoDemo
import com.tombaxter.taken.core.todo.TodoCopy
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoValidation
import com.tombaxter.taken.data.MemoryPersistence
import com.tombaxter.taken.data.MemoryTodoPersistence
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import java.util.UUID

/**
 * Debug builds only (never in release, SPEC-ANDROID 4): the demo screens CI draws for Tom, named as the iPhone's
 * scripts/screenshots.sh names them, on a fixed day so every capture is the same. The stack is DemoData's (Vitamin D3,
 * Finasteride, Fish Oil 2x, Creatine, Magnesium, Zinc every other day, with weeks of history), in London, on Wednesday
 * 21 October 2026 at 21:41: the end-of-day moment Taken exists for.
 */
object DemoScreens {
    val zone: ZoneId = ZoneId.of("Europe/London")

    /** Wednesday 21 October 2026 at 21:41 in London (a store set moves back to the Thursday before). */
    fun now(stack: DemoStack = DemoStack.STANDARD): Instant =
        DemoData.referenceNow(ZonedDateTime.of(2026, 10, 21, 10, 0, 0, 0, zone).toInstant(), zone, stack)

    /** A morning: 07:20 the same day, before anything is taken. */
    fun morning(): Instant = ZonedDateTime.of(2026, 10, 21, 7, 20, 0, 0, zone).toInstant()

    val screens = listOf(
        "empty", "today", "today-pending", "today-done", "today-edit", "today-nudge-offer", "today-repair",
        "today-widget-invite", "locked",
        "add", "add-search", "item", "set-time", "log", "day", "settings",
        // The To-do tab (SPEC-ANDROID 11): the list, listening, past 4:00, empty, the blockers, a note just saved as
        // said, the undo bar, the edit and type sheets, and the microphone's rationale.
        "todo", "todo-recording", "todo-cap", "todo-empty", "todo-blocker", "todo-unavailable", "todo-saved",
        "todo-deleted", "todo-edit", "todo-type", "todo-mic-ask",
        // Reminders (SPEC-ANDROID 10.4): the explanation before Android's notification prompt comes again.
        "notify-ask",
    )

    /**
     * Profile's Reminder section (SPEC-ANDROID 10.4), drawn scrolled to it: the nudge on with its time; notifications off
     * for Taken, with the Settings link; only the nudge's channel off; and locked, where the nudge needs Taken Pro.
     */
    val reminderScreens = listOf("settings-reminder", "settings-reminder-off", "settings-reminder-channel", "settings-reminder-locked")

    /**
     * The to-dos a screen shows: TodoDemo's one list (a time tonight, a day this week, two done today, and what the
     * recording's ramble became), empty for `todo-empty`. `todo-saved` adds the ramble as Android saves it: as said, one
     * line per sentence. `todo-deleted` has "Send Mum the photos" swiped away.
     */
    private fun todos(screen: String, now: Instant): TodoState {
        val recording = screen == "todo-recording" || screen == "todo-cap" || screen == "todo-saved"
        val state = when (screen) {
            "todo-empty" -> TodoState()
            else -> TodoDemo.state(now, recording = recording, zone = zone)
        }
        if (screen == "todo-saved") {
            var counter = 0L
            state.add(TodoValidation.lines(TodoDemo.TRANSCRIPT), noteId = UUID(0x7A4E_0000_0000_4000L, 0x0BADL), at = now.minusSeconds(4)) {
                counter += 1
                UUID(0x7A4E_0000_0000_4000L, 0x0C00L + counter)
            }
        }
        if (screen == "todo-deleted") state.tasks = state.tasks.filter { it.title != DELETED_TITLE }
        return state
    }

    private const val DELETED_TITLE = "Send Mum the photos"

    fun make(screen: String, look: ThemeID = ThemeID.SIGNAL, stack: DemoStack = DemoStack.STANDARD): AppModel {
        val pending = screen == "today-pending"
        val now = if (pending) morning() else now(stack)
        // The widget invite shows on the first day that reaches All taken.
        val allTaken = screen == "today-done" || screen == "today-widget-invite"
        var state = when (screen) {
            "empty", "add", "add-search" -> StackState(settings = StackSettings(reminderEnabled = true))
            else -> DemoData.state(now, allTaken = allTaken, yesterdayPartial = screen == "today-repair", zone = zone, stack = stack)
        }
        if (pending) {
            // Today's morning doses are still to come at 07:20.
            val clock = com.tombaxter.taken.core.day.DayClock(state.settings.dayStartHour, zone)
            val today = clock.day(now)
            state = state.copy(doses = state.doses.filter { clock.day(it) != today })
        }
        if (screen == "today-nudge-offer" || screen == "settings-reminder-off" || screen == "settings-reminder-locked") {
            state = state.copy(settings = state.settings.copy(reminderEnabled = false))
        }
        state = state.copy(settings = state.settings.copy(theme = look))
        val locked = screen == "locked" || screen == "settings-reminder-locked"
        val persistence = MemoryPersistence(stack = state)
        val ledger = ProLedger(firstSeenAt = now.minusSeconds(86_400L * 60), firstDoseAt = state.doses.minOfOrNull { it.takenAt })
        val prompt = when (screen) {
            "today-nudge-offer" -> TodayPrompt.NudgeOffer(state.settings.reminderMinutes)
            "today-repair" -> TodayPrompt.Repair(com.tombaxter.taken.core.day.DayClock(state.settings.dayStartHour, zone).day(now).adding(-1))
            "today-widget-invite" -> TodayPrompt.WidgetInvite
            else -> null
        }
        val todoState = todos(screen, now)
        val todo = TodoModel(
            MemoryTodoPersistence(todoState), todoState, clockNow = { now }, zone = { zone }, locale = { Locale.US }, isDemo = true,
        )
        val model = AppModel(
            persistence = persistence,
            initialState = state,
            initialLedger = ledger,
            initialProfile = if (screen == "empty") Profile() else Profile(DemoData.PROFILE_NAME),
            initialPhoto = null,
            pro = if (locked) ProSource.locked else ProSource.untilBilling,
            clockNow = { now },
            zone = { zone },
            locale = { Locale.US },
            isDemo = true,
            launchTab = when {
                screen == "log" || screen == "day" -> AppTab.HISTORY
                screen.startsWith("todo") -> AppTab.TODO
                else -> AppTab.TODAY
            },
            launchEditing = screen == "today-edit",
            demoPrompt = prompt,
            todoModel = todo,
            // An Android 13 phone whose launcher can pin widgets, without the tile yet: Profile offers it.
            surfaceHost = SurfaceHost.fake(canPin = true, offersTile = true),
        )
        when (screen) {
            "add" -> {
                model.addSeed = AddSeed(
                    selected = listOf("Vitamin D3", "Fish Oil", "Finasteride"),
                    choices = mapOf("Finasteride" to FrequencyChoice.ALTERNATE),
                )
                model.sheet = Sheet.Add
            }
            "add-search" -> {
                model.addSeed = AddSeed(query = stack.typedQuery)
                model.sheet = Sheet.Add
            }
            "item" -> model.state.items.firstOrNull { it.name == "Finasteride" }?.let { model.sheet = Sheet.EditItem(it.id) }
            "set-time" -> model.state.items.firstOrNull { it.name == "Magnesium" }?.let { model.sheet = Sheet.SetTime(it.id) }
            "day" -> model.sheet = Sheet.Day(DemoData.sheetDay(now, zone))
            "settings" -> model.openProfile()
            "settings-reminder", "settings-reminder-locked" -> model.openProfile()
            "settings-reminder-off" -> {
                model.openProfile()
                model.notifications.stageDemo(denied = true)
            }
            "settings-reminder-channel" -> {
                model.openProfile()
                model.notifications.stageDemo(channelOff = true)
            }
            "notify-ask" -> model.notifications.stageDemo(asking = true)
            "todo-recording" -> todo.showDemoRecording(lastMinute = false)
            "todo-cap" -> todo.showDemoRecording(lastMinute = true)
            "todo-blocker" -> todo.stageDemo(blocker = TodoModel.Blocker.MICROPHONE)
            "todo-unavailable" -> todo.stageDemo(blocker = TodoModel.Blocker.UNAVAILABLE)
            "todo-saved" -> {
                val note = todoState.tasks.filter { it.noteId == UUID(0x7A4E_0000_0000_4000L, 0x0BADL) }
                todo.stageArrived(note.map { it.id }.toSet())
                todo.stageDemo(notice = TodoCopy.ALL_UNSORTED)
            }
            "todo-deleted" -> {
                val gone = TodoDemo.state(now, recording = false, zone = zone).tasks.first { it.title == DELETED_TITLE }
                todo.stageDemo(deleted = gone)
            }
            "todo-edit" -> todoState.tasks.firstOrNull { it.title == "Take the bins out" }?.let { model.sheet = Sheet.TodoEdit(it.id) }
            "todo-type" -> model.sheet = Sheet.TodoType
            "todo-mic-ask" -> todo.stageDemo(askingMicrophone = true)
        }
        return model
    }
}
