package com.tombaxter.taken.billing

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.InAppMessageParams
import com.android.billingclient.api.InAppMessageResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.tombaxter.taken.core.pro.PlayAnswer
import com.tombaxter.taken.core.pro.PlayOneTimeOffer
import com.tombaxter.taken.core.pro.PlayPhase
import com.tombaxter.taken.core.pro.PlayProduct
import com.tombaxter.taken.core.pro.PlayPurchase
import com.tombaxter.taken.core.pro.PlayResponse
import com.tombaxter.taken.core.pro.PlaySubscriptionOffer
import com.tombaxter.taken.core.pro.ProPlan
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import java.time.Instant
import kotlin.coroutines.resume

/**
 * Google Play Billing (SPEC-ANDROID 9.3): the one BillingClient of the process, built as Google documents it
 * (https://developer.android.com/google/play/billing/integrate). One client, so one PurchasesUpdatedListener gets each
 * event; pending purchases enabled for one-time products, as Play requires; automatic service reconnection, which Google
 * "strongly recommends", so `onBillingServiceDisconnected` stays a state update and a call made while disconnected
 * reconnects by itself. A first connection that fails with a retriable code is tried again with Google's own simple retry
 * (3 tries, 2 seconds apart, the `connectWithRetry` sample on https://developer.android.com/google/play/billing/errors);
 * BILLING_UNAVAILABLE is never retried by itself, as the same page advises.
 */
class PlayBilling(context: Context) : BillingGateway {
    enum class Connection {
        /** Not asked yet. */
        IDLE,
        CONNECTING,
        READY,
        /** Play answered with something other than OK (no Play Store, billing not available on this phone or account). */
        UNAVAILABLE,
        /** The service went away; the library reconnects by itself on the next request. */
        DISCONNECTED,
    }

    private val state = MutableStateFlow(Connection.IDLE)
    val connection: StateFlow<Connection> = state.asStateFlow()

    /** The last answer to a connection attempt. */
    var lastResponseCode: Int? = null
        private set

    private var purchasesListener: (PlayResponse, List<PlayPurchase>) -> Unit = { _, _ -> }
    private val connectionWaiters = ArrayList<(PlayResponse) -> Unit>()

    /**
     * The products as Play last returned them: the purchase flow needs Play's own objects. Asked for again each time the
     * paywall opens, since Google warns that "stale objects can cause launchBillingFlow() failures" (integrate page).
     */
    private val products = HashMap<String, ProductDetails>()

    private val client: BillingClient = BillingClient.newBuilder(context)
        .setListener { result, purchases ->
            purchasesListener(response(result.responseCode), purchases.orEmpty().map { it.toPlay() })
        }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    override fun setPurchasesListener(listener: (PlayResponse, List<PlayPurchase>) -> Unit) {
        purchasesListener = listener
    }

    /** Starts a connection unless one is on its way or ready. Safe to call on every start. */
    fun startConnecting() {
        when (state.value) {
            Connection.CONNECTING, Connection.READY -> return
            Connection.IDLE, Connection.UNAVAILABLE, Connection.DISCONNECTED -> Unit
        }
        state.value = Connection.CONNECTING
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                lastResponseCode = billingResult.responseCode
                val answer = response(billingResult.responseCode)
                state.value = if (answer == PlayResponse.OK) Connection.READY else Connection.UNAVAILABLE
                val waiting = synchronized(connectionWaiters) { connectionWaiters.toList().also { connectionWaiters.clear() } }
                waiting.forEach { it(answer) }
            }

