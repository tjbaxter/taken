package com.tombaxter.taken.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import com.tombaxter.taken.AppContainer
import com.tombaxter.taken.ProSource
import com.tombaxter.taken.TakenApp
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.parseUuid
import com.tombaxter.taken.core.pro.ProLedgers
import com.tombaxter.taken.core.pro.ProPendingAction
import com.tombaxter.taken.core.stack.logNextDoseIfPending
import com.tombaxter.taken.core.stack.takeAllPending
import com.tombaxter.taken.data.LedgerFile
import kotlinx.coroutines.flow.first
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** What a tap on a widget or the tile did. */
sealed interface SurfaceOutcome {
    data class Logged(val count: Int) : SurfaceOutcome

    /** Nothing was pending and ready: a second tap, a stale widget, or everything taken. Never un-takes. */
    data object Nothing : SurfaceOutcome

    /** Logging needs Taken Pro: nothing was written. */
    data object Locked : SurfaceOutcome

    /** The file could not be written (a full disk). */
    data object Failed : SurfaceOutcome
}

/**
 * Logging from outside Taken, without opening it (Shared/Intents.swift `TakeAllIntent` and `LogNextDoseIntent`, which the
 * iPhone's widget buttons and Control Center control run): the same rules as the app, written straight to taken.json
 * through DataStore's transaction, at the moment of the tap. Each ends by redrawing the surfaces, so the widget a tap came
 * from shows what it did before its broadcast ends (WT-3.1, https://developer.android.com/docs/quality-guidelines/widget-quality).
 */
object SurfaceActions {
    /**
     * TAKE ALL on the widget or the tile: every quick-loggable pending dose at one moment (`takeAllPending`), never one
     * logged in the last hour. Locked: nothing is written, and the Take all is kept in pro.json for Taken to offer with the
     * paywall when it next opens (10 minutes), as the iPhone's intent does.
     */
    suspend fun takeAll(
        container: AppContainer,
        now: Instant = container.clock(),
        zone: ZoneId = container.zone(),
        pro: ProSource = container.pro,
    ): SurfaceOutcome {
        val stores = container.stores
        val outcome = try {
            val inputs = container.surfaces.read()
            if (container.surfaces.locked(inputs, now, pro)) {
                stores.ledger.updateData { file -> LedgerFile(ProLedgers.recordPending(file.ledger, ProPendingAction.TakeAll, now)) }
                SurfaceOutcome.Locked
            } else {
                var logged: List<Dose> = emptyList()
                stores.stack.updateData { latest ->
                    latest.clone().also { s -> logged = s.takeAllPending(now, DayClock(s.settings.dayStartHour, zone)) }
                }
                if (logged.isNotEmpty()) {
                    stores.ledger.updateData { file -> LedgerFile(ProLedgers.noteFirstDose(file.ledger, now)) }
                    SurfaceOutcome.Logged(logged.size)
                } else {
                    SurfaceOutcome.Nothing
                }
            }
        } catch (e: IOException) {
            SurfaceOutcome.Failed
        }
        container.surfaces.refresh()
        return outcome
    }

    /**
     * A widget row: that item's next dose, only while it is still pending and was not logged in the last hour
     * (`logNextDoseIfPending`), so a stale widget or a second tap can never log twice. Locked (a widget drawn before Pro
     * ran out): nothing is logged, and the widget is drawn again read-only, where a tap opens the paywall.
     */
    suspend fun logNext(
        container: AppContainer,
        itemId: UUID,
        now: Instant = container.clock(),
        zone: ZoneId = container.zone(),
        pro: ProSource = container.pro,
    ): SurfaceOutcome {
        val stores = container.stores
        val outcome = try {
            val inputs = container.surfaces.read()
            if (container.surfaces.locked(inputs, now, pro)) {
                SurfaceOutcome.Locked
            } else {
                var dose: Dose? = null
                stores.stack.updateData { latest ->
                    latest.clone().also { s -> dose = s.logNextDoseIfPending(itemId, now, DayClock(s.settings.dayStartHour, zone)) }
                }
                if (dose != null) {
                    stores.ledger.updateData { file -> LedgerFile(ProLedgers.noteFirstDose(file.ledger, now)) }
                    SurfaceOutcome.Logged(1)
                } else {
                    SurfaceOutcome.Nothing
                }
            }
        } catch (e: IOException) {
            SurfaceOutcome.Failed
        }
        container.surfaces.refresh()
        return outcome
    }
}

/**
 * A row's tap on the stack widget. Glance runs it in its own broadcast receiver, which "allows extra execution time"
 * (https://developer.android.com/develop/ui/compose/glance/user-interaction).
 */
class LogNextAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[ITEM]?.let(::parseUuid) ?: return
        SurfaceActions.logNext((context.applicationContext as TakenApp).container, id)
    }

    companion object {
        val ITEM = ActionParameters.Key<String>("item")
    }
}

/** TAKE ALL on the stack widget. */
class TakeAllAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        SurfaceActions.takeAll((context.applicationContext as TakenApp).container)
    }
}
