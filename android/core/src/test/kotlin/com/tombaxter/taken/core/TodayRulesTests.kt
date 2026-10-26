package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.demo.DemoData
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.stack.ItemDay
import com.tombaxter.taken.core.stack.ProgressCopy
import com.tombaxter.taken.core.stack.RowSpeech
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.TodayRules
import com.tombaxter.taken.core.stack.logDose
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * The pure half of TakenTests/TodayRowTests.swift (`feat/tap-row-to-log`): what a tap anywhere on a row does, and what
 * TalkBack says it does. The demo stack: Vitamin D3 taken at 07:42, Fish Oil 1 of 2 (2x daily), Magnesium pending, and
 * Zinc (every other day, taken yesterday) under Not today. The tap's effects (the moment, the toast, edit mode's end)
 * run through Android's AppModel in :app's TodayRowTests.
 */
class TodayRulesTests {

    private val now: Instant = DemoData.referenceNow(at(2026, 10, 21, 10), london)
    private val state: StackState = DemoData.state(now, allTaken = false, zone = london)
    private val clock = DayClock(state.settings.dayStartHour, london)
    private val engine = StackEngine(state, clock)
    private val today = engine.todaySummary(now)

    private fun row(name: String): ItemDay = assertNotNull(today.items.firstOrNull { it.item.name == name })

    @Test
    fun testATapLogsWhilePendingAndShowsTheTimesOnceTaken() {
        val fish = row("Fish Oil")
        assertTrue(fish.isPending)
        assertEquals(1, fish.takenCount, "2x daily, the morning dose taken")
        assertEquals(TodayRules.Tap.LOG, TodayRules.tap(fish, editing = false))
        assertEquals(TodayRules.Tap.LOG, TodayRules.tap(row("Magnesium"), editing = false))
        val vd3 = row("Vitamin D3")
        assertFalse(vd3.isPending)
        assertEquals(TodayRules.Tap.SHOW_TIMES, TodayRules.tap(vd3, editing = false), "never un-takes and never logs a second dose")
    }

    @Test
    fun testANotTodayRowLogsTheSameWay() {
        val entry = assertNotNull(today.notDue.firstOrNull { it.item.name == "Zinc" })
        val shown = TodayRules.notTodayRow(engine, entry, today.day)
        assertTrue(shown.row.doses.isEmpty(), "a quiet ring")
        assertEquals("Every other day · Next: tomorrow", shown.note)
        assertEquals(TodayRules.Tap.LOG, TodayRules.tap(shown.row, editing = false), "no lockout")
    }

    @Test
    fun testEditModeOpensTheItemAndNeverLogs() {
        for (item in today.items) {
            assertEquals(TodayRules.Tap.OPEN_ITEM, TodayRules.tap(item, editing = true), item.item.name)
        }
        assertTrue(TodayRules.showsTakeAll(count = 2, editing = false))
        assertFalse(TodayRules.showsTakeAll(count = 2, editing = true), "Take all steps aside while editing")
        assertFalse(TodayRules.showsTakeAll(count = 1, editing = false), "one row is its own tap")
    }

    @Test
    fun testTakeAllCountsWhatItLogs() {
        // Fish Oil was logged at 07:43 and Magnesium is pending: at 21:41 both may be quick logged.
        assertEquals(2, TodayRules.takeAllCount(engine, today, now))
        // Within the hour of a tap on Fish Oil it is held back from Take all, never from its own row.
        val tapped = state.clone()
        tapped.logDose(row("Fish Oil").item.id, now.minusSeconds(60), london)
        val tappedEngine = StackEngine(tapped, clock)
        assertEquals(1, TodayRules.takeAllCount(tappedEngine, tappedEngine.todaySummary(now), now))
    }

    @Test
    fun testTheRowSaysWhatItIs() {
        assertEquals("Daily", TodayRules.subtitle(row("Vitamin D3"), note = null))
        assertEquals("2x daily · 1 of 2", TodayRules.subtitle(row("Fish Oil"), note = null))
        val lines = TodayRules.timeLines(row("Vitamin D3"), today.day, clock, now)
        assertEquals(listOf(TodayRules.TimeLine("Taken at", "07:42", "· 13h 59m ago")), lines)
        assertEquals("Vitamin D3, taken at 7:42 AM.", RowSpeech.label(row("Vitamin D3"), today.day, clock, nextLabel = null, locale = enUS))
        assertEquals("Fish Oil, 1 of 2 taken, at 7:43 AM. Pending.", RowSpeech.label(row("Fish Oil"), today.day, clock, nextLabel = null, locale = enUS))
        assertEquals("Magnesium, pending.", RowSpeech.label(row("Magnesium"), today.day, clock, nextLabel = null, locale = enUS))
        assertEquals("4 of 6 doses taken today. 2 pending.", ProgressCopy.spoken(today))
        assertEquals("07:44", ProgressCopy.lastTime(today, clock))
    }

    /** TodayRowTests.testVoiceOverHintsSayWhatADoubleTapDoes, word for word, and Android's click labels. */
    @Test
    fun testTalkBackHintsSayWhatADoubleTapDoes() {
        val fish = row("Fish Oil")
        val vd3 = row("Vitamin D3")
        val hints = listOf(
            RowSpeech.hint(fish, quiet = false, locked = false),
            RowSpeech.hint(vd3, quiet = false, locked = false),
            RowSpeech.hint(fish, quiet = false, locked = true),
            RowSpeech.hint(fish, quiet = false, locked = false, editing = true),
            RowSpeech.hint(vd3, quiet = false, locked = true, editing = true),
        )
        assertEquals(
            listOf(
                "Double tap to mark taken.",
                "Double tap for the times. Actions has Edit item.",
                "Logging needs Taken Pro. Double tap to see plans.",
                "Double tap to edit.",
                "Double tap to edit.",
            ),
            hints,
        )
        for (hint in hints) {
            assertCopyRules(hint)
            assertFalse(hint.lowercase().contains("name"), "nothing points at the name: $hint")
        }
        assertEquals("Log Fish Oil", RowSpeech.clickLabel(fish, quiet = false, locked = false, editing = false))
        assertEquals("Show times", RowSpeech.clickLabel(vd3, quiet = false, locked = false, editing = false))
        assertEquals("See Taken Pro plans", RowSpeech.clickLabel(fish, quiet = false, locked = true, editing = false))
        assertEquals("Edit Vitamin D3", RowSpeech.clickLabel(vd3, quiet = false, locked = true, editing = true))
    }

    @Test
    fun testSetTimeIsOfferedForTodaysDose() {
        val vd3 = row("Vitamin D3")
        assertTrue(TodayRules.offersSetTime(vd3, today.day, clock), "logged today: Set time corrects it")
        assertTrue(TodayRules.offersSetTime(row("Magnesium"), today.day, clock), "nothing yet: Set time logs one")
        val dose = assertNotNull(TodayRules.setTimeDose(state, vd3.item, today.day, clock))
        assertEquals("07:42", com.tombaxter.taken.core.format.Fmt.clock(dose.takenAt, clock))
    }
}
