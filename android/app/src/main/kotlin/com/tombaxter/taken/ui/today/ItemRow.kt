package com.tombaxter.taken.ui.today

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.stack.ItemDay
import com.tombaxter.taken.core.stack.RowSpeech
import com.tombaxter.taken.core.stack.TodayRules
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.drawCheck
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import kotlinx.coroutines.launch
import java.time.Instant

/** What a row's long-press menu and TalkBack's actions can do. */
class RowActions(
    val onTap: () -> Unit,
    val onUndoLast: () -> Unit,
    val onSetTime: () -> Unit,
    val onOpenDay: () -> Unit,
    val onEdit: () -> Unit,
)

/**
 * One item on Today, all of it one target (SPEC-ANDROID 7.2, `feat/tap-row-to-log`): the name and a small frequency line
 * on the left, and on the right the time and the ring. A tap anywhere logs while pending and shows the times once taken;
 * it never un-takes. In edit mode a chevron stands where the ring was and a tap opens the item. A long-press opens the
 * menu: Undo last dose, Set time… or Open <Weekday>, Edit item. TalkBack hears one node with the iPhone's sentence,
 * Android's click label, and the menu as custom actions.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ItemRow(
    row: ItemDay,
    today: DayKey,
    clock: DayClock,
    now: Instant,
    expanded: Boolean,
    nextLabel: String?,
    note: String?,
    locked: Boolean,
    editing: Boolean,
    logs: Int,
    offersSetTime: Boolean,
    actions: RowActions,
) {
    val colors = Taken.colors
    val quiet = nextLabel != null && row.doses.isEmpty()
    var menuOpen by remember { mutableStateOf(false) }

    // The logging moment: the row washes in the look's signal (in 0.1 s, out over 0.6 s) and the ring lifts to 1.12 and
    // settles on a spring. With animations removed, the wash shows for a single frame.
    val wash = remember { Animatable(0f) }
    val lift = remember { Animatable(1f) }
    var played by remember { mutableIntStateOf(logs) }
    LaunchedEffect(logs) {
        if (logs > played) {
            launch {
                lift.animateTo(1.12f, tween(100))
                lift.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMedium))
            }
            wash.animateTo(1f, tween(100))
            wash.animateTo(0f, tween(600))
        }
        played = logs
    }

    val label = RowSpeech.label(row, today, clock, nextLabel)
    val clickLabel = RowSpeech.clickLabel(row, quiet = quiet, locked = locked, editing = editing)
    val setTimeOrDay = if (offersSetTime) "Set time" else "Open ${Fmt.weekday(row.day)}"
    val customActions = buildList {
        if (row.doses.isNotEmpty()) add(CustomAccessibilityAction("Undo last dose") { actions.onUndoLast(); true })
        add(CustomAccessibilityAction(setTimeOrDay) { if (offersSetTime) actions.onSetTime() else actions.onOpenDay(); true })
        add(CustomAccessibilityAction("Edit item") { actions.onEdit(); true })
    }

    Box {
        Column(
            Modifier
                .fillMaxWidth()
                .background(colors.signalWash.copy(alpha = colors.signalWash.alpha * wash.value))
                .combinedClickable(
                    onClick = actions.onTap,
                    onClickLabel = clickLabel,
                    onLongClick = { menuOpen = true },
                    onLongClickLabel = "Options",
                )
                .semantics {
                    contentDescription = label
                    this.customActions = customActions
                }
                .testTag("row-${row.item.name}"),
        ) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 64.dp).clearAndSetSemantics { },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f).padding(start = 16.dp, top = 10.dp, bottom = 10.dp)) {
                    Text(
                        row.item.name,
                        style = TakenType.sans(17, FontWeight.Medium),
                        color = if (quiet) colors.fgMuted else colors.fg,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.size(3.dp))
                    Text(TodayRules.subtitle(row, note), style = TakenType.sans(14), color = colors.fgSubtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Crossfade(targetState = editing, label = "trailing") { isEditing ->
                    Box(Modifier.widthIn(min = 72.dp).padding(start = 8.dp, end = 16.dp), contentAlignment = Alignment.CenterEnd) {
                        if (isEditing) {
                            Icon(Symbols.ChevronRight, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(22.dp))
                        } else {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                val last = row.lastDose
                                if (last != null) {
                                    Text(Fmt.doseClock(last, today, clock), style = TakenType.mono(15), color = colors.signalInk, maxLines = 1)
                                    Spacer(Modifier.width(10.dp))
                                }
                                DoseRing(
                                    total = if (row.isDue) row.dosesPerDay else 1,
                                    taken = row.takenCount,
                                    quiet = quiet,
                                    locked = locked && (row.isPending || quiet),
                                    modifier = Modifier.scale(lift.value),
                                )
                            }
                        }
                    }
                }
            }
            AnimatedVisibility(
                visible = expanded && !editing,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically(),
            ) {
                Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp).clearAndSetSemantics { }) {
                    for (line in TodayRules.timeLines(row, today, clock, now)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(line.lead, style = TakenType.sans(14), color = colors.fgMuted)
                            Spacer(Modifier.width(6.dp))
                            Text(line.time, style = TakenType.mono(14), color = colors.fgMuted)
                            Spacer(Modifier.width(6.dp))
                            Text(line.ago, style = TakenType.sans(14), color = colors.fgMuted)
                        }
                        Spacer(Modifier.size(6.dp))
                    }
                }
            }
        }
        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { menuOpen = false },
            offset = androidx.compose.ui.unit.DpOffset(16.dp, 0.dp),
            shape = RoundedCornerShape(Taken.shapes.card),
            containerColor = colors.bgRaised,
            tonalElevation = 0.dp,
            shadowElevation = 0.dp,
            border = BorderStroke(1.dp, colors.lineStrong),
        ) {
            val itemColors = MenuDefaults.itemColors(
                textColor = colors.fg,
                leadingIconColor = colors.fgMuted,
                disabledTextColor = colors.fgFaint,
                disabledLeadingIconColor = colors.fgFaint,
            )
            DropdownMenuItem(
                text = { Text("Undo last dose", style = TakenType.sans(16)) },
                onClick = { menuOpen = false; actions.onUndoLast() },
                leadingIcon = { Icon(Symbols.Undo, contentDescription = null, modifier = Modifier.size(20.dp)) },
                enabled = row.doses.isNotEmpty(),
                colors = itemColors,
            )
            DropdownMenuItem(
                text = { Text(if (offersSetTime) "Set time…" else "Open ${Fmt.weekday(row.day)}", style = TakenType.sans(16)) },
                onClick = {
                    menuOpen = false
                    if (offersSetTime) actions.onSetTime() else actions.onOpenDay()
                },
                leadingIcon = {
                    Icon(if (offersSetTime) Symbols.Schedule else Symbols.CalendarToday, contentDescription = null, modifier = Modifier.size(20.dp))
                },
                colors = itemColors,
            )
            DropdownMenuItem(
                text = { Text("Edit item", style = TakenType.sans(16)) },
                onClick = { menuOpen = false; actions.onEdit() },
                leadingIcon = { Icon(Symbols.Tune, contentDescription = null, modifier = Modifier.size(20.dp)) },
                colors = itemColors,
            )
        }
    }
}

/**
 * The ring on the right of a row: empty while pending, one arc per dose for a 2x or 3x item (14° gaps, from the top),
 * and the look's signal with a check and a soft glow once everything due is taken. A small lock in a pending ring when
 * locked.
 */
