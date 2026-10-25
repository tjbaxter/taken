package com.tombaxter.taken

import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.stack.ItemDay
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.data.MemoryPersistence
import com.tombaxter.taken.data.Persistence
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/TodayRowTests.swift (`feat/tap-row-to-log`), run through Android's AppModel: a tap anywhere on a
 * Today row does what the ring alone did, the logging moment plays on the row that was tapped, and editing lives in the
 * stack's edit mode (the pencil), out of the tap's way. The demo stack: Vitamin D3 taken at 07:42, Fish Oil 1 of 2,
 * Magnesium pending, and Zinc (every other day, taken yesterday) under Not today.
 */
@RunWith(RobolectricTestRunner::class)
class TodayRowTests {

    private fun demoModel(screen: String = "today"): AppModel = DemoScreens.make(screen)

    private fun row(name: String, model: AppModel): ItemDay = assertNotNull(model.today.items.firstOrNull { it.item.name == name })

    // MARK: The tap

    @Test
    fun testATapOnAPendingRowLogsADoseAndPlaysTheMomentOnThatRowOnly() {
        val model = demoModel()
        val fish = row("Fish Oil", model)
        assertTrue(fish.isPending)
        assertEquals(1, fish.takenCount, "2x daily, the morning dose taken")
        model.tap(fish)

        val after = row("Fish Oil", model)
        assertEquals(2, after.takenCount, "the tap fills the second arc")
        assertFalse(after.isPending)
        assertEquals("Fish Oil taken at", model.toast?.message, "the toast with Undo, as the ring had")
        assertNotNull(model.toast?.undo)
        assertEquals(mapOf(fish.item.id to 1), model.rowLogs, "the ring lifts and the row washes here, and nowhere else")

        val magnesium = row("Magnesium", model)
        model.tap(magnesium)
        assertEquals(mapOf(fish.item.id to 1, magnesium.item.id to 1), model.rowLogs, "each row plays its own moment")
        model.tap(row("Magnesium", model))
        assertEquals(1, model.rowLogs[magnesium.item.id], "a tap on it now shows the times, with no moment")
    }

    @Test
    fun testATapOnATakenRowShowsItsTimesAndNeverUntakes() {
        val model = demoModel()
        val vd3 = row("Vitamin D3", model)
        assertFalse(vd3.isPending)
        val doses = model.state.doses
        model.tap(vd3)
        assertEquals(vd3.item.id, model.expandedItemId, "the times open")
        assertEquals(doses, model.state.doses, "never un-takes and never logs a second dose")
        assertTrue(model.rowLogs.isEmpty(), "no logging moment for showing the times")
        model.tap(vd3)
        assertNull(model.expandedItemId, "a second tap closes them")
    }

    @Test
    fun testANotTodayRowLogsTheSameWay() {
        val model = demoModel()
        val entry = assertNotNull(model.today.notDue.firstOrNull { it.item.name == "Zinc" })
        val shown = model.notTodayRow(entry)
        assertTrue(shown.row.doses.isEmpty(), "a quiet ring")
        model.tap(shown.row)
        assertEquals(1, model.engine.doses(entry.item.id, model.today.day).size, "no lockout")
        assertEquals(1, model.rowLogs[entry.item.id])
    }

    @Test
    fun testTakeAllPlaysNoRowMoment() {
        val model = demoModel()
        model.takeAll()
        assertFalse(row("Magnesium", model).isPending)
        assertTrue(model.rowLogs.isEmpty(), "the moment plays where the finger is: Take all has its own toast")
        assertEquals("2 taken at", model.toast?.message)
    }

    @Test
    fun testALockedRowOpensThePaywallInsteadOfLogging() {
        val model = demoModel("locked")
        assertTrue(model.isLocked)
        val magnesium = row("Magnesium", model)
        val doses = model.state.doses
        model.tap(magnesium)
        assertNotNull(model.paywall, "as the ring did")
        assertEquals(doses, model.state.doses)
        assertTrue(model.rowLogs.isEmpty())

        model.closePaywall()
        model.setEditingStack(true)
        model.tap(magnesium)
        assertEquals(Sheet.EditItem(magnesium.item.id), model.sheet, "the item sheet always opens, Pro or not")
        assertNull(model.paywall)
    }

