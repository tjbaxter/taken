package com.tombaxter.taken.billing

import android.app.Activity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.tombaxter.taken.OffersPhase
import com.tombaxter.taken.ProSource
import com.tombaxter.taken.PurchaseOutcome
import com.tombaxter.taken.RestoreOutcome
import com.tombaxter.taken.core.pro.Entitlement
import com.tombaxter.taken.core.pro.PlanOffer
import com.tombaxter.taken.core.pro.PlayCatalog
import com.tombaxter.taken.core.pro.PlayEntitlement
import com.tombaxter.taken.core.pro.PlayPlan
import com.tombaxter.taken.core.pro.PlayPurchase
import com.tombaxter.taken.core.pro.PlayResponse
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProLedgers
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.lang.ref.WeakReference
import java.time.Instant
import java.util.Locale

/**
 * Taken Pro through Google Play Billing (SPEC-ANDROID 9), the Android counterpart of the iPhone's Taken/Pro/ProStore.swift.
 * It asks Play when Taken starts and on every resume, works the answer out with the pure rules in :core (Play.kt,
 * Entitlement.kt) and keeps it in pro.json, where the widgets, the tile and the nudge read it. No server: everything Play
 * says stays on the phone (SPEC-ANDROID 13).
 *
 * Google's lifecycle, as the integrate page documents it (https://developer.android.com/google/play/billing/integrate):
 * connect "when your app is launched or comes to the foreground"; `queryPurchasesAsync()` after connecting and in
 * `onResume()`; `queryProductDetailsAsync()` for the paywall; `launchBillingFlow()` with the offer token; every update
 * through the one PurchasesUpdatedListener; grant only PURCHASED; acknowledge within three days, never while PENDING.
 */
