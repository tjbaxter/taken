package com.tombaxter.taken

import android.content.Context
import com.tombaxter.taken.billing.PlayBilling
import com.tombaxter.taken.billing.ProStore
import com.tombaxter.taken.data.Persistence
import kotlinx.coroutines.CoroutineScope

/**
 * Release builds, and so every build that reaches Google Play: Taken Pro from Google Play Billing (SPEC-ANDROID 9), over
 * the one BillingClient of the process.
 */
object BuildWiring {
    fun pro(context: Context, persistence: Persistence, scope: CoroutineScope): ProSource =
        ProStore(gateway = PlayBilling(context), writeLedger = persistence::updateLedger, scope = scope)
}
