package com.tombaxter.taken

import android.app.Activity
import com.tombaxter.taken.billing.BillingGateway
import com.tombaxter.taken.core.pro.PlayAnswer
import com.tombaxter.taken.core.pro.PlayOneTimeOffer
import com.tombaxter.taken.core.pro.PlayPhase
import com.tombaxter.taken.core.pro.PlayProduct
import com.tombaxter.taken.core.pro.PlayPurchase
import com.tombaxter.taken.core.pro.PlayResponse
import com.tombaxter.taken.core.pro.PlaySubscriptionOffer
import com.tombaxter.taken.core.pro.ProPlan
import kotlinx.coroutines.CompletableDeferred
import java.time.Instant

/**
 * Google Play, played by the tests (SPEC-ANDROID 9.7): a billing client that answers as Play would in each state a person
 * can be in, with no Play Store. `held` is what `queryPurchasesAsync` returns; `onLaunch` is what the purchase screen does
 * (the person buys, cancels, waits for approval).
 */
class FakeBilling(
    var connectAnswer: PlayResponse = PlayResponse.OK,
    var purchasesAnswer: PlayResponse = PlayResponse.OK,
    var productsAnswer: PlayResponse = PlayResponse.OK,
    var held: List<PlayPurchase> = emptyList(),
    var products: List<PlayProduct> = catalog(trial = true),
) : BillingGateway {
    private var listener: (PlayResponse, List<PlayPurchase>) -> Unit = { _, _ -> }

    /** When set, `connect()` waits for it: Play that never answers. */
    var hangConnect: CompletableDeferred<PlayResponse>? = null

    /** What the purchase screen does once open; null leaves it open (no answer yet). */
    var onLaunch: ((productId: String, offerToken: String) -> Unit)? = null

    /** What `launchBillingFlow` itself answers. */
    var launchAnswer: PlayResponse = PlayResponse.OK

    /** Acknowledgement answers in turn (then OK). */
    val acknowledgeAnswers = ArrayDeque<PlayResponse>()

    val launches = mutableListOf<Pair<String, String>>()
    val acknowledged = mutableListOf<String>()
    var connects = 0
    var purchaseQueries = 0
    var productQueries = 0
    var inAppMessages = 0

    override suspend fun connect(): PlayResponse {
        connects += 1
        hangConnect?.let { return it.await() }
        return connectAnswer
    }

    override suspend fun queryPurchases(): PlayAnswer<List<PlayPurchase>> {
        purchaseQueries += 1
        return PlayAnswer(purchasesAnswer, if (purchasesAnswer == PlayResponse.OK) held else emptyList())
    }

    override suspend fun queryProducts(): PlayAnswer<List<PlayProduct>> {
        productQueries += 1
        return PlayAnswer(productsAnswer, if (productsAnswer == PlayResponse.OK) products else emptyList())
    }

    override fun launch(activity: Activity, productId: String, offerToken: String): PlayResponse {
        launches.add(productId to offerToken)
        if (launchAnswer != PlayResponse.OK) return launchAnswer
        onLaunch?.invoke(productId, offerToken)
        return PlayResponse.OK
    }

    override suspend fun acknowledge(token: String): PlayResponse {
        acknowledged.add(token)
        val answer = acknowledgeAnswers.removeFirstOrNull() ?: PlayResponse.OK
        if (answer == PlayResponse.OK) held = held.map { if (it.token == token) it.copy(acknowledged = true) else it }
        return answer
    }

    override fun showInAppMessages(activity: Activity, onStatusUpdated: () -> Unit) {
        inAppMessages += 1
    }

    override fun setPurchasesListener(listener: (PlayResponse, List<PlayPurchase>) -> Unit) {
        this.listener = listener
    }

    /** Play's PurchasesUpdatedListener fires: a purchase flow's result, or a purchase finishing while Taken runs. */
    fun deliver(response: PlayResponse, purchases: List<PlayPurchase> = emptyList()) = listener(response, purchases)

    /** The person buys on Play's screen: the purchase is held from now on and the listener hears it. */
    fun buys(at: Instant, state: PlayPurchase.State = PlayPurchase.State.PURCHASED) {
        onLaunch = { productId, _ ->
            val purchase = purchase(productId, at = at, state = state, acknowledged = false)
            held = held + purchase
            deliver(PlayResponse.OK, listOf(purchase))
        }
    }

    companion object {
        fun purchase(
            productId: String,
            at: Instant,
            state: PlayPurchase.State = PlayPurchase.State.PURCHASED,
            autoRenewing: Boolean = ProPlan.fromProductId(productId)?.isSubscription == true,
            acknowledged: Boolean = true,
            token: String = "token-$productId-${at.toEpochMilli()}",
        ) = PlayPurchase(listOf(productId), state, at, token, acknowledged, autoRenewing)

        private fun phase(price: String, micros: Long, period: String, cycles: Int = 0, recurrence: PlayPhase.Recurrence = PlayPhase.Recurrence.INFINITE) =
            PlayPhase(price, micros, "USD", period, cycles, recurrence)

        /** The three products as Play returns them to a US account; `trial` while Play still offers the yearly trial. */
        fun catalog(trial: Boolean): List<PlayProduct> {
            val base = PlaySubscriptionOffer("yearly", null, "yearly-base", listOf(phase("$19.99", 19_990_000, "P1Y")))
            val week = PlaySubscriptionOffer(
                "yearly", "trial-7d", "yearly-trial",
                listOf(phase("Free", 0, "P1W", 1, PlayPhase.Recurrence.FINITE), phase("$19.99", 19_990_000, "P1Y")),
            )
            return listOf(
                PlayProduct(ProPlan.YEARLY.productId, subscriptionOffers = if (trial) listOf(base, week) else listOf(base)),
                PlayProduct(ProPlan.MONTHLY.productId, subscriptionOffers = listOf(PlaySubscriptionOffer("monthly", null, "monthly-base", listOf(phase("$3.99", 3_990_000, "P1M"))))),
                PlayProduct(ProPlan.LIFETIME.productId, oneTimeOffers = listOf(PlayOneTimeOffer("$49.99", 49_990_000, "USD", "lifetime-buy", purchaseOptionId = "lifetime"))),
            )
        }
    }
}
