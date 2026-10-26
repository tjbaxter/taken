package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.FrequencyEra
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.retention.TodayPrompts
import com.tombaxter.taken.core.stack.DaySummary
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.weight.WeighIn
import com.tombaxter.taken.core.weight.WeightCSV
import com.tombaxter.taken.core.weight.WeightChange
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightFormat
import com.tombaxter.taken.core.weight.WeightGate
import com.tombaxter.taken.core.weight.WeightImport
import com.tombaxter.taken.core.weight.WeightOffer
import com.tombaxter.taken.core.weight.WeightPoint
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightState
import com.tombaxter.taken.core.weight.WeightTicks
import com.tombaxter.taken.core.weight.WeightTrend
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.core.weight.WeightWindow
import com.tombaxter.taken.core.weight.day
import java.time.Instant
import java.util.Locale
import kotlin.math.pow
import kotlin.math.roundToLong
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/WeightTests.swift, the pure cases: the trend with worked numbers, units per locale, the Pro rule,
 * the offer on Today, the dose ticks, the chart's window, the CSV both ways and the copy. The cases that run through the
 * app model (the tab's visibility, the offer's answer, logging and Undo, editing, the visit, the demo screens, Erase) are
 * :app's WeightTests. London clock, the day starting at 04:00; Monday 19 October 2026.
 */
class WeightTests {

    private val enUS = Locale.US
    private val enGB = Locale.UK
    private val deDE = Locale.GERMANY

    private fun weighIn(kg: Double, day: Int, hour: Int = 7, minute: Int = 0, month: Int = 10): WeighIn {
        val date = at(2026, month, day, hour, minute)
        return WeighIn(kg = kg, weighedAt = date, utcOffset = london.rules.getOffset(date).totalSeconds)
    }

    private fun day(dayOfMonth: Int, month: Int = 10): DayKey = DayKey(2026, month, dayOfMonth)

    private fun assertClose(expected: Double, actual: Double?, accuracy: Double = 1e-9, message: String? = null) {
        assertNotNull(actual, message)
        assertTrue(kotlin.math.abs(expected - actual) <= accuracy, "${message ?: ""}: expected $expected, got $actual")
    }

    private fun tenth(value: Double): Double = (value * 10).roundToLong() / 10.0

    // MARK: The trend

    /**
     * Fourmilab's pencil-and-paper example, by the calculator formula: T(n) = T(n-1) + 0.1 x (W(n) - T(n-1)), starting at
     * the first weigh-in. Rounded to a tenth it is their table: 173.5, 173.3, 173.2, 173.0.
     */
    @Test
    fun testTheTrendIsTheHackersDietOnEachDaysLowestWeighIn() {
        val weighIns = listOf(
            weighIn(173.6, 1), weighIn(174.2, 1, 19), // the day's lowest counts, whenever it was
            weighIn(172.5, 2), weighIn(171.5, 3), weighIn(172.0, 4), weighIn(171.5, 5, 6, 30),
        )
        val trend = WeightTrend.trend(weighIns, londonClock())
        assertEquals((1..5).map { day(it) }, trend.map { it.day })
        val expected = listOf(173.6, 173.49, 173.291, 173.1619, 172.99571)
        for ((point, value) in trend.zip(expected)) assertClose(value, point.kg, message = point.day.iso)
        assertEquals(listOf(173.5, 173.3, 173.2, 173.0), trend.drop(1).map { tenth(it.kg) }, "Fourmilab's hand-worked trend column")
        assertEquals(173.6, WeightTrend.daily(weighIns, londonClock()).first().kg, "the lowest of the day")
    }

    /** MacroFactor: 151 on Monday and 150 on Wednesday give 150.5 on Tuesday. The trend runs through the filled day. */
    @Test
    fun testDaysBetweenWeighInsAreFilledOnAStraightLine() {
        val monday = weighIn(151.0, 19)
        val wednesday = weighIn(150.0, 21)
        val filled = WeightTrend.filled(WeightTrend.daily(listOf(wednesday, monday), londonClock()))
        assertEquals(listOf(day(19), day(20), day(21)), filled.map { it.day })
        assertClose(150.5, filled[1].kg)

        val longer = WeightTrend.filled(listOf(WeightPoint(day(1), 90.0), WeightPoint(day(5), 88.0)))
        assertEquals(listOf(90.0, 89.5, 89.0, 88.5, 88.0), longer.map { it.kg })

        val trend = WeightTrend.trend(listOf(monday, wednesday), londonClock())
        assertClose(150.95, trend.map { it.kg }[1])
        assertClose(150.855, trend.map { it.kg }[2])
    }

