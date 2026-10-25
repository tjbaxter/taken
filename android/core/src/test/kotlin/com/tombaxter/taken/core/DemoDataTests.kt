package com.tombaxter.taken.core

import com.tombaxter.taken.core.catalog.Suggest
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.demo.DemoData
import com.tombaxter.taken.core.demo.DemoStack
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.stack.StackEngine
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/DemoDataTests.swift (adapted: the arguments are a debug-only list, as on the iPhone): the store
 * sets' demo stacks, the same demo sets Android's screenshot tests read.
 */
class DemoDataTests {

    private val prescriptionOnly = listOf(
        "Finasteride", "Metformin", "Semaglutide", "Oral Semaglutide", "Tirzepatide", "Birth Control", "Minoxidil", "Melatonin",
    )
    private val brands = listOf("Ozempic", "Wegovy", "Rybelsus", "Mounjaro", "Zepbound", "Propecia", "Proscar")

    /** Wednesday 21 October 2026 at 10:00 in London, the day this was written. */
    private val real = at(2026, 10, 21, 10)

    private fun demo(stack: DemoStack, allTaken: Boolean = false): Pair<StackState, Instant> {
        val now = DemoData.referenceNow(real, london, stack)
        return DemoData.state(now, allTaken = allTaken, zone = london, stack = stack) to now
    }

    private fun clock(state: StackState) = DayClock(state.settings.dayStartHour, london)

    @Test
    fun testTheArgumentPicksTheStackAndAnythingElseIsTheStandardOne() {
        assertEquals(DemoStack.US, DemoStack.fromArguments(listOf("Taken", "-demo", "-demo-stack", "us")))
        assertEquals(DemoStack.NEUTRAL, DemoStack.fromArguments(listOf("Taken", "-demo", "-demo-stack", "neutral", "-screen", "today")))
        assertEquals(DemoStack.STANDARD, DemoStack.fromArguments(listOf("Taken", "-demo", "-screen", "today")))
        assertEquals(DemoStack.STANDARD, DemoStack.fromArguments(listOf("Taken", "-demo", "-demo-stack", "uk")), "an unknown set")
        assertEquals(DemoStack.STANDARD, DemoStack.fromArguments(listOf("Taken", "-demo", "-demo-stack")), "no value")
    }

    @Test
    fun testEveryOtherCaptureKeepsItsStackAndItsDay() {
        val (state, now) = demo(DemoStack.STANDARD)
        assertEquals(listOf("Vitamin D3", "Finasteride", "Fish Oil", "Creatine", "Magnesium", "Zinc"), state.items.map { it.name })
        assertEquals((0 until 6).toList(), state.items.map { it.sortIndex })
        assertEquals(at(2026, 10, 21, 21, 41), now, "today at 21:41, as before")
    }

    @Test
    fun testTheStoreSetsLiveOnTheMostRecentThursdayAtTwentyOneFortyOne() {
        // Thursday 15 to Wednesday 21 October 2026: each goes back to the Thursday on or before it.
        for (day in 15..21) {
            for (stack in listOf(DemoStack.US, DemoStack.NEUTRAL)) {
                val now = DemoData.referenceNow(at(2026, 10, day, 9), london, stack)
                assertEquals(at(2026, 10, 15, 21, 41), now, "$day October, $stack")
            }
        }
        // Across the clocks going back (Sunday 25 October 2026 in London), the evening stays 21:41.
        val after = DemoData.referenceNow(at(2026, 10, 28, 9), london, DemoStack.US)
        assertEquals(at(2026, 10, 22, 21, 41), after)
        assertEquals(java.time.DayOfWeek.THURSDAY, after.atZone(london).dayOfWeek)
    }

    @Test
    fun testTheUSStackIsMixedWithASemaglutideRowWeeklyOnThursday() {
        val (state, now) = demo(DemoStack.US)
        assertEquals(
            listOf("Vitamin D3", "Finasteride", "Semaglutide", "Fish Oil", "Creatine", "Magnesium", "Zinc"),
            state.items.map { it.name },
        )
        assertEquals((0 until 7).toList(), state.items.map { it.sortIndex })
        val sem = assertNotNull(state.items.firstOrNull { it.name == "Semaglutide" })
        assertEquals("SEM", sem.code, "the catalog's code")
        assertEquals("Weekly · Thu", Fmt.frequency(sem.frequency))

        val today = StackEngine(state, clock(state)).todaySummary(now)
        val row = assertNotNull(today.items.firstOrNull { it.item.id == sem.id })
        assertTrue(row.isDue, "due on its day, in the Stack")
        assertEquals(1, row.doses.size, "taken that morning")
        assertEquals(5, today.takenDueDoses)
        assertEquals(7, today.dueDoses, "Vitamin D3, Finasteride, Semaglutide, Fish Oil twice, Creatine, Magnesium")
    }

