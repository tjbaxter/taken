package com.tombaxter.taken

import android.content.Context
import com.tombaxter.taken.data.Persistence
import kotlinx.coroutines.CoroutineScope

/**
 * Debug builds (never in release, SPEC-ANDROID 4): Taken Pro reads as on. A debug install carries the `.debug` package,
 * which Play sells nothing to, so asking Play would lock a developer out after the first dose. The tests drive the real
 * [com.tombaxter.taken.billing.ProStore] with a fake billing client instead.
 */
object BuildWiring {
    @Suppress("UNUSED_PARAMETER")
    fun pro(context: Context, persistence: Persistence, scope: CoroutineScope): ProSource = ProSource.untilBilling
}
