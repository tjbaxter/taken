package com.tombaxter.taken.ui.item

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.ui.components.PrimaryButton
import com.tombaxter.taken.ui.components.SheetHeader
import com.tombaxter.taken.ui.components.TakenSheet
import com.tombaxter.taken.ui.components.TakenTimeInput
import java.util.UUID

/**
 * Set time (SPEC 3.1): correct when the last dose was really taken, or log one at the right time. A 24-hour input starts
 * on that dose's time or now; a time still to come on today's logical day is never used ("That time is still to come").
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetTimeSheet(model: AppModel, itemId: UUID, onDismiss: () -> Unit) {
    val item = model.item(itemId)
    if (item == null) {
        LaunchedEffect(itemId) { onDismiss() }
        return
    }
    val last = model.setTimeDose(item)
    val start = model.clock.hourMinute(last?.takenAt ?: model.now)
    val state = rememberTimePickerState(initialHour = start.hour, initialMinute = start.minute, is24Hour = true)
    val minutes = state.hour * 60 + state.minute
    val future = model.moment(model.today.day, minutes).second
    val label = Fmt.minutes(minutes)
    TakenSheet(onDismiss = onDismiss) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 16.dp).testTag("set-time-sheet")) {
            SheetHeader(
                title = item.name,
                subtitle = if (last == null) "Log a dose at the time you took it." else "Correct the last dose.",
                onClose = onDismiss,
            )
            Box(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
                TakenTimeInput(state)
            }
            Spacer(Modifier.height(8.dp))
            PrimaryButton(
                title = when {
                    future -> "That time is still to come"
                    last == null -> "Log at $label"
                    else -> "Set to $label"
                },
                enabled = !future,
                modifier = Modifier.padding(horizontal = 20.dp),
            ) {
                val hour = state.hour
                val minute = state.minute
                // Set time logs or moves a dose, so in locked mode it opens the paywall.
                model.requirePro {
                    model.setTime(item, hour, minute)
                    onDismiss()
                }
            }
        }
    }
}
