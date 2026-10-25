package com.tombaxter.taken.ui.day

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.stack.DaySheetRules
import com.tombaxter.taken.core.stack.ItemDay
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.ConfirmDialog
import com.tombaxter.taken.ui.components.MonoTimeButton
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.SectionHeader
import com.tombaxter.taken.ui.components.SheetHeader
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.TakenSheet
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/**
 * One day from History (SPEC 3.2): what was taken and when, and the backfill for a forgotten day. "Log at" picks the
 * time; each dose is a chip (a tap asks to remove it, never gated); "+ 08:00" logs at the chosen time, through Taken Pro.
 */
@Composable
fun DaySheet(model: AppModel, day: DayKey, onDismiss: () -> Unit) {
    TakenSheet(onDismiss = onDismiss) {
        DayContent(model, day, onDismiss)
    }
}

@Composable
fun DayContent(model: AppModel, day: DayKey, onClose: () -> Unit) {
    val colors = Taken.colors
    val summary = model.sheetSummary(day)
    val isToday = day == model.today.day
    val live = DaySheetRules.isLive(day, model.today.day)
    var logMinutes by remember(day) {
        mutableIntStateOf(DaySheetRules.startMinutes(day, model.today.day, model.clock.minutesOfDay(model.now), model.settings.backfillMinutes))
    }
    var removing by remember { mutableStateOf<Dose?>(null) }
    val future = model.moment(day, logMinutes).second

    Column(Modifier.fillMaxWidth().testTag("day-sheet")) {
        SheetHeader(
            title = Fmt.longDay(day),
            subtitle = Fmt.daySheetStatus(summary, isToday = live),
            subtitleColor = if (summary.allTaken && summary.openCount == 0) colors.signalInk else colors.fgSubtle,
            onClose = onClose,
        )
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 30.dp)
                .navigationBarsPadding(),
        ) {
            Spacer(Modifier.height(12.dp))
            val shape = RoundedCornerShape(Taken.shapes.card)
            Row(
                Modifier.fillMaxWidth().background(colors.bgRaised, shape).border(1.dp, colors.line, shape)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Log at", style = TakenType.sans(17), color = colors.fg)
                    Spacer(Modifier.height(3.dp))
                    Text(
                        when {
                            future -> "That time is still to come. Pick an earlier one."
                            isToday -> "Defaults to now."
                            else -> "An hour after you wake up. Change it if you remember."
                        },
                        style = TakenType.sans(14),
                        color = if (future) colors.fg else colors.fgSubtle,
                    )
                }
                MonoTimeButton("Log at", logMinutes) { logMinutes = it }
            }
            SectionHeader("Items", trailing = if (summary.items.isEmpty()) null else "Tap a time to remove it")
            if (summary.items.isEmpty()) {
                Text("Nothing in your stack yet", style = TakenType.sans(16), color = colors.fgSubtle)
            } else {
                Card {
                    Column {
                        summary.items.forEachIndexed { index, row ->
                            if (index > 0) RowDivider()
                            DayItemRow(
                                row = row, day = day, clock = model.clock, isToday = live, logLabel = Fmt.minutes(logMinutes),
                                canLog = !future,
                                onLog = {
                                    val minutes = logMinutes
                                    // Backfill logs a dose, so in locked mode it opens the paywall; the log stays readable.
                                    model.requirePro { model.logDose(row.item, day, minutes) }
                                },
                                onRemove = { removing = it },
                            )
                        }
                    }
                }
            }
        }
    }

    removing?.let { dose ->
        ConfirmDialog(
            title = DaySheetRules.removalTitle(dose, model.item(dose.itemId)?.name, day, model.clock),
            message = null,
            confirm = "Remove dose",
            onConfirm = {
                model.removeDose(dose)
                removing = null
            },
            onDismiss = { removing = null },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DayItemRow(
    row: ItemDay,
    day: DayKey,
    clock: DayClock,
    isToday: Boolean,
    logLabel: String,
    canLog: Boolean,
    onLog: () -> Unit,
    onRemove: (Dose) -> Unit,
) {
    val colors = Taken.colors
    val showsLog = row.isPending || row.doses.isEmpty()
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(row.item.name, style = TakenType.sans(16, FontWeight.Medium), color = colors.fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(3.dp))
            // Shrinks before it truncates, as the iPhone's minimumScaleFactor(0.8) does, so "taken" or "missed" stays in
            // view beside the time pills on a narrow phone.
            BasicText(
                text = Fmt.dayItemStatus(row, isToday),
                style = TakenType.sans(14).copy(color = if (row.isDue && row.isDone) colors.signalInk else colors.fgSubtle),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                autoSize = TextAutoSize.StepBased(minFontSize = 11.sp, maxFontSize = 14.sp, stepSize = 0.25.sp),
            )
        }
        Spacer(Modifier.width(8.dp))
        FlowRow(
            modifier = Modifier.widthIn(max = 220.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            for (dose in row.doses) {
                Box(
                    Modifier
                        .heightIn(min = 48.dp)
                        .clip(CircleShape)
                        .clickable(role = Role.Button, onClickLabel = "remove") { onRemove(dose) }
                        .semantics { contentDescription = "Taken ${Fmt.spokenDose(dose, day, clock)}. Remove." },
                    contentAlignment = Alignment.Center,
                ) {
                    Row(
                        Modifier.height(32.dp).background(colors.signalWash, CircleShape).border(1.dp, colors.signalEdge, CircleShape)
                            .padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(Fmt.doseClock(dose, day, clock), style = TakenType.monoFixed(14), color = colors.signalInk)
                        Spacer(Modifier.width(6.dp))
                        Icon(Symbols.Close, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(12.dp))
                    }
                }
            }
            if (showsLog) {
                Box(
                    Modifier
                        .heightIn(min = 48.dp)
                        .clip(CircleShape)
                        .clickable(enabled = canLog, role = Role.Button, onClick = onLog)
                        .semantics { contentDescription = "Log ${row.item.name} at $logLabel" }
                        .alpha(if (canLog) 1f else 0.4f),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(
                        Modifier.height(32.dp).border(1.dp, colors.lineStrong, CircleShape).padding(horizontal = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Symbols.Add, contentDescription = null, tint = colors.fg, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(logLabel, style = TakenType.monoFixed(14), color = colors.fg)
                    }
                }
            }
        }
    }
}
