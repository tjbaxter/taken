package com.tombaxter.taken

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.android.billingclient.api.BillingClient
import com.tombaxter.taken.billing.PlayBilling
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

/**
 * The Billing client of NEXT 1 (SPEC-ANDROID 9.3): it is built the documented way and really asks Google Play for a
 * connection. Robolectric has no Play Store, so Play's answer here is "not available", never a hang and never a crash;
 * on a phone with Play the same call ends READY.
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
        billing.connect()
        assertEquals(PlayBilling.Connection.UNAVAILABLE, billing.awaitAnswer())
        assertNotEquals(BillingClient.BillingResponseCode.OK, billing.lastResponseCode)
    }

    @Test
    fun testConnectingAgainAfterNoAnswerAsksAgain() {
        val billing = PlayBilling(app)
        billing.connect()
        billing.awaitAnswer()
        billing.connect()
        assertEquals(PlayBilling.Connection.UNAVAILABLE, billing.awaitAnswer())
    }
}