class ProStore(
    private val gateway: BillingGateway,
    /** pro.json's read-modify-write (`Persistence.updateLedger`). */
    private val writeLedger: ((ProLedger?) -> ProLedger?) -> Unit,
    private val scope: CoroutineScope,
    private val clock: () -> Instant = { Instant.now() },
    private val locale: () -> Locale = { Locale.getDefault() },
    /** Never keep the app waiting on Play: after this long the cached answer stands (the iPhone's 4 s). */
    private val settleTimeoutMillis: Long = 4_000,
) : ProSource {
    override var status: ProStatus? by mutableStateOf(null)
        private set
    override var settled: Boolean by mutableStateOf(false)
        private set
    override var introEligible: Boolean? by mutableStateOf(null)
        private set
    override var offers: Map<ProPlan, PlanOffer> by mutableStateOf(emptyMap())
        private set
    override var offersPhase: OffersPhase by mutableStateOf(OffersPhase.IDLE)
        private set
    override var waitingForApproval: Boolean by mutableStateOf(false)
        private set
    override var heldSubscription: ProPlan? by mutableStateOf(null)
        private set

    /** Play's answer to the last connection or purchases question. */
    var lastResponse: PlayResponse? by mutableStateOf(null)
        private set

    private var ledger: ProLedger? = null
    private var answered = false
    private var started = false
    private var plans: Map<ProPlan, PlayPlan> = emptyMap()
    private var purchases: List<PlayPurchase> = emptyList()
    private var onChange: () -> Unit = {}
    private var activity: WeakReference<Activity>? = null
    private val settleWaiters = ArrayList<CompletableDeferred<Unit>>()
    private var settleGeneration = 0
    private var refreshing: Deferred<Boolean>? = null
    private var loading: Deferred<Unit>? = null
    private var buying: CompletableDeferred<PurchaseOutcome>? = null
    private var buyingPlan: PlayPlan? = null
    private val acknowledging = HashSet<String>()

    init {
        gateway.setPurchasesListener { response, updated -> scope.launch { purchasesUpdated(response, updated) } }
    }

    override fun listen(onChange: () -> Unit) {
        this.onChange = onChange
    }

    override fun attach(activity: Activity?) {
        this.activity = activity?.let { WeakReference(it) }
    }

    /** pro.json as last read. Its status stands until Play has answered this launch. */
    override fun adoptLedger(ledger: ProLedger?) {
        this.ledger = ledger
        if (!answered) status = ledger?.status
    }

    private fun updateLedger(transform: (ProLedger?) -> ProLedger?) {
        ledger = transform(ledger)
        writeLedger(transform)
    }

    // MARK: Lifecycle

    override fun foreground() {
        if (!started) {
            started = true
            armSettle()
            scope.launch {
                refresh()
                loadOffers()
            }
        } else if (PlayEntitlement.needsCheck(status, clock())) {
            // A subscription whose answer ran out while Taken was away: only Play knows, so no lock until it answers.
            settled = false
            armSettle()
        }
        activity?.get()?.let { gateway.showInAppMessages(it) { scope.launch { refresh() } } }
    }

    override fun resumed() {
        if (!started) return
        scope.launch { refresh() }
    }

    private fun armSettle() {
        settleGeneration += 1
        val generation = settleGeneration
        scope.launch {
            delay(settleTimeoutMillis)
            if (settleGeneration == generation) markSettled()
        }
    }

    override suspend fun settle() {
        if (settled) return
        val waiter = CompletableDeferred<Unit>()
        settleWaiters.add(waiter)
        waiter.await()
    }

    private fun markSettled() {
        if (settled) return
        settled = true
        val waiting = settleWaiters.toList()
        settleWaiters.clear()
        waiting.forEach { it.complete(Unit) }
    }

    // MARK: Entitlement

    /** Asks Play again. True when Pro itself changed. Calls made while one is running share it. */
    override suspend fun refresh(): Boolean {
        refreshing?.let { return it.await() }
        val task = scope.async { performRefresh() }
        refreshing = task
        return try {
            task.await()
        } finally {
            if (refreshing === task) refreshing = null
        }
    }

    private suspend fun performRefresh(): Boolean {
        val connected = gateway.connect()
        if (connected != PlayResponse.OK) {
            lastResponse = connected
            markSettled()
            return false
        }
        val answer = gateway.queryPurchases()
        lastResponse = answer.response
        val changed = applyPurchases(answer.value, answered = answer.response == PlayResponse.OK)
        markSettled()
        return changed
    }

    /** Play's purchases become the cached answer. Returns true when Pro itself changed. */
    private fun applyPurchases(found: List<PlayPurchase>, answered: Boolean): Boolean {
        if (answered) {
            purchases = found
            this.answered = true
        }
        waitingForApproval = PlayEntitlement.hasPending(purchases)
        heldSubscription = PlayEntitlement.heldSubscription(purchases)
        acknowledge(PlayEntitlement.toAcknowledge(found))
        val now = clock()
        val fresh = PlayEntitlement.status(found, ledger?.trialEnds.orEmpty(), now)
        val previous = status
        val next = Entitlement.next(previous, fresh, answered)
        status = next
        if (next != null) updateLedger { ProLedgers.withStatus(it, next) }
        val changed = !PlayEntitlement.sameEntitlement(previous, next)
        if (changed) onChange()
        return changed
    }

    /**
     * Acknowledges each purchase once, retrying with Google's exponential backoff (2 s, then 4 s, 3 tries, the errors
     * page's acknowledgement sample, https://developer.android.com/google/play/billing/errors). One missed now is
     * acknowledged on the next query, well inside Play's three days.
     */
    private fun acknowledge(tokens: List<String>) {
        for (token in tokens) {
            if (!acknowledging.add(token)) continue
            scope.launch {
                var wait = ACKNOWLEDGE_FIRST_DELAY_MS
                for (attempt in 1..ACKNOWLEDGE_TRIES) {
                    val answer = gateway.acknowledge(token)
                    if (answer == PlayResponse.OK || !answer.retriable) break
                    if (attempt < ACKNOWLEDGE_TRIES) {
                        delay(wait)
                        wait *= 2
                    }
                }
                acknowledging.remove(token)
            }
        }
    }

    // MARK: Plans

    /** Loads the three products. Prices, periods and the trial always come from here. */
    override suspend fun loadOffers(force: Boolean) {
        loading?.let { return it.await() }
        if (offersPhase == OffersPhase.READY && !force) return
        val task = scope.async { performLoad() }
        loading = task
        try {
            task.await()
        } finally {
            if (loading === task) loading = null
        }
    }

    private suspend fun performLoad() {
        offersPhase = OffersPhase.LOADING
        val connected = gateway.connect()
        if (connected != PlayResponse.OK) {
            lastResponse = connected
            offersPhase = OffersPhase.FAILED
            return
        }
        val answer = gateway.queryProducts()
        if (answer.response != PlayResponse.OK) {
            offersPhase = OffersPhase.FAILED
            return
        }
        val found = PlayCatalog.plans(answer.value, locale())
        plans = found
        offers = found.mapValues { it.value.offer }
        introEligible = PlayCatalog.introEligible(found)
        offersPhase = if (found.isEmpty()) OffersPhase.FAILED else OffersPhase.READY
        val prices = PlayCatalog.prices(found)
        if (prices.isNotEmpty()) updateLedger { ProLedgers.cachePrices(it, prices) }
    }

    // MARK: Buying

    override suspend fun purchase(plan: ProPlan): PurchaseOutcome {
        val chosen = plans[plan] ?: return PurchaseOutcome.Failed(ProCopy.PLANS_LOADING)
        // Already Pro on this Google account (bought on another phone, or a cache that ran out): nothing to sell, and
        // no second subscription next to the first.
        if (purchases.any { it.state == PlayPurchase.State.PURCHASED && it.plan != null }) {
            refresh()
            if (status?.isActive(clock()) == true) return PurchaseOutcome.Unlocked(trialStarted = false)
        }
        val host = activity?.get() ?: return PurchaseOutcome.Failed(ProCopy.DID_NOT_FINISH)
        val waiter = CompletableDeferred<PurchaseOutcome>()
        buying = waiter
        buyingPlan = chosen
        val launched = gateway.launch(host, chosen.productId, chosen.offerToken)
        val outcome = when (launched) {
            PlayResponse.OK -> waiter.await()
            PlayResponse.USER_CANCELED -> PurchaseOutcome.Cancelled
            // "Call queryPurchasesAsync()": in most cases the item is already owned (errors page).
            PlayResponse.ITEM_ALREADY_OWNED -> owned()
            else -> PurchaseOutcome.Failed(ProCopy.failure(launched) ?: ProCopy.DID_NOT_FINISH)
        }
        buying = null
        buyingPlan = null
        return outcome
    }

    private suspend fun owned(): PurchaseOutcome {
        refresh()
        return if (status?.isActive(clock()) == true) PurchaseOutcome.Unlocked(trialStarted = false) else PurchaseOutcome.Failed(ProCopy.DID_NOT_FINISH)
    }

    /** Every purchase flow's result, and purchases that finish while Taken runs (a pending one approved, a promo code). */
    private suspend fun purchasesUpdated(response: PlayResponse, updated: List<PlayPurchase>) {
        val waiter = buying
        when (response) {
            PlayResponse.OK -> {
                val ours = updated.filter { it.plan != null }
                // A trial is known only on the phone that bought it: keep its end, by the purchase time it began at.
                val bought = buyingPlan
                val trial = bought?.trial
                if (bought != null && trial != null) {
                    for (purchase in ours) {
                        if (purchase.state == PlayPurchase.State.PURCHASED && bought.productId in purchase.productIds) {
                            val end = PlayEntitlement.trialEnd(purchase.purchaseTime, trial)
                            updateLedger { ProLedgers.recordTrialEnd(it, purchase.purchaseTime, end) }
                        }
                    }
                }
                val merged = purchases.filter { old -> ours.none { it.token == old.token } } + ours
                purchases = merged
                // A purchase found always counts; a full answer from Play follows.
                applyPurchases(merged, answered = false)
                val outcome = when {
                    ours.any { it.state == PlayPurchase.State.PURCHASED } && status?.isActive(clock()) == true ->
                        PurchaseOutcome.Unlocked(trialStarted = status?.reason == com.tombaxter.taken.core.pro.ProReason.TRIAL)
                    ours.any { it.state == PlayPurchase.State.PENDING } -> PurchaseOutcome.Pending
                    else -> PurchaseOutcome.Failed(ProCopy.DID_NOT_FINISH)
                }
                waiter?.complete(outcome)
                refresh()
            }
            PlayResponse.USER_CANCELED -> waiter?.complete(PurchaseOutcome.Cancelled)
            PlayResponse.ITEM_ALREADY_OWNED -> waiter?.complete(owned())
            else -> waiter?.complete(PurchaseOutcome.Failed(ProCopy.failure(response) ?: ProCopy.DID_NOT_FINISH))
        }
    }

    /** Asks Play again, for the paywall's Restore. */
    override suspend fun restore(): RestoreOutcome {
        refresh()
        val answer = lastResponse
        if (answer != PlayResponse.OK) return RestoreOutcome.Failed(answer?.let { ProCopy.failure(it) } ?: ProCopy.NO_CONNECTION)
        return if (status?.isActive(clock()) == true) RestoreOutcome.Restored else RestoreOutcome.Nothing
    }

    companion object {
        /** Google's acknowledgement sample: 3 tries, 2 s then 4 s apart (errors page). */
        const val ACKNOWLEDGE_TRIES = 3
        const val ACKNOWLEDGE_FIRST_DELAY_MS = 2_000L
    }
}
