package com.tombaxter.taken.core

import com.tombaxter.taken.core.catalog.AddCopy
import com.tombaxter.taken.core.catalog.AddPlan
import com.tombaxter.taken.core.catalog.FrequencyChoice
import com.tombaxter.taken.core.catalog.Suggest
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.demo.DemoStack
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.StackCodec
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.profile.ProfileCodec
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.stack.DayStatus
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.addItems
import com.tombaxter.taken.core.stack.logDose
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/RedesignTests.swift, the pure cases: the wake-up time and the day it rolls over, a frequency per
 * item in the Add sheet, the profile. The tab and erase cases run against Android's AppModel and stores in :app.
 */
class RedesignTests {

    // MARK: Wake-up time

    @Test
    fun testTheDayRollsOverFourHoursBeforeWakingUpBetweenMidnightAndNoon() {
        assertEquals(4, StackSettings.dayStartHour(forWake = 8 * 60))
        assertEquals(1, StackSettings.dayStartHour(forWake = 5 * 60))
        assertEquals(10, StackSettings.dayStartHour(forWake = 14 * 60))
        assertEquals(0, StackSettings.dayStartHour(forWake = 2 * 60), "never before midnight")
        assertEquals(0, StackSettings.dayStartHour(forWake = 4 * 60))
        assertEquals(12, StackSettings.dayStartHour(forWake = 23 * 60), "never after noon")
        assertEquals(3, StackSettings.dayStartHour(forWake = 7 * 60 + 30), "a half hour rolls over on the hour before")
        assertEquals(7 * 60, StackSettings().wakeMinutes, "07:00 unless chosen")
        assertEquals(3, StackSettings().dayStartHour)
    }

    @Test
    fun testADayStartFromBeforeBecomesTheWakeUpTimeAndNoHistoryMoves() {
        for (hour in 0..12) {
            val settings = StackCodec.decode("""{"settings":{"dayStartHour":$hour}}""").settings
            assertEquals((hour + 4) * 60, settings.wakeMinutes)
            assertEquals(hour, settings.dayStartHour, "the day still rolls over at $hour:00")
        }
        val legacy = StackCodec.decode("""{"settings":{"dayStartHour":4,"reminderMinutes":1260}}""").settings
        assertEquals(8 * 60, legacy.wakeMinutes, "1.0's default 04:00 is waking at 08:00")
        assertEquals(21 * 60, legacy.reminderMinutes, "a nudge time already set stays")

        // A history logged with the 04:00 rollover reads the same after the move to the wake-up time.
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val before = StackState(items = listOf(vd3), settings = StackSettings.fromDayStartHour(4))
        before.logDose(vd3.id, at(2026, 10, 13, 1, 30), london)
        val after = StackCodec.decode(StackCodec.encode(before))
        val clock = DayClock(after.settings.dayStartHour, london)
        assertEquals(DayStatus.COMPLETE, StackEngine(after, clock).summary(DayKey(2026, 10, 12)).status, "01:30 still counts for the night before")
    }

    @Test
    fun testTheWakeUpTimeIsStoredWithItsRolloverAndReadBack() {
        val settings = StackSettings(wakeMinutes = 6 * 60 + 15)
        settings.reminderEnabled = true
        val text = StackCodec.encode(StackState(settings = settings))
        assertTrue(text.contains("\"wakeMinutes\":375"), text)
        assertTrue(text.contains("\"dayStartHour\":2"), "an earlier build reading this file rolls over at the same hour")
        assertFalse(text.contains("reminderMinutes"), "no nudge time chosen, none stored")
        assertEquals(settings, StackCodec.decode(text).settings)
    }