    // MARK: Edit mode

    @Test
    fun testEditModeOpensTheItemSheetAndNeverLogs() {
        val model = demoModel()
        assertFalse(model.editingStack, "Today opens logging")
        val vd3 = row("Vitamin D3", model)
        model.tap(vd3)
        model.setEditingStack(true)
        assertTrue(model.editingStack)
        assertNull(model.expandedItemId, "editing closes the times, so every row shows its chevron")

        val fish = row("Fish Oil", model)
        val doses = model.state.doses
        model.tap(fish)
        assertEquals(Sheet.EditItem(fish.item.id), model.sheet)
        assertEquals(doses, model.state.doses, "nothing logs while editing")
        assertNull(model.toast)
        assertTrue(model.rowLogs.isEmpty())

        model.sheet = null
        assertTrue(model.editingStack, "closing the sheet keeps edit mode, so the next item is one tap away")
        model.setEditingStack(false)
        model.tap(fish)
        assertEquals(fish.takenCount + 1, row("Fish Oil", model).takenCount, "Done: a tap logs again")
    }

    @Test
    fun testEditModeEndsOnLeavingTodayInTheBackgroundOnBackAndWhenTheStackEmpties() {
        val model = demoModel()
        model.setEditingStack(true)
        model.tab = AppTab.TODAY
        assertTrue(model.editingStack, "Today's own tab keeps it")
        model.tab = AppTab.HISTORY
        assertFalse(model.editingStack)
        model.tab = AppTab.TODAY
        assertFalse(model.editingStack, "coming back finds the rows logging")

        model.setEditingStack(true)
        assertTrue(model.backOnTabs(), "Android's back ends edit mode first")
        assertFalse(model.editingStack)
        assertFalse(model.backOnTabs(), "then back leaves the app from Today, the start destination")

        model.setEditingStack(true)
        model.didEnterBackground()
        assertFalse(model.editingStack, "the next open is a tap that logs")

        model.setEditingStack(true)
        for (item in model.activeItems) model.deleteItem(item.id)
        assertFalse(model.hasStack)
        assertFalse(model.editingStack, "first run has nothing to edit")
    }

    @Test
    fun testTheTodayEditScreenOpensTodayInEditMode() {
        val model = demoModel("today-edit")
        assertEquals(AppTab.TODAY, model.tab)
        assertTrue(model.editingStack)
        assertFalse(demoModel("today").editingStack, "every other capture shows Today logging")
    }

    // MARK: Undo, Set time and the toast

    @Test
    fun testUndoOnTheToastRemovesTheDoseAndUndoLastDosePutsItBack() {
        val model = demoModel()
        val fish = row("Fish Oil", model)
        model.tap(fish)
        val toast = assertNotNull(model.toast)
        model.undo(toast)
        assertEquals(1, row("Fish Oil", model).takenCount, "the toast's Undo removes that dose")
        assertNull(model.toast)

        val vd3 = row("Vitamin D3", model)
        model.undoLastDose(vd3)
        assertEquals("Vitamin D3: last dose removed", model.toast?.message)
        assertTrue(row("Vitamin D3", model).isPending)
        model.undo(assertNotNull(model.toast))
        assertEquals("07:42", com.tombaxter.taken.core.format.Fmt.clock(assertNotNull(row("Vitamin D3", model).lastDose).takenAt, model.clock), "back with its original time")
    }