    @Test
    fun testTheNeutralStackHasAWeeklyShotAndNoPrescriptionOnlyMedicine() {
        val (state, now) = demo(DemoStack.NEUTRAL, allTaken = true)
        assertEquals(listOf("Vitamin D3", "Weekly shot", "Fish Oil", "Creatine", "Magnesium", "Zinc"), state.items.map { it.name })
        for (name in prescriptionOnly + brands) {
            assertFalse(state.items.any { it.name.lowercase().contains(name.lowercase()) }, name)
        }
        val ids = state.items.map { it.id }.toSet()
        assertTrue(state.doses.all { ids.contains(it.itemId) }, "no dose of an item it does not have")

        val shot = assertNotNull(state.items.firstOrNull { it.name == "Weekly shot" })
        assertEquals("Weekly · Thu", Fmt.frequency(shot.frequency))
        val today = StackEngine(state, clock(state)).todaySummary(now)
        assertEquals(6, today.dueDoses)
        assertTrue(today.allTaken, "today-done: everything taken")
    }

    @Test
    fun testTheWeeklyRowIsLoggedEveryWeekSoTheRecordStaysWhole() {
        for (stack in listOf(DemoStack.US, DemoStack.NEUTRAL)) {
            val (state, now) = demo(stack)
            val weekly = assertNotNull(state.items.firstOrNull { it.name == stack.weeklyName })
            val engine = StackEngine(state, clock(state))
            val today = engine.todaySummary(now).day
            for (week in 1..8) {
                val row = assertNotNull(engine.summary(today.adding(-7 * week), asOf = today).items.firstOrNull { it.item.id == weekly.id })
                assertTrue(row.isDue, "$stack week $week")
                assertEquals(1, row.doses.size, "$stack week $week")
            }
            // The weekly row never changes the streak the other rows make.
            val (standard, standardNow) = demo(DemoStack.STANDARD)
            val standardEngine = StackEngine(standard, clock(standard))
            assertEquals(standardEngine.streak(standardEngine.todaySummary(standardNow).day), engine.streak(today), "$stack")
        }
    }

    @Test
    fun testTheOtherRowsKeepTheirHistoryInEveryStack() {
        val now = DemoData.referenceNow(real, london, DemoStack.US)
        fun times(stack: DemoStack): Map<String, List<Instant>> {
            val state = DemoData.state(now, allTaken = false, zone = london, stack = stack)
            val byName = LinkedHashMap<String, MutableList<Instant>>()
            for (dose in state.doses) {
                val item = state.items.firstOrNull { it.id == dose.itemId } ?: continue
                byName.getOrPut(item.name) { mutableListOf() }.add(dose.takenAt)
            }
            return byName
        }
        val standard = times(DemoStack.STANDARD)
        for (stack in listOf(DemoStack.US, DemoStack.NEUTRAL)) {
            val other = times(stack)
            for (name in listOf("Vitamin D3", "Fish Oil", "Creatine", "Magnesium", "Zinc")) {
                assertEquals(standard[name], other[name], "$stack: $name")
            }
        }
    }

    @Test
    fun testTheNeutralTypeAheadFillsTheRoomWithSupplementsOnly() {
        assertEquals("tum", DemoStack.STANDARD.typedQuery)
        assertEquals("tum", DemoStack.US.typedQuery)
        assertEquals("mag", DemoStack.NEUTRAL.typedQuery)

        val matches = Suggest.rank("mag")
        assertEquals(listOf("Magnesium", "Magnesium Glycinate", "Magnesium Citrate", "Magnesium L-Threonate"), matches.map { it.entry.name })
        assertTrue(matches.all { it.alias == null }, "no other name, so no brand, shows")
        val rows = Suggest.rows(matches, literal = Suggest.literal("mag"), capacity = 6)
        assertEquals(5, rows.size, "four names and the typed row: the most the card shows")
    }

    /** The seeded generator is the iPhone's LCG, so the demo history matches it draw for draw. */
    @Test
    fun testTheSeededRandomIsTheIPhonesGenerator() {
        val random = com.tombaxter.taken.core.demo.SeededRandom(1L)
        // state = 1 × 6364136223846793005 + 1442695040888963407 = 7806831264735756412; >> 33 = 908834774.
        assertEquals(908_834_774L, random.next())
        assertEquals(1_093_944_153L, random.next(), "the multiply wraps at 64 bits, as Swift's &* does")
        assertEquals(1_392_341_196L, random.next())
        val demo = com.tombaxter.taken.core.demo.SeededRandom(0x7A4E_2026L)
        assertEquals(listOf(897_645_561L, 548_693_115L, 1_312_308_595L), List(3) { demo.next() }, "the demo stack's seed")
    }
}
