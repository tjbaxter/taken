package com.tombaxter.taken

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.Purchase
import com.tombaxter.taken.billing.toPlay
import com.tombaxter.taken.core.pro.PlayPurchase
import com.tombaxter.taken.core.pro.PlayResponse
import com.tombaxter.taken.core.pro.ProPlan
import java.time.Instant
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import com.tombaxter.taken.billing.PlayBilling
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

/**
 * The Billing client (SPEC-ANDROID 9.3): it is built the documented way and really asks Google Play for a connection.
 * Robolectric has no Play Store, so Play's answer here is "not available", never a hang and never a crash; on a phone
 * with Play the same call ends READY. And what the client hands Taken: Play's Purchase as plain facts, its codes by name.
 */
@RunWith(RobolectricTestRunner::class)
class PlayBillingTests {
    private val app: TakenApp get() = ApplicationProvider.getApplicationContext()

    private fun PlayBilling.awaitAnswer(): PlayBilling.Connection {
        val end = System.currentTimeMillis() + 10_000
        while (connection.value == PlayBilling.Connection.CONNECTING) {
            shadowOf(Looper.getMainLooper()).idle()
            check(System.currentTimeMillis() < end) { "Google Play never answered the connection" }
            Thread.sleep(10)
        }
        return connection.value
    }

    @Test
    fun testTheClientConnectsAndHearsBackWithoutAPlayStore() {
        val billing = PlayBilling(app)
        assertEquals(PlayBilling.Connection.IDLE, billing.connection.value)
        billing.startConnecting()
        assertEquals(PlayBilling.Connection.UNAVAILABLE, billing.awaitAnswer())
        assertNotEquals(BillingClient.BillingResponseCode.OK, billing.lastResponseCode)
    }

    /** Play's own Purchase, as Taken reads it (SPEC-ANDROID 9.4): what the phone can know, and nothing more. */
    @Test
    fun testAPurchaseFromPlayReadsAsTakensFacts() {
        val json = """{"orderId":"GPA.3301-0000-0000-00000","packageName":"com.tombaxter.taken","productId":"com.tombaxter.taken.pro.yearly","purchaseTime":1793178840000,"purchaseState":0,"purchaseToken":"token-1","quantity":1,"autoRenewing":true,"acknowledged":false}"""
        val bought = Purchase(json, "signature").toPlay()
        assertEquals(listOf("com.tombaxter.taken.pro.yearly"), bought.productIds)
        assertEquals(PlayPurchase.State.PURCHASED, bought.state)
        assertEquals(Instant.ofEpochMilli(1_793_178_840_000), bought.purchaseTime, "the signup time, which renewals never change")
        assertEquals("token-1", bought.token)
        assertTrue(bought.autoRenewing)
        assertFalse(bought.acknowledged)
        assertTrue(bought.pendingUpdateProductIds.isEmpty())
        assertEquals(ProPlan.YEARLY, bought.plan)

        val waiting = Purchase(json.replace("\"purchaseState\":0", "\"purchaseState\":4"), "signature").toPlay()
        assertEquals(PlayPurchase.State.PENDING, waiting.state, "a slow card or a family approval")
    }

    /** Play's response codes by name. */
    @Test
    fun testResponseCodesMapByName() {
        val codes = mapOf(
            BillingClient.BillingResponseCode.OK to PlayResponse.OK,
            BillingClient.BillingResponseCode.USER_CANCELED to PlayResponse.USER_CANCELED,
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE to PlayResponse.SERVICE_UNAVAILABLE,
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE to PlayResponse.BILLING_UNAVAILABLE,
            BillingClient.BillingResponseCode.ITEM_UNAVAILABLE to PlayResponse.ITEM_UNAVAILABLE,
            BillingClient.BillingResponseCode.DEVELOPER_ERROR to PlayResponse.DEVELOPER_ERROR,
            BillingClient.BillingResponseCode.ERROR to PlayResponse.ERROR,
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED to PlayResponse.ITEM_ALREADY_OWNED,
            BillingClient.BillingResponseCode.ITEM_NOT_OWNED to PlayResponse.ITEM_NOT_OWNED,
            BillingClient.BillingResponseCode.NETWORK_ERROR to PlayResponse.NETWORK_ERROR,
            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED to PlayResponse.SERVICE_DISCONNECTED,
            BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED to PlayResponse.FEATURE_NOT_SUPPORTED,
        )
        for ((code, response) in codes) assertEquals(response, PlayBilling.response(code))
        assertEquals(PlayResponse.ERROR, PlayBilling.response(999), "an unknown code is treated as an error")
    }

    @Test
    fun testConnectingAgainAfterNoAnswerAsksAgain() {
        val billing = PlayBilling(app)
        billing.startConnecting()
        billing.awaitAnswer()
        billing.startConnecting()
        assertEquals(PlayBilling.Connection.UNAVAILABLE, billing.awaitAnswer())
    }
}
