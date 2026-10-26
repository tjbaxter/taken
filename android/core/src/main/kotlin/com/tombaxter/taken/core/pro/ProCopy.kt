package com.tombaxter.taken.core.pro

import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.reminders.TrialReminder
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Currency
import java.util.Locale

// The paywall's and Profile's words, built from what Google Play says about each product, never from numbers in the
// code (PRO.md). Ported from Shared/ProCopy.swift; Android wording where the iPhone names Apple's surfaces
// (SPEC-ANDROID 6.4). Pure, so every line Play's Subscriptions policy asks for is unit tested
// (https://support.google.com/googleplay/android-developer/answer/9900533). Copy rules: no em or en dashes, never the word
// for no charge, no exclamation marks.

/**
 * One plan as the paywall shows it, in Play's terms: its formatted price, its price as a number with Play's currency,
 * its billing period (null for one payment) and the introductory offer Play returned for this person.
 */
data class PlanOffer(
    val plan: ProPlan,
    val displayPrice: String,
    val price: BigDecimal,
    val currencyCode: String,
    val locale: Locale,
    val period: PlanPeriod?,
    val intro: IntroTerms?,
)

/** The recurring price of a subscription offer; null for one payment. */
fun PlanPrice.Companion.of(offer: PlanOffer): PlanPrice? = offer.period?.let { PlanPrice(offer.displayPrice, it) }

/** One step of the paywall's trial timeline: "Today" and "full Pro". */
data class TrialStep(val day: String, val text: String) {
    /** "Day 4: we remind you", as TalkBack reads it. */
    val line: String get() = "$day: $text"

    /** The text as the timeline sets it, under its day: "We remind you". */
    val displayText: String get() = text.replaceFirstChar { it.uppercase() }
}

object ProCopy {
    const val PRIVACY_URL = "https://tjbaxter.github.io/taken/privacy.html"

    const val HEADLINE = "Keep your record."
    const val SUBLINE = "Every dose, logged to the minute. Widgets, quick settings, the nudge."

    /** The subline as the paywall sets it: one thought per line. */
    const val SUBLINE_LINES = "Every dose, logged to the minute.\nWidgets, quick settings, the nudge."

    /** What Pro unlocks, and only that: the log, the history and CSV export stay open without it. */
    val features: List<String> = listOf(
        "One-tap logging and Take all",
        "Home screen widgets and a quick settings tile",
        "The evening nudge",
        "Voice to-dos",
    )

    /** What a widget, the tile or a nudge says when logging needs Pro. */
    const val LOCKED_DIALOG = "Logging needs Taken Pro. Open Taken to continue."

    /** Profile > Reminder without Pro: no nudge is scheduled. */
    const val NUDGE_LOCKED = "The nudge needs Taken Pro"

    /** A restore found Pro. */
    const val RESTORED = "Restored. Taken Pro is on."

    /** A restore found nothing active: true for someone who never bought and for a plan that ended. */
    const val NOTHING_TO_RESTORE = "No active Taken Pro on this Google account."

    /** Profile > Taken Pro for a lifetime member whose subscription still renews. */
    const val RENEWING_NEXT_TO_PRO_FOR_GOOD = "Your subscription still renews. Taken Pro is yours for good, so you can cancel it."

    /** How a subscription renews and where to cancel it (SPEC-ANDROID 9.6). */
    const val RENEWAL_TERMS = "Renews automatically until cancelled. Cancel anytime in Google Play."
    const val LIFETIME_TERMS = "One payment. Yours for good."

    /**
     * Play's Subscriptions policy: say "whether a subscription is required to use the app", and make clear the content
     * can be used without the offer (https://support.google.com/googleplay/android-developer/answer/9900533).
     */
    const val NEEDS_PRO = "Logging needs Taken Pro after your first dose. Your record stays readable without it."

    /** A pending purchase (a slow card, a family approval): Play's PENDING state grants nothing yet. */
    const val WAITING = "Waiting for approval. Taken Pro turns on as soon as it goes through."

    /**
     * Profile > Taken Pro: on Android a restore needs no button. Google: call `queryPurchasesAsync()` when the app starts
     * and in `onResume()`, which returns the account's purchases from any phone
     * (https://developer.android.com/google/play/billing/integrate).
     */
    const val RESTORE_AUTOMATIC = "Restore is automatic. Taken checks Google Play for your purchases each time it opens."

    /** Google Play could not be reached, or did not answer in time. */
    const val NO_CONNECTION = "No connection to Google Play. Try again."
    const val DID_NOT_FINISH = "Google Play did not finish that. Try again."
    const val NOT_SOLD_HERE = "Taken Pro is not sold in this country yet."
    const val CANNOT_PAY_HERE = "Google Play cannot take payments on this phone or account right now."
    const val PLANS_LOADING = "Plans are still loading. Try again in a moment."

