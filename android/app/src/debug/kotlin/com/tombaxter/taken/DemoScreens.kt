package com.tombaxter.taken

import com.tombaxter.taken.core.catalog.FrequencyChoice
import com.tombaxter.taken.core.demo.DemoData
import com.tombaxter.taken.core.demo.DemoStack
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.PlanOffer
import com.tombaxter.taken.core.pro.of
import com.tombaxter.taken.core.pro.PlayCatalog
import com.tombaxter.taken.core.pro.PlayOneTimeOffer
import com.tombaxter.taken.core.pro.PlayPhase
import com.tombaxter.taken.core.pro.PlayProduct
import com.tombaxter.taken.core.pro.PlaySubscriptionOffer
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
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

    /** Taken Pro's screens (SPEC-ANDROID 9.5 and 9.6): the paywall's states, Today's trial notice, Profile's Pro states. */
    val proScreens = listOf(
        "paywall", "paywall-intro", "paywall-trial-used", "paywall-no-yearly", "paywall-loading", "paywall-offline",
        "today-trial-notice", "settings-pro-trial", "settings-pro-yearly", "settings-pro-yearly-ending",
        "settings-pro-monthly", "settings-pro-lifetime", "settings-pro-locked", "settings-pro-pending",
    )

    /** The Pro screens drawn in every look; the rest in Signal. */
    val proScreensEveryLook = listOf("paywall", "locked", "settings-pro-trial", "settings-pro-yearly", "settings-pro-lifetime", "settings-pro-locked")

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
        if (screen == "paywall-intro") {
            // The first run: a stack just added and its first dose, the moment the intro paywall follows.
            val first = state.items.first { it.name == "Vitamin D3" }
            state = state.copy(doses = listOf(com.tombaxter.taken.core.stack.doseAt(first.id, now.minusSeconds(2), zone)))
        }
        val persistence = MemoryPersistence(stack = state)
        val ledger = ProLedger(firstSeenAt = now.minusSeconds(86_400L * 60), firstDoseAt = state.doses.minOfOrNull { it.takenAt })
        val pro = DemoPro.forScreen(screen, now)
        val prompt = when (screen) {
            // The trial reminder's words on Today, from the moment it would have come (notifications not built yet).
            "today-trial-notice" -> com.tombaxter.taken.core.reminders.TrialReminder.notice(
                pro.status, pro.offers[ProPlan.YEARLY]?.let { com.tombaxter.taken.core.pro.PlanPrice.of(it) }, state, now, zone,
            )?.let { TodayPrompt.TrialEnds(it) }
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
            pro = pro,
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
        if (screen.startsWith("settings-pro")) model.openProfile()
        if (screen.startsWith("paywall")) model.presentPaywall(if (screen == "paywall-intro") PaywallOrigin.INTRO else PaywallOrigin.BAR)
        return model
    }
}

/**
 * Taken Pro for the demo screens (debug only): fixed answers and the three plans in Play's own shapes, read through the
 * real catalog rules (`PlayCatalog`), as the iPhone's `-demo` uses StoreKit-shaped demo plans. Outside debug every
 * price, period and offer comes from Google Play.
 */