            override fun onBillingServiceDisconnected() {
                // No startConnection here: with automatic reconnection on, Google says to leave this a no-op apart from
                // state (integrate page above).
                state.value = Connection.DISCONNECTED
            }
        })
    }

    override suspend fun connect(): PlayResponse {
        var tries = 0
        while (true) {
            val answer = connectOnce()
            tries += 1
            if (answer == PlayResponse.OK || !answer.retriable || tries >= CONNECT_TRIES) return answer
            delay(CONNECT_RETRY_DELAY_MS)
        }
    }

    private suspend fun connectOnce(): PlayResponse {
        // Disconnected after a connection: the library reconnects on the next call by itself.
        if (state.value == Connection.READY || state.value == Connection.DISCONNECTED) return PlayResponse.OK
        return suspendCancellableCoroutine { continuation ->
            synchronized(connectionWaiters) {
                connectionWaiters.add { answer -> if (continuation.isActive) continuation.resume(answer) }
            }
            startConnecting()
        }
    }

    override suspend fun queryPurchases(): PlayAnswer<List<PlayPurchase>> {
        val subscriptions = purchases(BillingClient.ProductType.SUBS)
        val oneTime = purchases(BillingClient.ProductType.INAPP)
        val answer = if (subscriptions.response != PlayResponse.OK) subscriptions.response else oneTime.response
        return PlayAnswer(answer, subscriptions.value + oneTime.value)
    }

    private suspend fun purchases(type: String): PlayAnswer<List<PlayPurchase>> = suspendCancellableCoroutine { continuation ->
        val params = QueryPurchasesParams.newBuilder().setProductType(type).build()
        client.queryPurchasesAsync(params) { result, purchases ->
            if (continuation.isActive) {
                continuation.resume(PlayAnswer(response(result.responseCode), purchases.map { it.toPlay() }))
            }
        }
    }

    override suspend fun queryProducts(): PlayAnswer<List<PlayProduct>> {
        val subscriptions = details(BillingClient.ProductType.SUBS, listOf(ProPlan.YEARLY.productId, ProPlan.MONTHLY.productId))
        val oneTime = details(BillingClient.ProductType.INAPP, listOf(ProPlan.LIFETIME.productId))
        val found = subscriptions.value + oneTime.value
        synchronized(products) {
            products.clear()
            for (product in found) products[product.productId] = product
        }
        val answer = when {
            subscriptions.response == PlayResponse.OK || oneTime.response == PlayResponse.OK -> PlayResponse.OK
            else -> subscriptions.response
        }
        return PlayAnswer(answer, found.map { it.toPlay() })
    }

    private suspend fun details(type: String, ids: List<String>): PlayAnswer<List<ProductDetails>> =
        suspendCancellableCoroutine { continuation ->
            val params = QueryProductDetailsParams.newBuilder()
                .setProductList(ids.map { QueryProductDetailsParams.Product.newBuilder().setProductId(it).setProductType(type).build() })
                .build()
            client.queryProductDetailsAsync(params) { result, details ->
                if (continuation.isActive) {
                    continuation.resume(PlayAnswer(response(result.responseCode), details.productDetailsList.orEmpty()))
                }
            }
        }

    override fun launch(activity: Activity, productId: String, offerToken: String): PlayResponse {
        val product = synchronized(products) { products[productId] } ?: return PlayResponse.ITEM_UNAVAILABLE
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    // The offer token is set for subscriptions and one-time products alike: "you must set the offer token
                    // corresponding to the offer selected by the user"
                    // (https://developer.android.com/google/play/billing/one-time-product-multi-purchase-options-offers).
                    BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product).setOfferToken(offerToken).build(),
                ),
            )
            .build()
        return response(client.launchBillingFlow(activity, params).responseCode)
    }

    override suspend fun acknowledge(token: String): PlayResponse = suspendCancellableCoroutine { continuation ->
        val params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(token).build()
        client.acknowledgePurchase(params) { result ->
            if (continuation.isActive) continuation.resume(response(result.responseCode))
        }
    }

    /**
     * Google: "We recommend that you call this API whenever the user opens the app": Play shows its own snackbar about a
     * declined payment, with a link to fix it (https://developer.android.com/google/play/billing/subscriptions).
     */
    override fun showInAppMessages(activity: Activity, onStatusUpdated: () -> Unit) {
        if (state.value != Connection.READY) return
        val params = InAppMessageParams.newBuilder()
            .addInAppMessageCategoryToShow(InAppMessageParams.InAppMessageCategoryId.TRANSACTIONAL)
            .build()
        client.showInAppMessages(activity, params) { result ->
            if (result.responseCode == InAppMessageResult.InAppMessageResponseCode.SUBSCRIPTION_STATUS_UPDATED) onStatusUpdated()
        }
    }

    companion object {
        /** Google's `connectWithRetry` sample: at most 3 tries, 2 seconds apart (errors page above). */
        const val CONNECT_TRIES = 3
        const val CONNECT_RETRY_DELAY_MS = 2_000L

        /** Play's response codes by name (`BillingClient.BillingResponseCode`). */
        fun response(code: Int): PlayResponse = when (code) {
            BillingClient.BillingResponseCode.OK -> PlayResponse.OK
            BillingClient.BillingResponseCode.USER_CANCELED -> PlayResponse.USER_CANCELED
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE -> PlayResponse.SERVICE_UNAVAILABLE
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE -> PlayResponse.BILLING_UNAVAILABLE
            BillingClient.BillingResponseCode.ITEM_UNAVAILABLE -> PlayResponse.ITEM_UNAVAILABLE
            BillingClient.BillingResponseCode.DEVELOPER_ERROR -> PlayResponse.DEVELOPER_ERROR
            BillingClient.BillingResponseCode.ERROR -> PlayResponse.ERROR
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> PlayResponse.ITEM_ALREADY_OWNED
            BillingClient.BillingResponseCode.ITEM_NOT_OWNED -> PlayResponse.ITEM_NOT_OWNED
            BillingClient.BillingResponseCode.NETWORK_ERROR -> PlayResponse.NETWORK_ERROR
            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED -> PlayResponse.SERVICE_DISCONNECTED
            BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED -> PlayResponse.FEATURE_NOT_SUPPORTED
            // SERVICE_TIMEOUT (-3) is deprecated and returned only by Billing Library 5.2.0 and earlier (errors page).
            -3 -> PlayResponse.SERVICE_TIMEOUT
            else -> PlayResponse.ERROR
        }
    }
}