    @Test
    fun testSetTimeCorrectsTodaysDoseAndNeverUsesATimeStillToCome() {
        val model = demoModel()
        val vd3 = row("Vitamin D3", model).item
        model.setTime(vd3, 7, 5)
        assertEquals("Vitamin D3 set to", model.toast?.message)
        assertEquals("07:05", model.toast?.time)
        val before = model.state.doses
        model.setTime(vd3, 23, 30)
        assertEquals(before, model.state.doses, "21:41 now: 23:30 is still to come and is never used")
        val magnesium = row("Magnesium", model).item
        model.setTime(magnesium, 21, 0)
        assertEquals("Magnesium taken at", model.toast?.message, "no dose yet: Set time logs one")
    }

    /** WeeklyWeekTests.testATapOnTheRingLogsAnEarlyDoseFromToday, through AppModel: Thu 15 logged, a tap on Tue 20. */
    @Test
    fun testATapOnTheRowLogsAnEarlyDoseFromToday() {
        val zone = ZoneId.of("Europe/London")
        fun local(day: Int, hour: Int, minute: Int = 0) = ZonedDateTime.of(2026, 10, day, hour, minute, 0, 0, zone).toInstant()
        val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = local(1, 9), sortIndex = 0)
        val sem = Item(name = "Semaglutide", code = "SEM", frequency = Frequency.Weekdays(setOf(5)), createdAt = local(1, 9), sortIndex = 1)
        val state = StackState(items = listOf(vd3, sem))
        state.logDose(sem.id, local(8, 9), zone)
        state.logDose(sem.id, local(15, 9), zone)
        val now = local(20, 10, 30)
        val model = model(state, now, zone)

        val entry = assertNotNull(model.today.notDue.firstOrNull { it.item.id == sem.id })
        val shown = model.notTodayRow(entry)
        assertEquals(DayKey(2026, 10, 20), shown.row.day, "today's row, not last Thursday's")
        assertTrue(shown.row.doses.isEmpty(), "a quiet ring")
        assertEquals("Weekly · Next: Thursday", shown.note)
        model.tap(shown.row)

