package com.tombaxter.taken

import android.app.Activity
import com.tombaxter.taken.core.pro.PlanOffer
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import java.time.Instant

/** Where the paywall's plans are: not asked yet, on their way, back, or not available. */
enum class OffersPhase { IDLE, LOADING, READY, FAILED }

/** What a purchase in the paywall came to. */
sealed interface PurchaseOutcome {
    /** Taken Pro is on. `trialStarted`: it began with the yearly trial, so the trial ask may follow (SPEC-ANDROID 10.4). */
    data class Unlocked(val trialStarted: Boolean) : PurchaseOutcome

    /** Play's PENDING state: a slow card or a family approval. Pro turns on when it goes through. */
    data object Pending : PurchaseOutcome

    data object Cancelled : PurchaseOutcome

    data class Failed(val text: String) : PurchaseOutcome
}

/** What asking Play again came to. */
sealed interface RestoreOutcome {
    data object Restored : RestoreOutcome

    data object Nothing : RestoreOutcome

    data class Failed(val text: String) : RestoreOutcome
}

/**
 * Where Taken Pro's answer comes from (SPEC-ANDROID 9). Release builds use [com.tombaxter.taken.billing.ProStore] over
 * Google Play Billing; debug builds, which carry the `.debug` package Play sells nothing to, and the tests use a fixed
 * source (`BuildWiring`). The fields the screens read are Compose state in every implementation.
 */
interface ProSource {
    /** The best answer so far: pro.json's at launch, then Play's. */
    val status: ProStatus?

    /** Play has answered this launch, or the wait for it ran out (4 s). */
    val settled: Boolean

    /** Whether Play offers this person the yearly trial. Null until the yearly plan has loaded. */
    val introEligible: Boolean?

    /** The paywall's plans, as Play returned them. */
    val offers: Map<ProPlan, PlanOffer> get() = emptyMap()

    val offersPhase: OffersPhase get() = OffersPhase.READY

    /** A purchase of Taken Pro is waiting for approval. */
    val waitingForApproval: Boolean get() = false

    /** The subscription this Google account holds, for Profile's Manage subscription. */
    val heldSubscription: ProPlan? get() = status?.takeIf { it.isPro }?.plan

    /** Waits for Play's first answer of this launch, at most a few seconds. */
    suspend fun settle() {}

    /** Asks Play again. True when Pro itself changed. */
    suspend fun refresh(): Boolean = false

    /** Loads the three products (each time the paywall opens). */
    suspend fun loadOffers(force: Boolean = false) {}

    suspend fun purchase(plan: ProPlan): PurchaseOutcome = PurchaseOutcome.Cancelled

    suspend fun restore(): RestoreOutcome = RestoreOutcome.Nothing

    /** Taken came to the front (`ON_START`): connects, and waits for Play before an answer that ran out can lock. */
    fun foreground() {}

    /** `ON_RESUME`: Google asks for `queryPurchasesAsync` here (https://developer.android.com/google/play/billing/integrate). */
    fun resumed() {}

    /** The activity Play's purchase screen and its in-app messages need, while one is alive. */
    fun attach(activity: Activity?) {}

    /** pro.json as last read: its cached status before Play answers, the trials it recorded, the prices. */
    fun adoptLedger(ledger: ProLedger?) {}

    /** `onChange` runs when Pro itself changes (not when it was only checked): widgets and reminders follow it. */
    fun listen(onChange: () -> Unit) {}

    companion object {
        /** Debug builds: Pro reads as on, for good, so a developer install is never locked out (it cannot buy). */
        val untilBilling: ProSource = fixed(ProStatus(isPro = true, reason = ProReason.NONE, checkedAt = Instant.EPOCH))

        /** No Pro, Play has answered: locked mode after the first dose. */
        val locked: ProSource = fixed(null)

        fun fixed(status: ProStatus?, eligible: Boolean? = true): ProSource = object : ProSource {
            override val status = status
            override val settled = true
            override val introEligible = eligible
        }
    }
}