    /**
     * What a failed Play call says (SPEC-ANDROID 9.3), from Google's response codes
     * (https://developer.android.com/google/play/billing/errors). Null when it says nothing: the person cancelled, or the
     * call worked.
     */
    fun failure(response: PlayResponse): String? = when (response) {
        PlayResponse.OK, PlayResponse.USER_CANCELED -> null
        PlayResponse.SERVICE_UNAVAILABLE, PlayResponse.NETWORK_ERROR, PlayResponse.SERVICE_DISCONNECTED,
        PlayResponse.SERVICE_TIMEOUT,
        -> NO_CONNECTION
        // "The Play Store app on the user's device is out of date", "the user is in an unsupported country", purchases
        // turned off by an admin, or a payment method Play cannot charge (BillingResponseCode.BILLING_UNAVAILABLE).
        PlayResponse.BILLING_UNAVAILABLE, PlayResponse.FEATURE_NOT_SUPPORTED -> CANNOT_PAY_HERE
        PlayResponse.ITEM_UNAVAILABLE -> NOT_SOLD_HERE
        PlayResponse.DEVELOPER_ERROR, PlayResponse.ERROR, PlayResponse.ITEM_ALREADY_OWNED, PlayResponse.ITEM_NOT_OWNED,
        -> DID_NOT_FINISH
    }

    /** The whole introductory span: "7 days", "1 month". */
    fun span(intro: IntroTerms): String {
        val days = intro.period.days
        if (days != null) {
            val total = days * maxOf(intro.periodCount, 1)
            return if (total == 1) "1 day" else "$total days"
        }
        val total = intro.period.value * maxOf(intro.periodCount, 1)
        val word = intro.period.unitWord
        return if (total == 1) "1 $word" else "$total ${word}s"
    }

    /** "7 days on us", for an introductory offer that costs nothing. Null for any other kind. */
    fun introTag(intro: IntroTerms?): String? {
        if (intro == null || intro.mode != IntroTerms.Mode.ON_US) return null
        return "${span(intro)} on us"
    }

    /** The card's billed amount and its unit: ("$19.99", "/ year"), ("$49.99", "once"). */
    fun price(offer: PlanOffer): Pair<String, String> {
        val period = offer.period ?: return offer.displayPrice to "once"
        val unit = if (period.value == 1) "/ ${period.unitWord}" else "/ ${period.value} ${period.unitWord}s"
        return offer.displayPrice to unit
    }

    /**
     * "about $1.67 / month", under a yearly price. Smaller than the billed amount, which stays the headline: Play's policy
     * names "Annual subscriptions that most prominently display their pricing in terms of monthly cost" as a violation.
     */
    fun monthlyEquivalent(offer: PlanOffer): String? {
        val period = offer.period ?: return null
        if (period.unit != PlanPeriod.PeriodUnit.YEAR) return null
        val months = period.months ?: return null
        if (months <= 0) return null
        val currency = runCatching { Currency.getInstance(offer.currencyCode) }.getOrNull() ?: return null
        val format = NumberFormat.getCurrencyInstance(offer.locale)
        format.currency = currency
        val digits = maxOf(currency.defaultFractionDigits, 0)
        format.minimumFractionDigits = digits
        format.maximumFractionDigits = digits
        val perMonth = offer.price.divide(BigDecimal(months), digits, RoundingMode.HALF_EVEN)
        return "about ${format.format(perMonth)} / month"
    }

    /** The introductory offer the person can still have on this plan, if any. */
    fun liveIntro(offer: PlanOffer?, eligible: Boolean): IntroTerms? {
        if (!eligible || offer == null || !offer.plan.isSubscription) return null
        return offer.intro
    }

    /** The primary button: "Start 7 days on us" while the offer applies, "Continue" otherwise. */
    fun cta(offer: PlanOffer?, eligible: Boolean): String {
        val tag = introTag(liveIntro(offer, eligible))
        return if (tag != null) "Start $tag" else "Continue"
    }

    /**
     * The plain terms line under the button, for the selected plan: "7 days on us, then $19.99 per year. Renews
     * automatically until cancelled. Cancel anytime in Google Play."
     */
    fun terms(offer: PlanOffer, eligible: Boolean): String {
        val period = offer.period ?: return LIFETIME_TERMS
        val recurring = "${offer.displayPrice} ${per(period)}"
        var lead = "$recurring."
        val intro = liveIntro(offer, eligible)
        if (intro != null) {
            lead = when (intro.mode) {
                IntroTerms.Mode.ON_US -> "${span(intro)} on us, then $recurring."
                IntroTerms.Mode.PAY_AS_YOU_GO -> "${intro.displayPrice} ${per(intro.period)} for ${span(intro)}, then $recurring."
                IntroTerms.Mode.PAY_UP_FRONT -> "${intro.displayPrice} for ${span(intro)}, then $recurring."
            }
        }
        return "$lead $RENEWAL_TERMS"
    }

    /** The terms line before Play has answered: true for every subscription, exact for none. */
    fun termsWithoutPrices(plan: ProPlan): String = if (plan.isSubscription) RENEWAL_TERMS else LIFETIME_TERMS

    /** "per year", "every 3 months". */
    fun per(period: PlanPeriod): String =
        if (period.value == 1) "per ${period.unitWord}" else "every ${period.value} ${period.unitWord}s"