    /**
     * No line past the last weigh-in and no forecast; a weigh-in before the day starts at 04:00 counts for the day before,
     * as a dose does, and one logged in New York keeps its New York day.
     */
    @Test
    fun testTheTrendStopsAtTheLastWeighInAndDaysAreDayClocks() {
        val trend = WeightTrend.trend(listOf(weighIn(90.0, 1), weighIn(89.0, 4)), londonClock())
        assertEquals(day(4), trend.last().day, "nothing after the last weigh-in")
        assertEquals(4, trend.size)

        val lateNight = weighIn(88.0, 20, 2, 30)
        assertEquals(day(19), londonClock().day(lateNight), "02:30 counts for the day being lived")

        val evening = at(2026, 10, 20, 23, 30, newYork)
        val abroad = WeighIn(kg = 88.0, weighedAt = evening, utcOffset = newYork.rules.getOffset(evening).totalSeconds)
        assertEquals(day(21), londonClock().day(evening), "04:30 on the 21st in London")
        assertEquals(day(20), londonClock().day(abroad), "but 23:30 on the 20th where it was logged")
        assertTrue(WeightTrend.trend(emptyList(), londonClock()).isEmpty())
    }

    /**
     * After a 1 kg drop the trend is 89 + 0.9^n, so the 7-day change is 0.9^7 - 1. Each change shows once that much
     * history exists.
     */
    @Test
    fun testChangesAreReadOffTheTrendOnceThereIsThatMuchHistory() {
        val eight = listOf(weighIn(90.0, 1)) + (2..8).map { weighIn(89.0, it) }
        val trend = WeightTrend.trend(eight, londonClock())
        assertClose(89 + 0.9.pow(7), trend.last().kg)
        assertClose(0.9.pow(7) - 1, WeightTrend.change(trend, 7))
        assertNull(WeightTrend.change(trend, 30), "8 days of history: no 30-day change yet")
        assertEquals(listOf(7), WeightTrend.changes(trend).map { it.days })

        val month = listOf(weighIn(90.0, 1, month = 9)) + (2..30).map { weighIn(89.0, it, month = 9) } + listOf(weighIn(89.0, 1))
        val monthTrend = WeightTrend.trend(month, londonClock())
        assertClose(0.9.pow(30) - 1, WeightTrend.change(monthTrend, 30))
        assertEquals(listOf(7, 30), WeightTrend.changes(monthTrend).map { it.days })

        val down = WeightChange(days = 30, kg = -1.21)
        assertEquals(WeightChange.Direction.DOWN, down.direction(WeightUnit.KG))
        assertEquals("arrow.down", down.symbol(WeightUnit.KG))
        assertEquals("1.2 kg", down.amount(WeightUnit.KG, enGB), "the arrow carries the sign")
        assertEquals("Down 1.2 kilograms over 30 days", down.spoken(WeightUnit.KG, enGB))
        assertEquals(WeightChange.Direction.FLAT, WeightChange(days = 7, kg = 0.04).direction(WeightUnit.KG), "0.0 at one decimal is flat")
        assertEquals("arrow.up", WeightChange(days = 7, kg = 0.5).symbol(WeightUnit.LB))
        assertEquals(
            "Trend 88.1 kilograms. Down 1.2 kilograms over 30 days.",
            WeightCopy.chartSummary(88.1, "Down 1.2 kilograms over 30 days", WeightUnit.KG, enGB),
        )
        assertEquals("Trend 88.1 kilograms.", WeightCopy.chartSummary(88.1, null, WeightUnit.KG, enGB))
    }

    // MARK: Units

    /**
     * The locale's person-weight unit (CLDR, as Foundation's UnitMass reads it): pounds for en_US and es_US, kilograms
     * everywhere else, en_GB's stones included.
     */
    @Test
    fun testTheUnitFollowsTheLocaleUntilTheMoreMenuPicksOne() {
        assertEquals(WeightUnit.LB, WeightUnit.preferred(enUS))
        assertEquals(WeightUnit.LB, WeightUnit.preferred(Locale.forLanguageTag("es-US")))
        for (id in listOf("en-GB", "en-IE", "en-AU", "en-CA", "de-DE", "fr-FR", "ja-JP", "en-IN")) {
            assertEquals(WeightUnit.KG, WeightUnit.preferred(Locale.forLanguageTag(id)), id)
        }
        assertClose(194.6 * 0.45359237, WeightUnit.LB.kilograms(194.6), 1e-12)
        assertClose(194.6, WeightUnit.LB.valueFromKilograms(WeightUnit.LB.kilograms(194.6)))
        assertEquals(88.35, WeightUnit.KG.valueFromKilograms(88.35))
    }

