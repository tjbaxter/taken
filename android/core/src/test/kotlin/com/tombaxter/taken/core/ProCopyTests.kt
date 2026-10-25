package com.tombaxter.taken.core

import com.tombaxter.taken.core.pro.IntroTerms
import com.tombaxter.taken.core.pro.PlanOffer
import com.tombaxter.taken.core.pro.PlanPeriod
import com.tombaxter.taken.core.pro.PlanPeriod.PeriodUnit
import com.tombaxter.taken.core.pro.PlanPrice
import com.tombaxter.taken.core.pro.PlayResponse
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.pro.of
import com.tombaxter.taken.core.reminders.TrialReminder
import java.math.BigDecimal
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/ProCopyTests.swift: the paywall's and Profile's words are built from Play's values (PRO.md), so
 * the lines Play's Subscriptions policy asks for are checked here for every plan and offer shape. Android wording where
 * SPEC-ANDROID 6.4 changes it ("Cancel anytime in Google Play.", "this Google account"); the status lines are Android's
 * (SPEC-ANDROID 9.5), since a phone never sees a period end.
 */
class ProCopyTests {
    private val us = Locale.US
    private val week = PlanPeriod(1, PeriodUnit.WEEK)

    private fun yearly(
        intro: IntroTerms? = null,
        price: String = "19.99",
        display: String = "$19.99",
        currency: String = "USD",
        locale: Locale = us,
    ) = PlanOffer(ProPlan.YEARLY, display, BigDecimal(price), currency, locale, PlanPeriod(1, PeriodUnit.YEAR), intro)

    private val onUsWeek get() = IntroTerms(IntroTerms.Mode.ON_US, week, 1, "$0.00")
    private val monthly get() = PlanOffer(ProPlan.MONTHLY, "$3.99", BigDecimal("3.99"), "USD", us, PlanPeriod(1, PeriodUnit.MONTH), null)
    private val lifetime get() = PlanOffer(ProPlan.LIFETIME, "$49.99", BigDecimal("49.99"), "USD", us, null, null)

    @Test
    fun testYearlyWithTheIntroductoryWeek() {
        val offer = yearly(intro = onUsWeek)
        assertEquals("7 days on us", ProCopy.introTag(offer.intro))
        assertEquals("$19.99", ProCopy.price(offer).first)
        assertEquals("/ year", ProCopy.price(offer).second)
        assertEquals("about $1.67 / month", ProCopy.monthlyEquivalent(offer))
        assertEquals("Start 7 days on us", ProCopy.cta(offer, eligible = true))
        assertEquals(
            "7 days on us, then $19.99 per year. Renews automatically until cancelled. Cancel anytime in Google Play.",
            ProCopy.terms(offer, eligible = true),
        )
    }

    @Test
    fun testYearlyAfterTheOfferWasUsed() {
        val offer = yearly(intro = onUsWeek)
        assertNull(ProCopy.liveIntro(offer, eligible = false))
        assertEquals("Continue", ProCopy.cta(offer, eligible = false))
        assertEquals(
            "$19.99 per year. Renews automatically until cancelled. Cancel anytime in Google Play.",
            ProCopy.terms(offer, eligible = false),
        )
    }

