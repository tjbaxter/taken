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
import com.tombaxter.taken.data.MemoryWeightPersistence
import com.tombaxter.taken.core.weight.WeighIn
import com.tombaxter.taken.core.weight.WeightGoal
import com.tombaxter.taken.core.weight.WeightState
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.core.weight.day
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
        val allTaken = screen == "today-done" || WeightDemo.allTaken(screen)
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
        // The Weight screens' chart gets its weekly dose ticks, and the offer its weekly shot.
        if (WeightDemo.addsWeeklyShot(screen)) state = DemoData.withWeeklyShot(state, now, zone)
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
            "today-weight-offer" -> TodayPrompt.WeightOffer
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
            launchTab = when {
                screen == "log" || screen == "day" -> AppTab.HISTORY
                WeightDemo.opensOnWeight(screen) -> AppTab.WEIGHT
                else -> AppTab.TODAY
            },
            launchEditing = screen == "today-edit",
            demoPrompt = prompt,
            weightModel = WeightDemo.model(screen, now),
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
            "weight-list" -> model.sheet = Sheet.WeighIns
            "weight-settings", "weight-data" -> model.openProfile()
            "weight-goal-sheet", "weight-goal-low" -> model.sheet = Sheet.WeightGoal
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
                "locked", "paywall", "paywall-intro", "settings-pro-locked", "weight-locked" -> DemoPro(null)
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

/**
 * The Weight tab's demo screens (debug only), ported from Shared/WeightData.swift `WeightDemo` and WeightModel.demo:
 * screen one as it opens (`weight`), typing (`weight-entry`, `weight-entry-range`), never weighed in (`weight-empty`),
 * weighed in today (`weight-weighed`), locked (`weight-locked`), in pounds (`weight-lb`); screen two (`weight-first`,
 * `weight-trend`); All weigh-ins (`weight-list`); Profile at the Weight switch and the CSV rows (`weight-settings`,
 * `weight-data`); the goal's (`weight-goal`, `weight-goal-saved`, `weight-goal-moment`, `weight-goal-reached`,
 * `weight-goal-reached-moment`, `weight-goal-sheet`, `weight-goal-low`); and `today-weight-offer`.
 */
object WeightDemo {
    val pageScreens = listOf(
        "weight", "weight-entry", "weight-entry-range", "weight-empty", "weight-first", "weight-weighed", "weight-trend",
        "weight-locked", "weight-lb", "weight-list", "weight-settings", "weight-data",
    )
    val goalScreens = listOf(
        "weight-goal", "weight-goal-saved", "weight-goal-moment", "weight-goal-reached", "weight-goal-reached-moment",
        "weight-goal-sheet", "weight-goal-low",
    )

    /** The screens that open on the Weight tab (Profile's two open over it). */
    fun opensOnWeight(screen: String?): Boolean = screen != null && (screen in pageScreens || screen in goalScreens)

    /** The goal screens: Tom-like history from 97.8 kg, the goal 87.0 and 180 cm (`DemoData.goalWeighIns`). */
    fun hasGoal(screen: String?): Boolean = screen in goalScreens

    /** The goal's history six weeks on, down to about 86.8 and holding. */
    fun goalReached(screen: String?): Boolean = screen == "weight-goal-reached" || screen == "weight-goal-reached-moment"

    /** What the goal field holds on `weight-goal-low`. */
    fun typedGoal(screen: String?): String? = if (screen == "weight-goal-low") "55.0" else null

    /** What the entry screens type. */
    fun draft(screen: String?): String? = when (screen) {
        "weight-entry" -> "88.1"
        "weight-entry-range" -> "883"
        else -> null
    }

    /** The screens shown scrolled to screen two. */
    fun opensOnTrend(screen: String?): Boolean = screen in listOf("weight-first", "weight-trend", "weight-goal", "weight-goal-reached")

    /** The history includes a weigh-in today; elsewhere it ends yesterday, so the line reads "yesterday". */
    fun includesToday(screen: String?): Boolean = screen in listOf("weight-weighed", "weight-list", "weight-settings", "weight-data")

    /** Pounds (`weight-lb`); every other capture is in kilograms, so they read the same everywhere. */
    fun unit(screen: String?): WeightUnit = if (screen == "weight-lb") WeightUnit.LB else WeightUnit.KG

    /** The tab is on for every Weight screen and off everywhere else, so the other captures still show the default app. */
    fun showsTab(screen: String?): Boolean = opensOnWeight(screen)

    /** Weigh-ins everywhere the tab is on but `weight-empty`. */
    fun hasWeighIns(screen: String?): Boolean = opensOnWeight(screen) && screen != "weight-empty"

    /** A weekly shot in the stack, for the chart's dose ticks and the offer's medicine. */
    fun addsWeeklyShot(screen: String?): Boolean = hasWeighIns(screen) || screen == "today-weight-offer"

    /** Today with everything taken, as the offer needs. */
    fun allTaken(screen: String?): Boolean = screen == "today-weight-offer"

    /**
     * The Weight tab's model for a screen: in memory, the tab on for the Weight screens with a flat-to-gently-falling
     * line of weigh-ins (ending yesterday unless the screen is about today), in kilograms (pounds on `weight-lb`); off and
     * empty for every other screen. The goal screens get Tom-like history, the goal and the height, and the in-memory
     * state their line needs (a save on this visit, a point just lit).
     */
    fun model(screen: String, now: Instant): WeightModel {
        val zone = DemoScreens.zone
        val clock = com.tombaxter.taken.core.day.DayClock(DemoData.settings.dayStartHour, zone)
        val state = WeightState()
        if (showsTab(screen)) {
            state.showsTab = true
            state.unit = unit(screen)
        }
        if (hasGoal(screen)) {
            state.weighIns = DemoData.goalWeighIns(
                now, extraWeeks = if (goalReached(screen)) 6 else 0, momentKg = if (screen == "weight-goal-moment") 87.1 else null, zone = zone,
            )
            state.weighIns.minOfOrNull { clock.day(it) }?.let { first ->
                state.goal = WeightGoal(87.0, first)
                state.heightCm = 180.0
            }
        } else if (screen == "weight-first") {
            // The first weigh-in, this morning: screen two with one dot.
            val at = clock.date(clock.day(now), 7, 6)
            state.weighIns = listOf(WeighIn(kg = 88.35, weighedAt = at, utcOffset = com.tombaxter.taken.core.day.DayClock.offset(zone, at)))
        } else if (hasWeighIns(screen)) {
            state.weighIns = DemoData.weighIns(now, includeToday = includesToday(screen), zone = zone)
        }
        state.firstWeighInAt = state.weighIns.minOfOrNull { it.weighedAt }
        val model = WeightModel(MemoryWeightPersistence(state), state, clockNow = { now }, locale = { Locale.US }, isDemo = true)
        model.demoTypedGoal = typedGoal(screen)
        model.demoOpensOnTrend = opensOnTrend(screen)
        draft(screen)?.let {
            model.draft = it
            model.entryRequested = true
        }
        val moments = model.moments(clock)
        when (screen) {
            "weight-goal-moment" -> {
                model.justReached = moments.firstOrNull { it.kind == com.tombaxter.taken.core.weight.WeightMoment.Kind.Percent(10) }
                model.justSaved = model.state.last?.id
            }
            "weight-goal-reached-moment" -> {
                model.justReached = moments.firstOrNull { it.isGoal }
                model.justSaved = model.state.last?.id
            }
            "weight-goal-saved" -> model.justSaved = model.state.last?.id
        }
        return model
    }
}