    @Test
    fun testWhatIsTypedParsesInTheLocaleWithinTheBounds() {
        assertEquals(88.35, WeightFormat.parse("88,35", deDE))
        assertEquals(88.35, WeightFormat.parse("88.35", deDE), "a point reads as the decimal point too")
        assertEquals(88.35, WeightFormat.parse("88.35", enGB))
        assertEquals(88.35, WeightFormat.parse("88,35", enUS), "a weight never needs a thousands separator")
        assertEquals(88.0, WeightFormat.parse(" 88 ", enGB))
        assertEquals(88.0, WeightFormat.parse("88.", enGB))
        assertEquals(
            88.3, WeightFormat.parse("٨٨٫٣", Locale.forLanguageTag("ar-SA")),
            "any script's digits, the locale's own separator",
        )
        for (bad in listOf("", "88.356", "88..3", "8,8.3", "abc", "-88", "1,234.5", ".5", "88 kg")) {
            assertNull(WeightFormat.parse(bad, enGB), bad)
        }
        assertNull(WeightFormat.kilograms("19.9", WeightUnit.KG, enGB))
        assertEquals(20.0, WeightFormat.kilograms("20", WeightUnit.KG, enGB))
        assertEquals(350.0, WeightFormat.kilograms("350", WeightUnit.KG, enGB))
        assertNull(WeightFormat.kilograms("350.1", WeightUnit.KG, enGB))
        assertNull(WeightFormat.kilograms("43.9", WeightUnit.LB, enUS))
        assertClose(44 * 0.45359237, WeightFormat.kilograms("44", WeightUnit.LB, enUS))
        assertNotNull(WeightFormat.kilograms("770", WeightUnit.LB, enUS))
        assertNull(WeightFormat.kilograms("771", WeightUnit.LB, enUS))

        assertEquals("88.35", WeightFormat.sanitize("88.356", enGB), "two decimals at most")
        assertEquals("88,35", WeightFormat.sanitize("8a8,3,5", deDE))
        assertEquals("5", WeightFormat.sanitize(".5", enGB), "no leading separator")
        assertEquals("1234", WeightFormat.sanitize("12345", enGB))
    }

    /** Kilograms as typed with up to two decimals, pounds with one, the trend with one, in the locale's own numbers. */
    @Test
    fun testWeightsShowInTheLocale() {
        assertEquals("88,35", WeightFormat.value(88.35, WeightUnit.KG, deDE))
        assertEquals("88.35", WeightFormat.value(88.35, WeightUnit.KG, enGB))
        assertEquals("88.0", WeightFormat.value(88.0, WeightUnit.KG, enGB))
        assertEquals("88.3", WeightFormat.value(88.3, WeightUnit.KG, enGB))
        assertEquals("194.6", WeightFormat.value(194.6 * 0.45359237, WeightUnit.LB, enUS))
        assertEquals("1000.0", WeightFormat.value(1000 * 0.45359237, WeightUnit.LB, enUS), "no grouping")
        assertEquals("88.1", WeightFormat.trend(88.123, WeightUnit.KG, enGB))
        // (Android) As ICU formats it on the iPhone: the shortest decimal, 88.35, rounded half to even, not the binary 88.3499...
        assertEquals("88.4", WeightFormat.trend(88.35, WeightUnit.KG, enGB))
        assertEquals("88.2", WeightFormat.trend(88.25, WeightUnit.KG, enGB))
        assertEquals("88.35 kg", WeightFormat.withUnit(88.35, WeightUnit.KG, enGB))
        assertEquals("88.35 kilograms", WeightFormat.spoken(88.35, WeightUnit.KG, enGB))
    }

    // MARK: Taken Pro

