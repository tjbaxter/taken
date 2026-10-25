package com.tombaxter.taken.billing

import android.content.Context
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Google Play Billing, first step (SPEC-ANDROID 9.3, NEXT 1): the one BillingClient of the process, connected when Taken
 * comes to the front, asking Play for nothing yet. Play lets products be created only once a build with the Billing
 * Library is on a track (https://developer.android.com/google/play/billing/getting-ready), so this build carries the
 * library and a real connection; Taken Pro itself still reads [com.tombaxter.taken.ProSource.untilBilling] until the
 * products exist and NEXT 2 maps Play's purchases to the gate.
 *
 * Built as Google documents it (https://developer.android.com/google/play/billing/integrate): one client, so one
 * PurchasesUpdatedListener gets each event; pending purchases enabled for one-time products, which the lifetime plan
 * will be; automatic service reconnection, which Google "strongly recommends", so a lost connection needs no retry code
 * and onBillingServiceDisconnected stays a state update; a connection "when your app is launched or comes to the
 * foreground".
 */
class PlayBilling(context: Context) {
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

    /** The last answer to a connection attempt, for NEXT 2's status lines and the tests. */
    var lastResponseCode: Int? = null
        private set

    private val client: BillingClient = BillingClient.newBuilder(context)
        // Nothing is sold in this build, so no purchase flow is ever launched from Taken. NEXT 2 handles the updates.
        .setListener { _, _ -> }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    /** Connects unless a connection is on its way or ready. Safe to call on every start. */
    fun connect() {
        when (state.value) {
            Connection.CONNECTING, Connection.READY -> return
            Connection.IDLE, Connection.UNAVAILABLE, Connection.DISCONNECTED -> Unit
        }
        state.value = Connection.CONNECTING
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                lastResponseCode = billingResult.responseCode
                state.value =
                    if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) Connection.READY else Connection.UNAVAILABLE
            }

            override fun onBillingServiceDisconnected() {
                // No startConnection here: with automatic reconnection on, Google says to leave this a no-op apart from
                // state (integrate page above).
                state.value = Connection.DISCONNECTED
            }
        })
    }
}
