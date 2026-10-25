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
import com.tombaxter.taken.data.MemoryPersistence
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale

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
        "empty", "today", "today-pending", "today-done", "today-edit", "today-nudge-offer", "today-repair", "locked",
        "add", "add-search", "item", "set-time", "log", "day", "settings",
    )

    fun make(screen: String, look: ThemeID = ThemeID.SIGNAL, stack: DemoStack = DemoStack.STANDARD): AppModel {
        val pending = screen == "today-pending"
        val now = if (pending) morning() else now(stack)
        val allTaken = screen == "today-done"
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
        if (screen == "today-nudge-offer") state = state.copy(settings = state.settings.copy(reminderEnabled = false))
        state = state.copy(settings = state.settings.copy(theme = look))
        val locked = screen == "locked"
        val persistence = MemoryPersistence(stack = state)
        val ledger = ProLedger(firstSeenAt = now.minusSeconds(86_400L * 60), firstDoseAt = state.doses.minOfOrNull { it.takenAt })
        val prompt = when (screen) {
            "today-nudge-offer" -> TodayPrompt.NudgeOffer(state.settings.reminderMinutes)
            "today-repair" -> TodayPrompt.Repair(com.tombaxter.taken.core.day.DayClock(state.settings.dayStartHour, zone).day(now).adding(-1))
            else -> null
        }
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
            launchTab = if (screen == "log" || screen == "day") AppTab.HISTORY else AppTab.TODAY,
            launchEditing = screen == "today-edit",
            demoPrompt = prompt,
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
        }
        return model
    }
}