    /** The first weigh-in needs no Pro; after it, logging needs it, as doses and voice to-dos do. */
    @Test
    fun testTheFirstWeighInNeedsNoProAfterThatLoggingDoes() {
        val now = at(2026, 10, 22, 9)
        assertEquals(ProAccess.FIRST_SESSION, WeightGate.access(null, null, settled = true, legacyLog = false, now = now))
        assertEquals(
            ProAccess.FIRST_SESSION,
            WeightGate.access(null, ProStatus.notPro(now), settled = true, legacyLog = false, now = now),
        )
        assertEquals(ProAccess.LOCKED, WeightGate.access(now, null, settled = true, legacyLog = false, now = now))
        val yearly = ProStatus(isPro = true, reason = ProReason.YEARLY, checkedAt = now, expiresAt = at(2027, 10, 22, 9), willRenew = true)
        assertEquals(ProAccess.PRO, WeightGate.access(now, yearly, settled = true, legacyLog = false, now = now))
        assertEquals(
            ProAccess.CHECKING, WeightGate.access(now, null, settled = false, legacyLog = false, now = now),
            "never locked before Play's first answer",
        )
        assertEquals(
            ProAccess.PENDING, WeightGate.access(now, null, settled = true, legacyLog = true, now = now),
            "a 1.0 log is never locked out on a guess (never true on Android, kept as the shared rule says)",
        )

        val state = WeightState()
        state.log(88.35, now, london)
        assertEquals(now, state.firstWeighInAt)
        val first = state.weighIns[0]
        state.delete(first.id)
        state.eraseAll()
        assertEquals(now, state.firstWeighInAt, "deleting or erasing never gives the first weigh-in back")
    }

    // MARK: The offer on Today

    private data class OfferCase(var state: StackState, var now: Instant) {
        val summary: DaySummary get() = StackEngine(state, londonClock()).todaySummary(now)
    }

    /**
     * A Thursday 22 October with Vitamin D3 daily and Semaglutide on Thursdays, both logged today and last week, and the
     * widget invite shown on Tuesday.
     */
    private fun glp1Day(code: String = "SEM"): OfferCase {
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val shot = makeItem(
            if (code == "OSM") "Oral Semaglutide" else "Semaglutide", code,
            if (code == "OSM") Frequency.Daily(1) else Frequency.Weekdays(setOf(5)), created = created, sortIndex = 1,
        )
        val state = StackState(items = listOf(vd3, shot))
        for (dayOfMonth in 15..22) {
            state.logDose(vd3.id, at(2026, 10, dayOfMonth, 8), london)
            if (code == "OSM") state.logDose(shot.id, at(2026, 10, dayOfMonth, 8, 5), london)
        }
        if (code != "OSM") {
            state.logDose(shot.id, at(2026, 10, 15, 8, 5), london)
            state.logDose(shot.id, at(2026, 10, 22, 8, 5), london)
        }
        state.settings.nudgeOfferDone = true
        state.settings.widgetInviteDay = day(20).ordinal
        return OfferCase(state, at(2026, 10, 22, 20))
    }

    private fun shows(c: OfferCase, weight: WeightState = WeightState()): Boolean =
        WeightOffer.shows(weight, c.state, c.summary, londonClock())

    private fun OfferCase.edited(change: StackState.() -> Unit): OfferCase = OfferCase(state.clone().apply(change), now)

    @Test
    fun testTheOfferGoesOnlyToAGLP1StackOnALaterAllTakenDay() {
        val base = glp1Day()
        assertTrue(base.summary.allTaken)
        assertTrue(shows(base), "Semaglutide logged, everything taken, a later day than the first dose and the invite")
        assertTrue(shows(glp1Day("TRZ")), "Tirzepatide")
        assertTrue(shows(glp1Day("OSM")), "Oral Semaglutide")

        assertFalse(shows(base, WeightState(showsTab = true)), "the tab is on already")
        assertFalse(shows(base, WeightState(showsTab = false)), "hidden on purpose: an answer")
        assertFalse(shows(base, WeightState(offerAnswered = true)), "either answer is final")

        val pending = OfferCase(base.state.clone().apply { doses = doses.filter { it.takenAt < at(2026, 10, 22, 4) } }, at(2026, 10, 22, 7))
        assertFalse(shows(pending), "never while anything is pending")

        val supplements = base.edited { items = items.mapIndexed { i, item -> if (i == 1) item.copy(code = "VD3X") else item } }
        assertFalse(shows(supplements), "no GLP-1 medicine, no offer")

        val archived = base.edited { items = items.mapIndexed { i, item -> if (i == 1) item.copy(archived = true) else item } }
        assertFalse(shows(archived), "an archived medicine is not in the stack")

        val shotId = base.state.items[1].id
        val neverLogged = base.edited {
            items = items.mapIndexed { i, item -> if (i == 1) item.copy(frequency = Frequency.Weekdays(setOf(2))) else item }
            doses = doses.filter { it.itemId != shotId }
        }
        assertTrue(neverLogged.summary.allTaken)
        assertFalse(shows(neverLogged), "only once that medicine's dose is logged")

        val firstDay = base.edited { doses = doses.filter { it.takenAt >= at(2026, 10, 22, 4) } }
        assertFalse(shows(firstDay), "never in the first session: not on the first dose's day")

        val inviteToday = base.edited {
            settings.widgetInviteDay = day(22).ordinal
            settings.widgetInviteDone = true
        }
        assertFalse(shows(inviteToday), "never on the widget invite's day")

        val inviteToCome = base.edited { settings.widgetInviteDay = null }
        assertFalse(shows(inviteToCome), "the widget invite has its day first")
        val answered = inviteToCome.edited { settings.widgetInviteDone = true }
        assertTrue(shows(answered), "a Taken widget already there answered the invite without a day")
    }