@Composable
fun DoseRing(total: Int, taken: Int, quiet: Boolean, locked: Boolean, modifier: Modifier = Modifier) {
    val colors = Taken.colors
    val count = maxOf(total, 1)
    val done = taken >= count
    val settle = remember { Animatable(if (done) 1f else 0.94f) }
    LaunchedEffect(done) {
        settle.animateTo(if (done) 1f else 0.94f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMedium))
    }
    Box(modifier.size(30.dp).scale(settle.value), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(30.dp)) {
            val radius = size.minDimension / 2
            if (done) {
                drawCircle(
                    brush = Brush.radialGradient(
                        listOf(colors.glow(0.35f), Color.Transparent),
                        center = center,
                        radius = radius * 1.6f,
                    ),
                    radius = radius * 1.6f,
                )
                drawCircle(colors.signal, radius = radius)
                val side = 15.dp.toPx()
                drawCheck(colors.onSignal, side, 2.4.dp.toPx(), Offset(center.x - side / 2, center.y - side / 2))
            } else {
                val ringWidth = 1.5.dp.toPx()
                drawCircle(if (quiet) colors.line else colors.lineStrong, radius = radius - ringWidth / 2, style = Stroke(ringWidth))
                if (count > 1) {
                    val gap = 14f
                    val share = 360f / count
                    val arcWidth = 3.dp.toPx()
                    val inset = arcWidth / 2
                    for (index in 0 until minOf(taken, count)) {
                        drawArc(
                            color = colors.signal,
                            startAngle = -90f + share * index + gap / 2,
                            sweepAngle = share - gap,
                            useCenter = false,
                            topLeft = Offset(inset, inset),
                            size = Size(size.width - arcWidth, size.height - arcWidth),
                            style = Stroke(arcWidth, cap = StrokeCap.Round),
                        )
                    }
                }
            }
        }
        if (!done && locked) {
            Icon(Symbols.LockFill, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(11.dp))
        }
    }
}