    /** "a year", "every 3 months": how the trial timeline and the trial reminder say what follows the trial. */
    fun perPlain(period: PlanPeriod): String =
        if (period.value == 1) "a ${period.unitWord}" else "every ${period.value} ${period.unitWord}s"

    /** "$19.99 a year", from Play's formatted price and period. */
    fun renewal(price: PlanPrice): String = "${price.displayPrice} ${perPlain(price.period)}"

    // MARK: The trial promise (2026-10-21)

    /**
     * The whole introductory span in days: a day or week offer by count, a month or year one on the calendar from `now`,
     * so "1 month" from 21 Oct is 31 days.
     */
    fun trialDays(intro: IntroTerms, from: Instant, zone: ZoneId = ZoneId.systemDefault()): Int {
        val days = intro.period.days
        if (days != null) return days * maxOf(intro.periodCount, 1)
        val count = (intro.period.value * maxOf(intro.periodCount, 1)).toLong()
        val start = from.atZone(zone)
        val end = if (intro.period.unit == PlanPeriod.PeriodUnit.YEAR) start.plusYears(count) else start.plusMonths(count)
        return ChronoUnit.DAYS.between(start.toLocalDate(), end.toLocalDate()).toInt()
    }

    /**
     * The three steps under the yearly plan while its introductory offer costs nothing and Play offers it to this person:
     * "Today: full Pro", "Day 4: we remind you", "Day 7: $19.99 a year starts". Built from Play's trial length, formatted
     * price and period; the reminder day is the trial length minus `TrialReminder.LEAD_DAYS`, a trial of 3 days or less
     * has no reminder step, and nor does it when notifications are turned off for Taken (`remindable` false). Empty when
     * there is no such offer.
     */
    fun trialTimeline(
        offer: PlanOffer?,
        eligible: Boolean,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
        remindable: Boolean = true,
    ): List<TrialStep> {
        if (offer == null) return emptyList()
        val price = PlanPrice.of(offer) ?: return emptyList()
        val intro = liveIntro(offer, eligible) ?: return emptyList()
        if (intro.mode != IntroTerms.Mode.ON_US) return emptyList()
        val days = trialDays(intro, now, zone)
        if (days < 1) return emptyList()
        val steps = mutableListOf(TrialStep("Today", "full Pro"))
        if (remindable && days > TrialReminder.LEAD_DAYS) {
            steps.add(TrialStep("Day ${days - TrialReminder.LEAD_DAYS}", "we remind you"))
        }
        steps.add(TrialStep("Day $days", "${renewal(price)} starts"))
        return steps
    }

    /** The slim bar under Today's progress line in locked mode. */
    fun lockedBar(eligible: Boolean?, intro: IntroTerms?): String {
        val tag = introTag(intro)
        if (eligible == true && tag != null) return "Start $tag"
        if (eligible == false) return "Pro ended. Tap to continue"
        return "Taken Pro. Tap to continue"
    }

    /**
     * Profile > Taken Pro's status line on Android (SPEC-ANDROID 9.5): "Pro lifetime", "Trial · ends 1 Nov" (a trial
     * known on this phone), "Pro yearly · renewing", "Pro yearly · not renewing", the monthly equivalents, "Not active".
     * A phone never sees a subscription's period end (the Purchase reference names none,
     * https://developer.android.com/reference/com/android/billingclient/api/Purchase), so no renewal date is shown.
     * Active Pro with no reason (a debug build, or a pro.json written by a later version with a reason this one cannot
     * read) says "Taken Pro": the line and Profile's lit dot follow one predicate, `isActive`, so they never disagree.
     */
    fun statusLine(status: ProStatus?, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        if (status == null || !status.isActive(now)) return "Not active"
        return when (status.reason) {
            ProReason.FOUNDING -> "Founding member · Pro for life"
            ProReason.LIFETIME -> "Pro lifetime"
            ProReason.TRIAL -> {
                val end = status.expiresAt ?: return "Trial"
                if (end <= now) "Trial · renewing" else "Trial · ends ${Fmt.shortDate(end, year = false, zone = zone)}"
            }
            ProReason.YEARLY, ProReason.MONTHLY -> {
                val name = if (status.reason == ProReason.YEARLY) "Pro yearly" else "Pro monthly"
                if (status.willRenew == false) "$name · not renewing" else "$name · renewing"
            }
            ProReason.NONE -> ACTIVE_WITHOUT_REASON
        }
    }

    /** Profile's status line for active Pro whose reason is unknown. */
    const val ACTIVE_WITHOUT_REASON = "Taken Pro"

    /** Every fixed line, for the copy rules test. */
    val all: List<String>
        get() = listOf(
            HEADLINE, SUBLINE, SUBLINE_LINES, LOCKED_DIALOG, NUDGE_LOCKED, RESTORED, NOTHING_TO_RESTORE,
            RENEWING_NEXT_TO_PRO_FOR_GOOD, RENEWAL_TERMS, LIFETIME_TERMS, NEEDS_PRO, WAITING, RESTORE_AUTOMATIC,
            NO_CONNECTION, DID_NOT_FINISH, NOT_SOLD_HERE, CANNOT_PAY_HERE, PLANS_LOADING,
        ) + features
}
