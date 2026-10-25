package com.tombaxter.taken.billing

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.tombaxter.taken.TakenApp
import java.util.concurrent.TimeUnit

/**
 * A purchase's acknowledgement that must not be lost. Google: acknowledging "must be done within three days so that the
 * purchase isn't automatically refunded and entitlement revoked" (https://developer.android.com/google/play/billing/integrate).
 * [ProStore] tries at once, three times; this keeps a try waiting outside Taken's process in case those fail or the process
 * goes first, since someone who logs from the widget, the tile and the nudge may not open Taken for days.
 */
interface AcknowledgeRetry {
    /** A purchase waits to be acknowledged: ask again later, even if Taken's process has gone. */
    fun schedule()

    /** Everything this process saw is acknowledged: nothing left to ask. */
    fun cancel()

    companion object {
        val none: AcknowledgeRetry = object : AcknowledgeRetry {
            override fun schedule() = Unit
            override fun cancel() = Unit
        }
    }
}

/**
 * The durable try through WorkManager, which Google documents for work that "must run even if the app exits"
 * (https://developer.android.com/develop/background-work/background-tasks/persistent): one unique request, run once a network
 * is there, retried with exponential backoff until Play has every purchase acknowledged. WorkManager is already in Taken for
 * Glance's sessions and sends nothing off the phone itself; the worker only talks to Google Play on the phone. [Own choice:
 * the 1 minute wait before the first try, which leaves the in-process tries their 6 seconds.]
 */
class WorkAcknowledgeRetry(context: Context) : AcknowledgeRetry {
    private val app: Context = context.applicationContext

    override fun schedule() {
        val request = OneTimeWorkRequestBuilder<AcknowledgeWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInitialDelay(FIRST_TRY_MINUTES, TimeUnit.MINUTES)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .build()
        // KEEP: a request already waiting stays as it is, so repeated purchases never push the first try back.
        runCatching { WorkManager.getInstance(app).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.KEEP, request) }
    }

    override fun cancel() {
        runCatching { WorkManager.getInstance(app).cancelUniqueWork(WORK_NAME) }
    }

    companion object {
        const val WORK_NAME = "taken.pro.acknowledge"
        const val FIRST_TRY_MINUTES = 1L
        /** WorkManager's own default backoff, written out (https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work). */
        const val BACKOFF_SECONDS = 30L
    }
}

/** Asks Google Play for Taken's purchases and acknowledges each one not yet acknowledged; retried until none is left. */
class AcknowledgeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        // Debug builds hold no ProStore (their `.debug` package buys nothing): nothing to acknowledge.
        val store = (applicationContext as TakenApp).container.pro as? ProStore ?: return Result.success()
        return if (store.acknowledgeOutstanding()) Result.success() else Result.retry()
    }
}
