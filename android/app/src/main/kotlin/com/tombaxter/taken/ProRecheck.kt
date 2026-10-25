package com.tombaxter.taken

import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.PlayEntitlement
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProStatus
import java.time.Instant

/**
 * Whether a log from outside Taken may be written: a widget's row or TAKE ALL, the tile, a nudge's TAKE ALL
 * (SPEC-ANDROID 9.3 and 9.7). The iPhone's `ProGate.mayLog` (Shared/Pro.swift), which its Siri intents and the nudge's
 * TAKE ALL run before writing:
 * 1. Pro's answer is the source's, or pro.json's cached one while the source has none yet (a widget or a receiver in a
 *    fresh process), as the iPhone's surfaces read the ledger.
 * 2. When that refuses only because a subscription has outlived its cached answer (`PlayEntitlement.needsCheck`), the
 *    store is asked once more before anything is refused. On Android that answer's `expiresAt` is only a check horizon
 *    (`PlayEntitlement.facts`: 24 hours for a plan set not to renew, 72 hours for one that renews), never the end of the
 *    period paid for, so a cancelled plan is asked about too: Google keeps returning it "until it expires", and removing
 *    access a person is still entitled to "is a violation of Google Play's subscriptions policy"
 *    (https://developer.android.com/google/play/billing/lifecycle/subscriptions). The iPhone, whose `expiresAt` is the
 *    real end, asks only for a renewal it has not seen. On Android the question is `ProSource.refresh()`, Google Play's
 *    `queryPurchasesAsync`, run inside the receiver's `goAsync()` time. No Pro at all is refused without asking, as on the
 *    iPhone; Play's answer then stands, so a plan that really ended is asked about once.
 *
 * A recheck that changed Pro runs `onProChanged`, so the widgets, the tile and the alarms follow it with no screen open.
 */
object ProRecheck {
    suspend fun mayLog(
        pro: ProSource,
        state: StackState,
        now: Instant,
        readLedger: suspend () -> ProLedger?,
        onProChanged: () -> Unit = {},
    ): Boolean {
        val ledger = readLedger()
        val status = pro.status ?: ledger?.status
        if (access(status, state, ledger, now).allowsLogging) return true
        if (!PlayEntitlement.needsCheck(status, now)) return false
        if (pro.refresh()) onProChanged()
        // Play's answer is the source's now; pro.json follows it a moment later.
        val again = readLedger()
        return access(pro.status ?: again?.status, state, again, now).allowsLogging
    }

    private fun access(status: ProStatus?, state: StackState, ledger: ProLedger?, now: Instant): ProAccess = ProGate.access(
        status, settled = true, legacyLog = false, hasLogged = ProGate.hasLogged(state, ledger), now = now,
    )
}