        val thu22 = DayKey(2026, 10, 22)
        assertEquals(listOf(now), model.engine.doses(sem.id, thu22).map { it.takenAt }, "it counts for Thu 22")
        val after = model.notTodayRow(assertNotNull(model.today.notDue.firstOrNull { it.item.id == sem.id }))
        assertEquals(thu22, after.row.day)
        assertEquals("Weekly · Counts for Thursday", after.note)
        assertTrue(model.offersSetTime(after.row), "logged today: Set time corrects it")
        assertEquals("Semaglutide taken at", model.toast?.message)
    }

    // MARK: Today's one-time rows in demo captures (RetentionTests.testDemoShowsAOneTimeRowOnlyWhenItsScreenAsks)

    @Test
    fun testDemoShowsAOneTimeRowOnlyWhenItsScreenAsks() {
        for (screen in listOf("today", "today-done", "locked")) {
            assertNull(demoModel(screen).todayPrompt, "no one-time row in the $screen capture")
        }
        val offer = demoModel("today-nudge-offer")
        assertEquals(TodayPrompt.NudgeOffer(20 * 60), offer.todayPrompt)
        offer.answerNudgeOffer(turnOn = false)
        assertNull(offer.todayPrompt, "Not now hides it")
        assertTrue(offer.settings.nudgeOfferDone)

        val repair = demoModel("today-repair")
        assertEquals(TodayPrompt.Repair(repair.today.day.adding(-1)), repair.todayPrompt)
        assertEquals(repair.today.day.adding(-1), repair.repairDay, "the demo's yesterday is partial")
        repair.closeRepair(repair.today.day.adding(-1))
        assertNull(repair.todayPrompt, "its close hides it")
    }

    /**
     * With Reminders (NEXT 3) this build can post the nudge, so Today offers it right after the stack is added, until it
     * is answered (RetentionTests.testTheNudgeOfferShowsRightAfterTheStackIsAddedUntilItIsAnswered, through the model).
     */
    @Test
    fun testTodayOffersTheNudgeOnceThisBuildCanSendIt() {
        val zone = ZoneId.of("Europe/London")
        val now = ZonedDateTime.of(2026, 10, 21, 9, 0, 0, 0, zone).toInstant()
        val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = now.minusSeconds(86_400), sortIndex = 0)
        val model = model(StackState(items = listOf(vd3)), now, zone)
        assertTrue(AppModel.NUDGE_AVAILABLE)
        assertFalse(model.settings.reminderEnabled)
        assertFalse(model.settings.nudgeOfferDone, "a new stack, the offer never answered")
        assertEquals(TodayPrompt.NudgeOffer(20 * 60), model.todayPrompt, "Nudge me at 20:00 if anything's left")
        model.answerNudgeOffer(turnOn = false)
        assertNull(model.todayPrompt, "answered, it never comes back")
        assertTrue(model.settings.nudgeOfferDone)
        assertFalse(model.settings.reminderEnabled)
    }

    // MARK: Saving

    /**
     * A save that fails puts the row back to what the file holds, as on the iPhone, where a failed write never reaches the
     * screen; a write replayed onto a file that moved on keeps the dose id the toast's Undo holds.
     */
    @Test
    fun testAFailedSaveLeavesTheRowPendingAndAReplayKeepsItsDoseId() {
        val zone = ZoneId.of("Europe/London")
        val now = ZonedDateTime.of(2026, 10, 21, 9, 0, 0, 0, zone).toInstant()
        val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = now.minusSeconds(86_400), sortIndex = 0)
        val fish = Item(name = "Fish Oil", code = "FSH", frequency = Frequency.Daily(1), createdAt = now.minusSeconds(86_400), sortIndex = 1)
        val file = FlakyFile(StackState(items = listOf(vd3, fish)))
        val model = AppModel(
            file, file.stack, ProLedger(firstSeenAt = now), Profile(), null, ProSource.untilBilling,
            clockNow = { now }, zone = { zone }, locale = { Locale.US },
        )

        file.failNext = true
        model.tap(row("Vitamin D3", model))
        assertFalse(row("Vitamin D3", model).isPending, "the ring fills at once")
        file.finish()
        assertEquals("Could not save. Try again.", model.toast?.message)
        assertTrue(row("Vitamin D3", model).isPending, "nothing was saved, so the row is pending again and a tap logs it")
        assertTrue(file.stack.doses.isEmpty())
        assertNull(model.ledger?.firstDoseAt, "a dose that never reached the file is not the first dose")

        // Meanwhile another surface logged Fish Oil: the next tap's write is replayed onto that file.
        file.stack = file.stack.clone().also { it.logDose(fish.id, now.minusSeconds(60), zone) }
        model.tap(row("Vitamin D3", model))
        val toast = assertNotNull(model.toast)
        val undo = assertIs<UndoStep.Remove>(toast.undo)
        assertEquals(undo.ids, file.stack.doses.filter { it.itemId == vd3.id }.map { it.id }.toSet(), "the file has the id Undo holds")
        assertEquals(file.stack, model.state, "the screen ends on the file, Fish Oil included")
        assertFalse(row("Fish Oil", model).isPending)

        model.undo(toast)
        assertTrue(file.stack.doses.none { it.itemId == vd3.id }, "Undo removes the dose from the file too")
        assertTrue(row("Vitamin D3", model).isPending)
    }

    // MARK: Add, erase and links

    @Test
    fun testAddingItemsSaysWhatWasAdded() {
        val model = demoModel("empty")
        model.addItems(listOf(com.tombaxter.taken.core.model.ItemDraft("Creatine")))
        assertEquals("Creatine added", model.toast?.message)
        model.addItems(listOf(com.tombaxter.taken.core.model.ItemDraft("Zinc"), com.tombaxter.taken.core.model.ItemDraft("Iron")))
        assertEquals("2 added to your stack", model.toast?.message)
        assertEquals(listOf("CRE", "ZNC", "IRN"), model.activeItems.map { it.code })
        assertEquals("ZNC", Catalog.code("Zinc"))
    }

    @Test
    fun testEraseSaysWhatItTakesAndKeepsTheLook() {
        assertTrue(AppModel.ERASE_MESSAGE.contains("to-dos"), "the to-dos go too, so the dialog says so")
        assertTrue(AppModel.ERASE_MESSAGE.contains("profile"))
        assertTrue(AppModel.ERASE_MESSAGE.contains("this phone"), "Android wording")
        val model = DemoScreens.make("today", look = com.tombaxter.taken.core.theme.ThemeID.ICE)
        model.eraseAll()
        assertFalse(model.hasStack)
        assertTrue(model.state.doses.isEmpty())
        assertEquals(com.tombaxter.taken.core.theme.ThemeID.ICE, model.theme, "the look stays")
        assertEquals(Profile(), model.profile)
        assertNotNull(model.ledger?.firstDoseAt, "pro.json stays: the first session never reopens")
    }

    @Test
    fun testLinksBringTodayForwardAndOpenThePaywallWhenLocked() {
        val model = demoModel()
        model.openProfile()
        model.sheet = Sheet.Add
        model.tab = AppTab.HISTORY
        model.handle("taken://today")
        assertEquals(listOf<Route>(Route.Main), model.backStack.toList(), "Profile closes")
        assertNull(model.sheet)
        assertEquals(AppTab.TODAY, model.tab)

        model.handle("taken://pro")
        assertNull(model.paywall, "Pro on: nothing to sell")
        val locked = demoModel("locked")
        locked.handle("taken://pro?then=take-all")
        assertEquals(PaywallOrigin.LINK, locked.paywall?.origin)
    }

    @Test
    fun testTheFirstDoseEverIsNotedInTheLedger() {
        val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = Instant.parse("2026-10-20T08:00:00Z"), sortIndex = 0)
        val now = Instant.parse("2026-10-21T08:00:00Z")
        val persistence = MemoryPersistence(stack = StackState(items = listOf(vd3)), ledger = ProLedger(firstSeenAt = now))
        val model = AppModel(
            persistence, persistence.stack, persistence.ledger, Profile(), null, ProSource.locked,
            clockNow = { now }, zone = { ZoneId.of("Europe/London") }, locale = { Locale.US },
        )
        model.tap(assertNotNull(model.today.items.firstOrNull()))
        assertEquals(now, persistence.ledger?.firstDoseAt, "the first dose needs no Pro, and it is remembered")
        assertEquals(1, persistence.stack.doses.size, "written to the file")
        assertTrue(model.isLocked, "after it, logging needs Pro")
    }

    /** A file that can refuse a write, as a full disk does, and answers later, as DataStore does. */
    private class FlakyFile(var stack: StackState) : Persistence {
        var failNext = false
        private var waiting: (() -> Unit)? = null

        override val busy: Boolean get() = waiting != null

        override fun saveStack(
            base: StackState,
            next: StackState,
            replay: (StackState) -> Unit,
            settled: (StackState) -> Unit,
            onFailure: () -> Unit,
        ) {
            if (failNext) {
                failNext = false
                waiting = {
                    onFailure()
                    settled(stack)
                }
                return
            }
            stack = if (stack == base) next else stack.clone().also(replay)
            settled(stack)
        }

        /** The refused write's answer arrives. */
        fun finish() {
            val answer = waiting
            waiting = null
            answer?.invoke()
        }

        override fun updateLedger(transform: (ProLedger?) -> ProLedger?) = Unit
        override fun saveProfile(profile: Profile) = Unit
        override fun savePhoto(jpeg: ByteArray?) = Unit
        override fun eraseExtras() = Unit
    }

    private fun model(state: StackState, now: Instant, zone: ZoneId): AppModel {
        val persistence = MemoryPersistence(stack = state)
        return AppModel(
            persistence, state, ProLedger(firstSeenAt = now), Profile(), null, ProSource.untilBilling,
            clockNow = { now }, zone = { zone }, locale = { Locale.US },
        )
    }
}
