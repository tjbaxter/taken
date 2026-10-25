package com.tombaxter.taken.billing

import android.app.Activity
import com.tombaxter.taken.core.pro.PlayAnswer
import com.tombaxter.taken.core.pro.PlayProduct
import com.tombaxter.taken.core.pro.PlayPurchase
import com.tombaxter.taken.core.pro.PlayResponse

/**
 * The boundary between Taken and Google Play Billing (SPEC-ANDROID 9.3): what [ProStore] asks of Play, in Taken's plain
 * types. [PlayBilling] is the real one, over the one `BillingClient` of the process; the tests drive a fake through every
 * state a purchase can be in, with no Play Store.
 */
interface BillingGateway {
    /** Ready to ask Play: connects when needed. OK when connected; otherwise Play's answer to the last attempt. */
    suspend fun connect(): PlayResponse

    /** Subscriptions and one-time products this Google account holds. OK only when Play answered both. */
    suspend fun queryPurchases(): PlayAnswer<List<PlayPurchase>>

    /** Taken's three products, with the offers Play gives this person. OK when Play answered either question. */
    suspend fun queryProducts(): PlayAnswer<List<PlayProduct>>

    /** Opens Play's purchase screen for one offer. OK means it opened; the result comes to the purchases listener. */
    fun launch(activity: Activity, productId: String, offerToken: String): PlayResponse

    /** Acknowledges a purchase, which Play otherwise refunds after three days. */
    suspend fun acknowledge(token: String): PlayResponse

    /** Play's own messages about a declined payment, once each time Taken opens; `onStatusUpdated` when one fixed it. */
    fun showInAppMessages(activity: Activity, onStatusUpdated: () -> Unit) {}

    /** Where Play's purchase updates go: every purchase flow's result, and purchases that finish while Taken runs. */
    fun setPurchasesListener(listener: (PlayResponse, List<PlayPurchase>) -> Unit)
}