class DemoPro(
    override val status: ProStatus?,
    override val introEligible: Boolean? = true,
    override val offers: Map<ProPlan, PlanOffer> = DemoPlay.offers(trial = true),
    override val offersPhase: OffersPhase = OffersPhase.READY,
    override val waitingForApproval: Boolean = false,
    private val outcome: PurchaseOutcome = PurchaseOutcome.Cancelled,
) : ProSource {
    override val settled = true

    override suspend fun purchase(plan: ProPlan): PurchaseOutcome = outcome

    companion object {
        fun forScreen(screen: String, now: Instant): ProSource {
            val horizon = now.plus(com.tombaxter.taken.core.pro.PlayEntitlement.RENEWING_HORIZON)
            fun sub(reason: ProReason, plan: ProPlan, renews: Boolean = true, end: Instant = horizon) =
                ProStatus(isPro = true, reason = reason, checkedAt = now, expiresAt = end, willRenew = renews, plan = plan)
            return when (screen) {
                "locked", "paywall", "paywall-intro", "settings-pro-locked" -> DemoPro(null)
                "paywall-trial-used" -> DemoPro(null, introEligible = false, offers = DemoPlay.offers(trial = false))
                "paywall-no-yearly" -> DemoPro(null, introEligible = null, offers = DemoPlay.offers(trial = true) - ProPlan.YEARLY)
                "paywall-loading" -> DemoPro(null, introEligible = null, offers = emptyMap(), offersPhase = OffersPhase.LOADING)
                "paywall-offline" -> DemoPro(null, introEligible = null, offers = emptyMap(), offersPhase = OffersPhase.FAILED)
                "settings-pro-pending" -> DemoPro(null, waitingForApproval = true)
                // The paywall after its button: Play's PENDING answer, and Pro on with the trial.
                "paywall-pending" -> DemoPro(null, outcome = PurchaseOutcome.Pending)
                "paywall-unlocked" -> DemoPro(null, outcome = PurchaseOutcome.Unlocked(trialStarted = true))
                "today-trial-notice" -> DemoPro(sub(ProReason.TRIAL, ProPlan.YEARLY, end = now.plus(java.time.Duration.ofDays(2))))
                "settings-pro-trial" -> DemoPro(sub(ProReason.TRIAL, ProPlan.YEARLY, end = now.plus(java.time.Duration.ofDays(4))))
                "settings-pro-yearly" -> DemoPro(sub(ProReason.YEARLY, ProPlan.YEARLY))
                "settings-pro-yearly-ending" -> DemoPro(sub(ProReason.YEARLY, ProPlan.YEARLY, renews = false, end = now.plus(com.tombaxter.taken.core.pro.PlayEntitlement.ENDING_HORIZON)))
                "settings-pro-monthly" -> DemoPro(sub(ProReason.MONTHLY, ProPlan.MONTHLY))
                "settings-pro-lifetime" -> DemoPro(ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now))
                else -> ProSource.untilBilling
            }
        }
    }
}

/** The three plans as Play returns them for a US account: yearly with its 7-day trial offer, monthly, lifetime. */
object DemoPlay {
    private fun phase(price: String, micros: Long, period: String, cycles: Int = 0, recurrence: PlayPhase.Recurrence = PlayPhase.Recurrence.INFINITE) =
        PlayPhase(price, micros, "USD", period, cycles, recurrence)

    fun products(trial: Boolean): List<PlayProduct> {
        val yearlyBase = PlaySubscriptionOffer("yearly", null, "demo-yearly", listOf(phase("$19.99", 19_990_000, "P1Y")))
        val yearlyTrial = PlaySubscriptionOffer(
            "yearly", "trial-7d", "demo-yearly-trial",
            listOf(phase("Free", 0, "P1W", 1, PlayPhase.Recurrence.FINITE), phase("$19.99", 19_990_000, "P1Y")),
        )
        return listOf(
            PlayProduct(ProPlan.YEARLY.productId, subscriptionOffers = if (trial) listOf(yearlyBase, yearlyTrial) else listOf(yearlyBase)),
            PlayProduct(ProPlan.MONTHLY.productId, subscriptionOffers = listOf(PlaySubscriptionOffer("monthly", null, "demo-monthly", listOf(phase("$3.99", 3_990_000, "P1M"))))),
            PlayProduct(ProPlan.LIFETIME.productId, oneTimeOffers = listOf(PlayOneTimeOffer("$49.99", 49_990_000, "USD", "demo-lifetime", purchaseOptionId = "lifetime"))),
        )
    }

    fun offers(trial: Boolean): Map<ProPlan, PlanOffer> = PlayCatalog.plans(products(trial), Locale.US).mapValues { it.value.offer }
}