/** A `Purchase` as Taken reads it (SPEC-ANDROID 9.4). */
fun Purchase.toPlay(): PlayPurchase = PlayPurchase(
    productIds = products,
    state = when (purchaseState) {
        Purchase.PurchaseState.PURCHASED -> PlayPurchase.State.PURCHASED
        Purchase.PurchaseState.PENDING -> PlayPurchase.State.PENDING
        else -> PlayPurchase.State.UNSPECIFIED
    },
    purchaseTime = Instant.ofEpochMilli(purchaseTime),
    token = purchaseToken,
    acknowledged = isAcknowledged,
    autoRenewing = isAutoRenewing,
    pendingUpdateProductIds = pendingPurchaseUpdate?.products.orEmpty(),
)

/** A `ProductDetails` as Taken reads it: each subscription offer with its phases, each one-time purchase option. */
fun ProductDetails.toPlay(): PlayProduct = PlayProduct(
    productId = productId,
    subscriptionOffers = subscriptionOfferDetails.orEmpty().map { offer ->
        PlaySubscriptionOffer(
            basePlanId = offer.basePlanId,
            offerId = offer.offerId,
            offerToken = offer.offerToken,
            phases = offer.pricingPhases.pricingPhaseList.map { phase ->
                PlayPhase(
                    formattedPrice = phase.formattedPrice,
                    priceMicros = phase.priceAmountMicros,
                    currencyCode = phase.priceCurrencyCode,
                    billingPeriod = phase.billingPeriod,
                    cycleCount = phase.billingCycleCount,
                    recurrence = when (phase.recurrenceMode) {
                        ProductDetails.RecurrenceMode.FINITE_RECURRING -> PlayPhase.Recurrence.FINITE
                        ProductDetails.RecurrenceMode.NON_RECURRING -> PlayPhase.Recurrence.NON_RECURRING
                        else -> PlayPhase.Recurrence.INFINITE
                    },
                )
            },
            tags = offer.offerTags,
        )
    },
    // An option without an offer token cannot be bought (the purchase flow needs it), so it is not offered.
    oneTimeOffers = oneTimeOffers().mapNotNull { option ->
        val token = option.offerToken ?: return@mapNotNull null
        PlayOneTimeOffer(
            formattedPrice = option.formattedPrice,
            priceMicros = option.priceAmountMicros,
            currencyCode = option.priceCurrencyCode,
            offerToken = token,
            purchaseOptionId = option.purchaseOptionId,
            offerId = option.offerId,
        )
    },
)

/** Every purchase option and offer Play returned for a one-time product (Billing 8+), else its backwards compatible one. */
private fun ProductDetails.oneTimeOffers(): List<ProductDetails.OneTimePurchaseOfferDetails> =
    oneTimePurchaseOfferDetailsList ?: listOfNotNull(oneTimePurchaseOfferDetails)