    @Test
    fun testSevenDaysReadsTheSameAsOneWeek() {
        val days = IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(7, PeriodUnit.DAY), 1, "$0.00")
        assertEquals("7 days on us", ProCopy.introTag(days))
        assertEquals("14 days", ProCopy.span(IntroTerms(IntroTerms.Mode.ON_US, week, 2, "$0.00")))
        assertEquals("1 month on us", ProCopy.introTag(IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(1, PeriodUnit.MONTH), 1, "$0.00")))
        assertEquals("1 day", ProCopy.span(IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(1, PeriodUnit.DAY), 1, "$0.00")))
    }

    @Test
    fun testMonthly() {
        assertEquals("$3.99", ProCopy.price(monthly).first)
        assertEquals("/ month", ProCopy.price(monthly).second)
        assertNull(ProCopy.monthlyEquivalent(monthly))
        assertNull(ProCopy.introTag(monthly.intro))
        assertEquals("Continue", ProCopy.cta(monthly, eligible = true), "monthly has no introductory offer")
        assertEquals(
            "$3.99 per month. Renews automatically until cancelled. Cancel anytime in Google Play.",
            ProCopy.terms(monthly, eligible = true),
        )
    }

    @Test
    fun testLifetime() {
        assertEquals("$49.99", ProCopy.price(lifetime).first)
        assertEquals("once", ProCopy.price(lifetime).second)
        assertNull(ProCopy.monthlyEquivalent(lifetime))
        assertEquals("Continue", ProCopy.cta(lifetime, eligible = true))
        assertEquals("One payment. Yours for good.", ProCopy.terms(lifetime, eligible = true))
        assertEquals("One payment. Yours for good.", ProCopy.termsWithoutPrices(ProPlan.LIFETIME))
        assertEquals(ProCopy.RENEWAL_TERMS, ProCopy.termsWithoutPrices(ProPlan.YEARLY))
        assertEquals("Continue", ProCopy.cta(null, eligible = true))
    }

    @Test
    fun testPricesFollowTheStorefront() {
        val gb = yearly(price = "19.99", display = "£19.99", currency = "GBP", locale = Locale.UK)
        assertEquals("£19.99", ProCopy.price(gb).first, "the billed amount is Play's own formatted price")
        assertEquals("about £1.67 / month", ProCopy.monthlyEquivalent(gb))
        val de = yearly(price = "19.99", display = "19,99 €", currency = "EUR", locale = Locale.GERMANY)
        val perMonth = ProCopy.monthlyEquivalent(de) ?: ""
        assertTrue(perMonth.startsWith("about 1,67"), perMonth)
        assertTrue(perMonth.contains("€"), perMonth)
        val jp = yearly(price = "3000", display = "¥3,000", currency = "JPY")
        assertEquals("about ¥250 / month", ProCopy.monthlyEquivalent(jp))
        assertEquals("¥3,000 per year.", ProCopy.terms(jp, eligible = false).take(16))
    }

    @Test
    fun testOtherIntroductoryOfferShapes() {
        val payAsYouGo = IntroTerms(IntroTerms.Mode.PAY_AS_YOU_GO, PlanPeriod(1, PeriodUnit.MONTH), 3, "$0.99")
        val monthlyIntro = PlanOffer(ProPlan.MONTHLY, "$3.99", BigDecimal("3.99"), "USD", us, PlanPeriod(1, PeriodUnit.MONTH), payAsYouGo)
        assertNull(ProCopy.introTag(payAsYouGo), "only an offer that costs nothing is on us")
        assertEquals("Continue", ProCopy.cta(monthlyIntro, eligible = true))
        assertEquals(
            "$0.99 per month for 3 months, then $3.99 per month. ${ProCopy.RENEWAL_TERMS}",
            ProCopy.terms(monthlyIntro, eligible = true),
        )
        val upFront = IntroTerms(IntroTerms.Mode.PAY_UP_FRONT, PlanPeriod(3, PeriodUnit.MONTH), 1, "$1.99")
        assertEquals("$1.99 for 3 months, then $19.99 per year. ${ProCopy.RENEWAL_TERMS}", ProCopy.terms(yearly(intro = upFront), eligible = true))
        val quarterly = PlanOffer(ProPlan.MONTHLY, "$9.99", BigDecimal("9.99"), "USD", us, PlanPeriod(3, PeriodUnit.MONTH), null)
        assertEquals("/ 3 months", ProCopy.price(quarterly).second)
        assertEquals("every 3 months", ProCopy.per(PlanPeriod(3, PeriodUnit.MONTH)))
    }

    @Test
    fun testLockedBar() {
        assertEquals("Start 7 days on us", ProCopy.lockedBar(eligible = true, intro = onUsWeek))
        assertEquals("Pro ended. Tap to continue", ProCopy.lockedBar(eligible = false, intro = onUsWeek))
        assertEquals("Taken Pro. Tap to continue", ProCopy.lockedBar(eligible = null, intro = null), "never promises the week before Play says it applies")
        assertEquals("Taken Pro. Tap to continue", ProCopy.lockedBar(eligible = true, intro = null))
    }

    /** Rewritten against the Android fact: no period end on the phone, so "renewing" and "not renewing" (SPEC-ANDROID 9.5). */
    @Test
    fun testSettingsStatusLines() {
        val now = at(2026, 10, 13, 9)
        fun line(status: ProStatus?) = ProCopy.statusLine(status, now, london)
        val horizon = at(2026, 10, 16, 9)

        assertEquals("Pro lifetime", line(ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now)))
        assertEquals("Pro yearly · renewing", line(ProStatus(true, ProReason.YEARLY, now, expiresAt = horizon, willRenew = true)))
        assertEquals("Pro yearly · not renewing", line(ProStatus(true, ProReason.YEARLY, now, expiresAt = horizon, willRenew = false)))
        assertEquals("Pro monthly · renewing", line(ProStatus(true, ProReason.MONTHLY, now, expiresAt = horizon, willRenew = true)))
        assertEquals("Pro monthly · not renewing", line(ProStatus(true, ProReason.MONTHLY, now, expiresAt = horizon, willRenew = false)))
        assertEquals("Trial · ends 19 Oct", line(ProStatus(true, ProReason.TRIAL, now, expiresAt = at(2026, 10, 19, 9), willRenew = true)))
        assertEquals("Trial · ends 19 Oct", line(ProStatus(true, ProReason.TRIAL, now, expiresAt = at(2026, 10, 19, 9), willRenew = false)), "a cancelled trial still ends then")
        assertEquals("Not active", line(ProStatus.notPro(now)))
        assertEquals("Not active", line(null))
        assertEquals(
            "Not active",
            line(ProStatus(true, ProReason.MONTHLY, now, expiresAt = at(2026, 10, 12, 9), willRenew = false)),
            "an ended plan is not Pro",
        )
        assertEquals(
            "Trial · renewing",
            line(ProStatus(true, ProReason.TRIAL, now, expiresAt = at(2026, 10, 13, 8), willRenew = true)),
            "the trial ended and the renewal has not shown yet",
        )
        assertEquals(
            "Not active",
            line(ProStatus(true, ProReason.YEARLY, now, expiresAt = at(2026, 10, 1, 9), willRenew = true)),
            "an answer that ran out and was never renewed, once the margin is over",
        )
    }

    @Test
    fun testThePaywallSellsOnlyWhatProUnlocks() {
        // The log, the history grid, the day sheet and CSV export stay open without Pro: no bullet may sell them.
        assertEquals(4, ProCopy.features.size)
        assertEquals("Voice to-dos", ProCopy.features.last(), "voice to-dos need Pro after the first note")
        for (line in ProCopy.features) {
            assertFalse(line.lowercase().contains("history"), line)
            assertFalse(line.lowercase().contains("csv"), line)
            assertFalse(line.lowercase().contains("export"), line)
        }
        assertTrue(ProCopy.features.any { it.contains("nudge") }, "the nudge is a Pro feature, so the paywall says so")
        assertEquals(listOf("Yearly", "Monthly", "Lifetime"), ProPlan.entries.map { it.title })
    }

    // MARK: The trial promise (2026-10-21)

    @Test
    fun testTheTrialTimelineForTheSevenDayTrial() {
        val now = at(2026, 10, 21, 9)
        val steps = ProCopy.trialTimeline(yearly(intro = onUsWeek), eligible = true, now = now, zone = london)
        assertEquals(listOf("Today: full Pro", "Day 4: we remind you", "Day 7: $19.99 a year starts"), steps.map { it.line })
        assertEquals(listOf("Today", "Day 4", "Day 7"), steps.map { it.day })
        assertEquals(listOf("Full Pro", "We remind you", "$19.99 a year starts"), steps.map { it.displayText })
        val days = IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(7, PeriodUnit.DAY), 1, "$0.00")
        assertEquals(steps, ProCopy.trialTimeline(yearly(intro = days), eligible = true, now = now, zone = london), "7 days reads the same as 1 week")
        assertEquals(3, TrialReminder.LEAD_DAYS, "the reminder day is the trial length minus 3")
    }

    @Test
    fun testTheTrialTimelineFollowsTheRealTrialLengthAndPrice() {
        val now = at(2026, 10, 21, 9)
        fun lines(intro: IntroTerms, offer: PlanOffer? = null): List<String> =
            ProCopy.trialTimeline(offer ?: yearly(intro = intro), eligible = true, now = now, zone = london).map { it.line }
        assertEquals(
            listOf("Today: full Pro", "Day 11: we remind you", "Day 14: $19.99 a year starts"),
            lines(IntroTerms(IntroTerms.Mode.ON_US, week, 2, "$0.00")),
        )
        assertEquals(
            listOf("Today: full Pro", "Day 28: we remind you", "Day 31: $19.99 a year starts"),
            lines(IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(1, PeriodUnit.MONTH), 1, "$0.00")),
            "a month from 21 Oct is 31 days on the calendar",
        )
        assertEquals(
            listOf("Today: full Pro", "Day 3: $19.99 a year starts"),
            lines(IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(3, PeriodUnit.DAY), 1, "$0.00")),
            "3 days: no reminder, so none is promised",
        )
        assertEquals(
            listOf("Today: full Pro", "Day 1: we remind you", "Day 4: $19.99 a year starts"),
            lines(IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(4, PeriodUnit.DAY), 1, "$0.00")),
        )
        val gb = yearly(intro = onUsWeek, price = "19.99", display = "£19.99", currency = "GBP", locale = Locale.UK)
        assertEquals("Day 7: £19.99 a year starts", lines(onUsWeek, gb).last(), "the storefront's own price")
        val quarterly = PlanOffer(ProPlan.MONTHLY, "$9.99", BigDecimal("9.99"), "USD", us, PlanPeriod(3, PeriodUnit.MONTH), onUsWeek)
        assertEquals("Day 7: $9.99 every 3 months starts", lines(onUsWeek, quarterly).last())
        assertEquals("a month", ProCopy.perPlain(PlanPeriod(1, PeriodUnit.MONTH)))
        assertEquals("$19.99 a year", ProCopy.renewal(PlanPrice("$19.99", PlanPeriod(1, PeriodUnit.YEAR))))
    }

    @Test
    fun testTheTrialTimelineOnlyWhileTheOfferApplies() {
        val now = at(2026, 10, 21, 9)
        assertEquals(emptyList(), ProCopy.trialTimeline(yearly(intro = onUsWeek), eligible = false, now = now, zone = london), "the offer was used: no timeline")
        assertEquals(emptyList(), ProCopy.trialTimeline(yearly(), eligible = true, now = now, zone = london), "no offer")
        assertEquals(emptyList(), ProCopy.trialTimeline(null, eligible = true, now = now, zone = london), "not loaded")
        assertEquals(emptyList(), ProCopy.trialTimeline(lifetime, eligible = true, now = now, zone = london))
        val payAsYouGo = IntroTerms(IntroTerms.Mode.PAY_AS_YOU_GO, PlanPeriod(1, PeriodUnit.MONTH), 3, "$0.99")
        assertEquals(emptyList(), ProCopy.trialTimeline(yearly(intro = payAsYouGo), eligible = true, now = now, zone = london), "only an offer that costs nothing is a trial")
        assertEquals(
            "7 days on us, then $19.99 per year. Renews automatically until cancelled. Cancel anytime in Google Play.",
            ProCopy.terms(yearly(intro = onUsWeek), eligible = true),
            "the terms line under the button stays as it was",
        )
    }

    @Test
    fun testTheTimelineNeverPromisesAReminderThatCannotCome() {
        val now = at(2026, 10, 21, 9)
        assertEquals(
            listOf("Today: full Pro", "Day 7: $19.99 a year starts"),
            ProCopy.trialTimeline(yearly(intro = onUsWeek), eligible = true, now = now, zone = london, remindable = false).map { it.line },
            "notifications already off for Taken: no reminder step, the rest as it was",
        )
        assertEquals(
            listOf("Today: full Pro", "Day 4: we remind you", "Day 7: $19.99 a year starts"),
            ProCopy.trialTimeline(yearly(intro = onUsWeek), eligible = true, now = now, zone = london, remindable = true).map { it.line },
            "not asked yet, or allowed: the promise stays",
        )
    }

    @Test
    fun testAPlanPriceSurvivesTheCache() {
        val price = PlanPrice.of(yearly(intro = onUsWeek))
        assertEquals(PlanPrice("$19.99", PlanPeriod(1, PeriodUnit.YEAR)), price)
        assertNull(PlanPrice.of(lifetime), "one payment has no recurring price")
        val text = com.tombaxter.taken.core.pro.ProLedgerCodec.encodePrice(price!!).toString()
        assertEquals(price, com.tombaxter.taken.core.pro.ProLedgerCodec.decodePrice(com.tombaxter.taken.core.model.TakenJson.parse(text)))
        val zero = """{"displayPrice":"$1","period":{"value":0,"unit":"year"}}"""
        assertEquals(
            1,
            com.tombaxter.taken.core.pro.ProLedgerCodec.decodePrice(com.tombaxter.taken.core.model.TakenJson.parse(zero)).period.value,
            "a period is never shorter than one unit",
        )
    }

    @Test
    fun testRestoreLinesAreTrueForEveryone() {
        // Said to someone who never bought and to a subscriber whose plan ended: neither has anything active.
        assertEquals("No active Taken Pro on this Google account.", ProCopy.NOTHING_TO_RESTORE)
        assertFalse(ProCopy.NOTHING_TO_RESTORE.contains("yet"))
        assertEquals("Restored. Taken Pro is on.", ProCopy.RESTORED)
    }

    /** Android only: Play's response codes as words (SPEC-ANDROID 9.3). */
    @Test
    fun testPlayFailuresSayWhatHappened() {
        assertNull(ProCopy.failure(PlayResponse.OK))
        assertNull(ProCopy.failure(PlayResponse.USER_CANCELED), "a cancelled purchase says nothing")
        assertEquals("No connection to Google Play. Try again.", ProCopy.failure(PlayResponse.NETWORK_ERROR))
        assertEquals("No connection to Google Play. Try again.", ProCopy.failure(PlayResponse.SERVICE_UNAVAILABLE))
        assertEquals("No connection to Google Play. Try again.", ProCopy.failure(PlayResponse.SERVICE_DISCONNECTED))
        assertEquals(ProCopy.CANNOT_PAY_HERE, ProCopy.failure(PlayResponse.BILLING_UNAVAILABLE))
        assertEquals("Taken Pro is not sold in this country yet.", ProCopy.failure(PlayResponse.ITEM_UNAVAILABLE))
        assertEquals("Google Play did not finish that. Try again.", ProCopy.failure(PlayResponse.ERROR))
        for (response in PlayResponse.entries) ProCopy.failure(response)?.let { assertCopyRules(it) }
    }

    @Test
    fun testEveryLineKeepsTheCopyRules() {
        val now = at(2026, 10, 13, 9)
        val lines = ArrayList(ProCopy.all)
        val offers = listOf(yearly(intro = onUsWeek), yearly(), monthly, lifetime)
        for (offer in offers) {
            for (eligible in listOf(true, false)) {
                lines.add(ProCopy.cta(offer, eligible))
                lines.add(ProCopy.terms(offer, eligible))
                for (step in ProCopy.trialTimeline(offer, eligible, now, london)) {
                    lines.add(step.line)
                    lines.add(step.displayText)
                }
            }
            lines.add(ProCopy.price(offer).first + " " + ProCopy.price(offer).second)
            lines.add(ProCopy.monthlyEquivalent(offer) ?: "")
        }
        for (eligible in listOf(true, false, null)) lines.add(ProCopy.lockedBar(eligible, onUsWeek))
        for (reason in ProReason.entries) {
            lines.add(ProCopy.statusLine(ProStatus(reason != ProReason.NONE, reason, now, expiresAt = at(2027, 1, 1, 0)), now, london))
        }
        for (text in lines) assertCopyRules(text)
    }
}