    /**
     * Android only: a launcher that cannot pin a widget never shows the widget invite, so nothing answers it. The offer
     * then waits only for a later day than the first dose, and nothing is written for the invite.
     */
    @Test
    fun testTheOfferDoesNotWaitForAnInviteThatCanNeverShow() {
        val base = glp1Day()
        val neverInvited = base.edited { settings.widgetInviteDay = null }
        assertFalse(shows(neverInvited), "a launcher that can pin: the invite still comes first")
        assertTrue(
            WeightOffer.shows(WeightState(), neverInvited.state, neverInvited.summary, londonClock(), inviteImpossible = true),
            "a launcher that cannot pin: the invite never shows, so the offer does not wait for it",
        )
        assertFalse(neverInvited.state.settings.widgetInviteDone, "the invite is not marked answered")
        val firstDay = neverInvited.edited { doses = doses.filter { it.takenAt >= at(2026, 10, 22, 4) } }
        assertFalse(
            WeightOffer.shows(WeightState(), firstDay.state, firstDay.summary, londonClock(), inviteImpossible = true),
            "still never on the first dose's day",
        )
        val inviteToday = base.edited { settings.widgetInviteDay = day(22).ordinal }
        assertFalse(
            WeightOffer.shows(WeightState(), inviteToday.state, inviteToday.summary, londonClock(), inviteImpossible = true),
            "an invite shown today, before the launcher changed, still keeps the offer to a later day",
        )
    }

    /** After the trial notice, the nudge offer, the repair and the widget invite; never while locked. */
    @Test
    fun testTheOfferComesAfterEveryOtherRowAndNeverWhileLocked() {
        val c = glp1Day()
        val settings = c.state.settings
        fun pick(settings: StackSettings, repair: DayKey? = null, locked: Boolean = false, notice: String? = null): TodayPrompt? =
            TodayPrompts.pick(
                settings, hasStack = true, today = c.summary, repairDay = repair, locked = locked, widgetPlaced = true,
                trialNotice = notice, weightOffer = true,
            )
        assertEquals(TodayPrompt.WeightOffer, pick(settings))
        assertNull(pick(settings, locked = true), "none while locked: the Pro bar sits there")
        assertEquals(
            TodayPrompt.TrialEnds("Your Taken trial ends Sunday 1 Nov."),
            pick(settings, notice = "Your Taken trial ends Sunday 1 Nov."),
        )
        val unanswered = settings.copy(nudgeOfferDone = false)
        assertEquals(TodayPrompt.NudgeOffer(20 * 60), pick(unanswered))
        assertEquals(TodayPrompt.Repair(day(21)), pick(settings, repair = day(21)))
        assertNull(
            TodayPrompts.pick(
                settings, hasStack = true, today = c.summary, repairDay = null, locked = false, widgetPlaced = true,
                trialNotice = null, weightOffer = false,
            ),
        )
    }

    // MARK: Dose ticks