    @Test
    fun testTheNudgeAndBackfillFollowTheWakeUpTimeUntilChosen() {
        val settings = StackSettings(wakeMinutes = 6 * 60)
        assertEquals(19 * 60, settings.reminderMinutes, "13 hours after waking")
        assertEquals(7 * 60, settings.backfillMinutes, "an hour after waking")
        settings.wakeMinutes = 12 * 60
        assertEquals(1 * 60, settings.reminderMinutes, "past midnight wraps")
        settings.reminderMinutes = 21 * 60 + 30
        assertEquals(21 * 60 + 30, settings.chosenReminderMinutes)
        settings.wakeMinutes = 5 * 60
        assertEquals(21 * 60 + 30, settings.reminderMinutes, "a chosen time stays put")
        assertEquals(0, StackSettings(wakeMinutes = -40).wakeMinutes)
        assertEquals(24 * 60 - 1, StackSettings(wakeMinutes = 9000).wakeMinutes)

        // The nudge plan reads the derived time.
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3), settings = StackSettings(wakeMinutes = 7 * 60, reminderEnabled = true))
        val plans = Reminders.plan(state, at(2026, 10, 12, 9), london)
        assertEquals(at(2026, 10, 12, 20), plans.firstOrNull()?.fireDate, "07:00 wake: the nudge at 20:00")
    }

    // MARK: Adding

    @Test
    fun testEachPickedItemKeepsItsOwnFrequency() {
        val drafts = AddPlan.drafts(
            selected = listOf("Vitamin D3", "Fish Oil", "Finasteride"),
            extras = listOf("  Lion's Mane ", "Grandma's Tonic"),
            choices = mapOf("Finasteride" to FrequencyChoice.ALTERNATE, "Fish Oil" to FrequencyChoice.TWICE, "  Lion's Mane " to FrequencyChoice.DAYS),
            days = mapOf("  Lion's Mane " to setOf(2, 4, 6)),
            weekday = 2,
        )
        assertEquals(listOf("Vitamin D3", "Fish Oil", "Finasteride", "Lion's Mane", "Grandma's Tonic"), drafts.map { it.name })
        assertEquals(
            listOf(Frequency.Daily(1), Frequency.Daily(2), Frequency.AlternateDays, Frequency.Weekdays(setOf(2, 4, 6)), Frequency.Daily(1)),
            drafts.map { it.frequency },
            "Finasteride every other day while D3 is daily, in one go",
        )
        assertEquals("VD3", drafts[0].code, "the chip's code")
        assertEquals("LMN", drafts[3].code, "a suggestion brings its catalog code")
        assertNull(drafts[4].code, "a name the catalog does not know gets one when it is added")

        val noDays = AddPlan.drafts(listOf("Zinc"), emptyList(), mapOf("Zinc" to FrequencyChoice.DAYS), mapOf("Zinc" to emptySet()), weekday = 2)
        assertEquals(listOf<Frequency>(Frequency.Daily(1)), noDays.map { it.frequency }, "Days with none picked is never an item never due")
        assertEquals(
            listOf<Frequency>(Frequency.Weekdays(FrequencyChoice.defaultDays)),
            AddPlan.drafts(listOf("Zinc"), emptyList(), mapOf("Zinc" to FrequencyChoice.DAYS), emptyMap(), weekday = 2).map { it.frequency },
        )
        assertTrue(AddPlan.drafts(emptyList(), listOf("   "), emptyMap(), emptyMap(), weekday = 2).isEmpty())
        assertEquals(
            listOf("Zinc"),
            AddPlan.drafts(listOf("Zinc"), listOf("zinc", " ZINC "), emptyMap(), emptyMap(), weekday = 2).map { it.name },
            "a name picked twice, in any case, is added once",
        )

        val state = StackState()
        val added = state.addItems(drafts, at(2026, 10, 13, 9))
        val engine = StackEngine(state.clone(), londonClock())
        state.logDose(added[2].id, at(2026, 10, 13, 9), london)
        val tomorrow = StackEngine(state, londonClock()).todaySummary(at(2026, 10, 14, 9))
        assertEquals(listOf("Finasteride"), tomorrow.notDue.map { it.item.name }, "taken today, so not due tomorrow")
        assertEquals(
            4,
            engine.todaySummary(at(2026, 10, 13, 9)).due.size,
            "a Tuesday: D3, Fish Oil, Finasteride and Grandma's Tonic; Lion's Mane is Mon Wed Fri",
        )
        assertEquals(listOf("Daily", "Every other day", "Weekly", "2x daily", "3x daily", "Days"), FrequencyChoice.entries.map { it.title })
    }

    @Test
    fun testWeeklyIsOneDayAndTheGLP1ChipsStartOnIt() {
        val thursday = 5
        val drafts = AddPlan.drafts(
            selected = listOf("Semaglutide", "Tirzepatide", "Birth Control", "Zinc"),
            extras = listOf("Mounjaro"), choices = mapOf("Zinc" to FrequencyChoice.WEEKLY), days = emptyMap(),
            weekly = mapOf("Tirzepatide" to 2), weekday = thursday,
        )
        assertEquals(
            listOf(
                Frequency.Weekdays(setOf(5)), Frequency.Weekdays(setOf(2)), Frequency.Daily(1), Frequency.Weekdays(setOf(5)),
                Frequency.Weekdays(setOf(5)),
            ),
            drafts.map { it.frequency },
            "Weekly starts on the day being lived until another day is tapped; Birth control is daily",
        )
        assertEquals(listOf("SEM", "TRZ", "BCP", "ZNC", "TRZ"), drafts.map { it.code }, "a brand typed in full keeps the code")

        val oral = AddPlan.drafts(listOf("Semaglutide"), emptyList(), mapOf("Semaglutide" to FrequencyChoice.DAILY), emptyMap(), weekday = thursday)
        assertEquals(listOf<Frequency>(Frequency.Daily(1)), oral.map { it.frequency }, "oral semaglutide is one switch to Daily")

        assertEquals(FrequencyChoice.WEEKLY, AddPlan.defaultChoice("semaglutide"))
        assertEquals(FrequencyChoice.WEEKLY, AddPlan.defaultChoice("Zepbound"))
        assertEquals(FrequencyChoice.DAILY, AddPlan.defaultChoice("Birth Control"))
        assertEquals(FrequencyChoice.DAILY, AddPlan.defaultChoice("Lion's Mane"))

        assertEquals(FrequencyChoice.WEEKLY, FrequencyChoice.of(Frequency.Weekdays(setOf(5))), "a one-day set reads back as Weekly")
        assertEquals(FrequencyChoice.DAYS, FrequencyChoice.of(Frequency.Weekdays(setOf(2, 4, 6))))
        assertEquals(FrequencyChoice.DAYS, FrequencyChoice.of(Frequency.Weekdays(emptySet())))
        assertEquals(Frequency.Weekdays(setOf(1)), FrequencyChoice.WEEKLY.frequency(setOf(2, 3), weekday = 1), "Sunday is 1")
        assertEquals(Frequency.Weekdays(setOf(7)), FrequencyChoice.WEEKLY.frequency(emptySet(), weekday = 12))
        assertEquals(Frequency.Weekdays(setOf(3)), FrequencyChoice.DAYS.frequency(setOf(3), weekday = 5))
    }

    @Test
    fun testAWeeklyItemKeepsTheFileFormat() {
        val shot = makeItem("Tirzepatide", "TRZ", Frequency.Weekdays(setOf(5)), created = at(2026, 10, 1, 8))
        val text = StackCodec.encode(StackState(items = listOf(shot)))
        assertTrue(text.contains("\"kind\":\"weekdays\""), text)
        assertTrue(text.contains("\"days\":[5]"), text)
        assertEquals(Frequency.Weekdays(setOf(5)), StackCodec.decode(text).items.firstOrNull()?.frequency)
    }

    @Test
    fun testSuggestionRowsFitUnderThePinnedField() {
        // A small phone with the keyboard up leaves about 230 dp under the field: four 48 dp rows.
        assertEquals(4, AddPlan.rowCapacity(available = 230f, rowHeight = 48f))
        assertEquals(1, AddPlan.rowCapacity(available = 48f, rowHeight = 48f))
        assertEquals(0, AddPlan.rowCapacity(available = 47f, rowHeight = 48f))
        assertEquals(2, AddPlan.rowCapacity(available = 230f, rowHeight = 96f), "large text: fewer rows, never a scroll")
        assertEquals(0, AddPlan.rowCapacity(available = -20f, rowHeight = 48f))
    }

    @Test
    fun testTheAddSheetCopyKeepsTheRules() {
        val lines = AddCopy.all + listOf(
            Fmt.frequency(Frequency.Weekdays(setOf(5))), Fmt.notDue(Frequency.Weekdays(setOf(5)), "Next: Thursday"),
        )
        for (text in lines) assertCopyRules(text)
        assertEquals("Search or type a name", AddCopy.FIELD_PROMPT)
        assertEquals("Add “Lion's Mane”", AddCopy.literal("Lion's Mane"))
        assertEquals("No suggestions", AddCopy.suggestions(0))
        assertEquals("1 suggestion", AddCopy.suggestions(1))
        assertEquals("3 suggestions", AddCopy.suggestions(3))
    }

    /** The add-search capture types "tum": Turmeric, and no medicine name, in the screenshot. */
    @Test
    fun testTheAddSearchScreenOpensTypeModeWithTum() {
        assertEquals("tum", DemoStack.STANDARD.typedQuery)
        assertEquals("Turmeric", Suggest.rank(DemoStack.STANDARD.typedQuery).firstOrNull()?.entry?.name, "no drug name in the screenshot")
    }

    // MARK: Profile

    @Test
    fun testTheProfileIsOptionalAndLocal() {
        assertNull(Profile().initials, "no name, the person glyph")
        assertEquals("TB", Profile(name = "Thomas Baxter").initials)
        assertEquals("T", Profile(name = "tom").initials)
        assertEquals("MC", Profile(name = "Mary Ann de la Cruz").initials)
        assertEquals("Thomas Baxter", Profile.clean("  Thomas \n  Baxter  "))
        assertEquals(Profile.MAX_NAME_LENGTH, Profile.clean("a".repeat(90)).length)

        assertEquals(Profile(name = "Thomas Baxter"), ProfileCodec.decode(ProfileCodec.encode(Profile(name = "Thomas Baxter"))))
        assertEquals(Profile(), ProfileCodec.decode("""{"name":7}"""), "an unreadable name reads as none")
        assertEquals(Profile(), ProfileCodec.decode("{}"))
    }
}