    /**
     * A tick for each day a dose of a Weekly item was logged, on the day it was logged; never a daily item, and never a
     * day the item was on another schedule.
     */
    @Test
    fun testDoseTicksAreTheDaysAWeeklyDoseWasLogged() {
        val created = at(2026, 9, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val sem = makeItem("Semaglutide", "SEM", Frequency.Weekdays(setOf(5)), created = created, sortIndex = 1)
        val state = StackState(items = listOf(vd3, sem))
        for (dayOfMonth in listOf(1, 8, 15, 16, 22)) state.logDose(sem.id, at(2026, 10, dayOfMonth, 8), london)
        for (dayOfMonth in 1..22) state.logDose(vd3.id, at(2026, 10, dayOfMonth, 8), london)
        val engine = StackEngine(state, londonClock())
        assertEquals(
            listOf(day(1), day(8), day(15), day(16), day(22)), WeightTicks.days(engine),
            "each logged day once, a late dose on its own day",
        )

        // Daily until 10 October, Weekly from then: only the doses logged on Weekly days tick.
        val changedSem = sem.copy(
            frequency = Frequency.Weekdays(setOf(5)),
            pastFrequencies = listOf(FrequencyEra(at(2026, 10, 10, 12), Frequency.Daily(1))),
        )
        val changed = StackState(items = listOf(vd3, changedSem))
        for (dayOfMonth in listOf(2, 3, 15)) changed.logDose(sem.id, at(2026, 10, dayOfMonth, 8), london)
        assertEquals(listOf(day(15)), WeightTicks.days(StackEngine(changed, londonClock())))
        assertTrue(WeightTicks.days(StackEngine(StackState(), londonClock())).isEmpty())
    }

    // MARK: The chart's window

    @Test
    fun testTheWindowFitsWhatIsInViewAndNeverStartsAtZero() {
        val weighIns = listOf(weighIn(92.0, 1, month = 9), weighIn(88.0, 21), weighIn(89.0, 22))
        val trend = WeightTrend.trend(weighIns, londonClock())
        val ticks = listOf(day(1, month = 9), day(17), day(22))
        val week = WeightWindow.make(weighIns, trend, ticks, WeightRange.WEEK, day(22), londonClock())
        assertEquals(day(16), week.firstDay)
        assertEquals(day(22), week.lastDay)
        assertEquals(listOf(88.0, 89.0), week.dots.map { it.kg })
        assertEquals(listOf(day(17), day(22)), week.ticks)
        val values = week.dots.map { it.kg } + week.trend.map { it.kg }
        val low = values.min()
        val high = values.max()
        val padding = maxOf(WeightWindow.MINIMUM_PADDING, (high - low) * 0.15)
        assertClose(low - padding, week.lower)
        assertClose(high + padding, week.upper)
        assertTrue(week.lower > 80, "fitted to the data, never from zero")

        val all = WeightWindow.make(weighIns, trend, ticks, WeightRange.ALL, day(22), londonClock())
        assertEquals(day(1, month = 9), all.firstDay)
        assertEquals(3, all.dots.size)
        assertEquals(trend.size, all.trend.size)
        assertTrue(all.upper >= 92)

        val single = WeightWindow.make(
            listOf(weighIn(88.0, 22)), WeightTrend.trend(listOf(weighIn(88.0, 22)), londonClock()), emptyList(),
            WeightRange.ALL, day(22), londonClock(),
        )
        assertEquals(day(16), single.firstDay, "at least a week across")
        assertClose(88 - WeightWindow.MINIMUM_PADDING, single.lower)

        val stale = WeightWindow.make(weighIns, trend, ticks, WeightRange.WEEK, day(31), londonClock())
        assertTrue(stale.isEmpty, "a week with no weigh-ins draws no line past the last one")
        assertEquals(listOf("W", "30D", "90D", "Y", "All"), WeightRange.entries.map { it.label })
    }

    // MARK: CSV

    @Test
    fun testExportIsDateTimeAndKilogramsOldestFirst() {
        val pounds = WeighIn(kg = 194.6 * 0.45359237, weighedAt = at(2026, 10, 20, 7, 5))
        val csv = WeightCSV.make(listOf(weighIn(88.35, 21, 7, 42), pounds, weighIn(88.0, 19, 6, 58)), london)
        assertEquals(
            listOf("date,time,kg", "2026-10-19,06:58,88.0", "2026-10-20,07:05,88.269", "2026-10-21,07:42,88.35"),
            csv.split("\n").filter { it.isNotEmpty() },
        )
        assertEquals("taken-weight.csv", WeightCSV.FILE_NAME)
    }

    private fun parse(text: String, unit: WeightUnit = WeightUnit.KG, locale: Locale? = null): WeightImport.Parsed? =
        WeightImport.parse(text, unit, locale ?: enGB, london, at(2026, 10, 22, 9)).getOrNull()

    /** Taken's own file comes back as it went out, and a second import adds nothing. */
    @Test
    fun testImportReadsTakensOwnExportAndDedupesByTheMinute() {
        val original = listOf(weighIn(88.35, 21, 7, 42), WeighIn(kg = 194.6 * 0.45359237, weighedAt = at(2026, 10, 20, 7, 5)))
        val parsed = assertNotNull(parse(WeightCSV.make(original, london), WeightUnit.LB))
        assertEquals(WeightUnit.KG, parsed.unit, "the header says kg")
        assertEquals(0, parsed.unreadable)
        assertEquals(listOf(at(2026, 10, 20, 7, 5), at(2026, 10, 21, 7, 42)), parsed.weighIns.map { it.weighedAt })
        assertEquals(listOf(88.269, 88.35), parsed.weighIns.map { it.kg })
        assertEquals("194.6", WeightFormat.value(parsed.weighIns[0].kg, WeightUnit.LB, enUS), "a pound figure round-trips")

        val state = WeightState(weighIns = original)
        assertNull(WeightState().firstWeighInAt)
        val merged = state.merge(parsed.weighIns, at(2026, 10, 22, 9))
        assertEquals(0, merged.added)
        assertEquals(2, merged.already)
        assertEquals(2, state.weighIns.size)

        val fresh = WeightState()
        assertEquals(2, fresh.merge(parsed.weighIns, at(2026, 10, 22, 9)).added)
        assertEquals(at(2026, 10, 22, 9), fresh.firstWeighInAt, "an import is a first weigh-in for the Pro rule")
        assertEquals(0, fresh.merge(parsed.weighIns, at(2026, 10, 22, 10)).added, "the same file twice adds nothing")
        assertEquals("Added 2 weigh-ins, read in kg.", WeightCopy.imported(added = 2, already = 0, unreadable = 0, unit = WeightUnit.KG))
        assertEquals(
            "Nothing new: those 2 weigh-ins are already in Taken. 1 row could not be read.",
            WeightCopy.imported(added = 0, already = 2, unreadable = 1, unit = WeightUnit.KG),
        )
        assertEquals(
            "Added 1 weigh-in, read in lb. 1 was already in Taken.",
            WeightCopy.imported(added = 1, already = 1, unreadable = 0, unit = WeightUnit.LB),
        )
    }

    /**
     * The common layouts: a US file in pounds with month-first dates and another column, a German Excel file with
     * semicolons and decimal commas, and an export with a title, quoted month names and a trend column.
     */
    @Test
    fun testImportReadsTheCommonLayouts() {
        val us = assertNotNull(
            parse(
                """
                Date,Weight (lbs),Body Fat (%)
                10/21/2026,194.6,22.1
                10/20/2026,195.0,22.3
                "10/19/2026","195.4 lbs",22.0
                """.trimIndent(),
                WeightUnit.KG, enGB,
            ),
        )
        assertEquals(WeightUnit.LB, us.unit)
        assertEquals(
            listOf(at(2026, 10, 19, 12), at(2026, 10, 20, 12), at(2026, 10, 21, 12)), us.weighIns.map { it.weighedAt },
            "a second number over 12 means month first; a date alone is noon",
        )
        assertClose(194.6 * 0.45359237, us.weighIns.last().kg)

        val german = assertNotNull(parse("Datum;Gewicht (kg)\n21.10.2026;88,35\n20.10.2026;88,6\n", WeightUnit.LB))
        assertEquals(WeightUnit.KG, german.unit)
        assertEquals(listOf(88.6, 88.35), german.weighIns.map { it.kg })
        assertEquals(at(2026, 10, 20, 12), german.weighIns.first().weighedAt)

        val export = assertNotNull(
            parse(
                """
                MyNetDiary Data Export

                "Date","Weight, kg","Trending Weight, kg"
                "Oct 21, 2026","88.35","88.1"
                "Oct 20, 2026","88.6","88.2"
                "Oct 19, 2026","",""
                "Sunday, October 18, 2026","88.9","88.3"
                """.trimIndent(),
            ),
        )
        assertEquals(listOf(88.9, 88.6, 88.35), export.weighIns.map { it.kg }, "the weight, never the trend column")
        assertEquals(1, export.unreadable, "a day with no weight")

        val noUnit = assertNotNull(parse("date,weight\n2026-10-21,88.35\n", WeightUnit.KG))
        assertEquals(WeightUnit.KG, noUnit.unit, "no unit anywhere: the person's own")
        assertClose(194.6 * 0.45359237, assertNotNull(parse("date,weight\n2026-10-21,194.6\n", WeightUnit.LB)).weighIns.first().kg)

        val timed = assertNotNull(
            parse(
                """
                Date,Time,Weight (kg),Notes
                2026-10-21,7:42 AM,88.35,after the gym
                2026-10-20T06:05:00Z,,88.5,
                21/10/2026 19:05,,88.9,
                """.trimIndent(),
            ),
        )
        assertEquals(
            listOf(at(2026, 10, 20, 7, 5), at(2026, 10, 21, 7, 42), at(2026, 10, 21, 19, 5)), timed.weighIns.map { it.weighedAt },
        )
        assertEquals(0, timed.weighIns.first().utcOffset, "the zone the cell names")
        assertEquals(day(20), londonClock().day(timed.weighIns[0]))

        val tabs = assertNotNull(parse("date\tkg\n2026-10-21\t88.35\n"))
        assertEquals(1, tabs.weighIns.size)
        val headerless = assertNotNull(parse("2026-10-21,88.35\n2026-10-20,88.6\n", WeightUnit.KG))
        assertEquals(2, headerless.weighIns.size, "two columns, a date and a number")
    }

    @Test
    fun testImportSkipsWhatItCannotReadAndSaysSo() {
        val mixed = assertNotNull(
            parse(
                """
                date,kg
                2026-10-23,88.0
                2026-10-21,12.0
                2026-10-21,abc
                2026-02-31,88.0
                2026-10-20,88.4
                2026-10-19,88.6
                2026-10-19,88.5

                """.trimIndent() + "\n",
            ),
        )
        assertEquals(listOf(88.5, 88.4), mixed.weighIns.map { it.kg }, "the 19th twice at noon: the lower stays")
        assertEquals(4, mixed.unreadable, "a day to come, below the bounds, not a number, not a date")

        val ambiguous = "date,kg\n03/04/2026,88.0\n"
        assertEquals(at(2026, 3, 4, 12), assertNotNull(parse(ambiguous, locale = enUS)).weighIns.first().weighedAt)
        assertEquals(
            at(2026, 4, 3, 12), assertNotNull(parse(ambiguous, locale = enGB)).weighIns.first().weighedAt,
            "neither number over 12: the locale's own order",
        )

        assertEquals(WeightImport.Result.Failed(WeightImport.Failure.NO_COLUMNS), WeightImport.parse("hello,world\n1,2\n", WeightUnit.KG))
        assertEquals(WeightImport.Result.Failed(WeightImport.Failure.NO_COLUMNS), WeightImport.parse("", WeightUnit.KG))
        assertEquals(WeightImport.Result.Failed(WeightImport.Failure.NOTHING_READABLE), WeightImport.parse("date,kg\nfoo,bar\n", WeightUnit.KG))
        assertEquals("date,kg", WeightImport.text("﻿date,kg".toByteArray(Charsets.UTF_8))?.replace("﻿", ""))
        assertEquals("date,kg", WeightImport.text("date,kg".toByteArray(Charsets.UTF_16)))
    }

    // MARK: Copy

    @Test
    fun testTheCopyIsCalmAndNeutral() {
        for (text in WeightCopy.all) {
            assertCopyRules(text)
            for (word in listOf("lose", "loss", "ideal", "goal")) {
                assertFalse(text.lowercase().contains(word), "$word in $text")
            }
        }
        val clock = londonClock()
        val now = at(2026, 10, 22, 9)
        fun last(weighIn: WeighIn?) = WeightCopy.lastLine(weighIn, now, clock)
        assertEquals("No weigh-ins yet", last(null))
        assertEquals("Last weigh-in today, 07:42", last(weighIn(88.35, 22, 7, 42)))
        assertEquals("Last weigh-in yesterday, 07:42", last(weighIn(88.35, 21, 7, 42)))
        assertEquals("Last weigh-in Monday, 07:42", last(weighIn(88.0, 19, 7, 42)))
        assertEquals("Last weigh-in 14 Oct, 07:42", last(weighIn(88.0, 14, 7, 42)))
        assertEquals("Last weigh-in 3 Mar 2025, 07:42", last(WeighIn(kg = 88.0, weighedAt = at(2025, 3, 3, 7, 42), utcOffset = 0)))
        fun spoken(weighIn: WeighIn?) = WeightCopy.spokenLastLine(weighIn, WeightUnit.KG, now, clock, enGB)
        assertEquals("Last weigh-in 88.35 kilograms, yesterday at 07:42", spoken(weighIn(88.35, 21, 7, 42)))
        assertEquals("Last weigh-in today at 07:06", spoken(weighIn(89.3, 22, 7, 6)))
        assertEquals("No weigh-ins yet", spoken(null))
        assertEquals("Tue 20 Oct", WeightCopy.listDay(day(20), day(22)))
        assertEquals("Mon 3 Mar 2025", WeightCopy.listDay(DayKey(2025, 3, 3), day(22)))
    }
}
