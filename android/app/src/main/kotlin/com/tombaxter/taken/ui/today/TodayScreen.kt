package com.tombaxter.taken.ui.today

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.PaywallOrigin
import com.tombaxter.taken.Sheet
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.retention.RetentionCopy
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.stack.DaySummary
import com.tombaxter.taken.core.stack.ItemDay
import com.tombaxter.taken.core.stack.ProgressCopy
import com.tombaxter.taken.core.stack.TodayRules
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.CapsuleGlyph
import com.tombaxter.taken.ui.components.InkButton
import com.tombaxter.taken.ui.components.PrimaryButton
import com.tombaxter.taken.ui.components.ProgressBar
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.SectionHeader
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.drawCheck
import com.tombaxter.taken.ui.shell.TabHeader
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/**
 * Today (SPEC 3.1, SPEC-ANDROID 7.2): the title and the long day, one calm progress line, at most one quiet row, then the
 * Stack with the pencil and "+" beside its title, and the Not today group. A tap on a row logs; the pencil turns every
 * row into a way into its item until the check.
 */
@Composable
fun TodayScreen(model: AppModel, bottomDock: @Composable () -> Unit) {
    val colors = Taken.colors
    Column(Modifier.fillMaxSize().background(colors.bg)) {
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp)
                .testTag("today"),
        ) {
            TabHeader(model, title = "Today", subtitle = Fmt.longDay(model.today.day))
            if (model.hasStack) {
                StackContent(model)
            } else {
                Spacer(Modifier.height(28.dp))
                EmptyStack(model)
            }
        }
        bottomDock()
    }
}

@Composable
private fun StackContent(model: AppModel) {
    val today = model.today
    Spacer(Modifier.height(18.dp))
    ProgressSummary(today, model, model.lockInCount, model.streak)
    if (model.isLocked) {
        Spacer(Modifier.height(16.dp))
        LockedBar(model.lockedBarText) { model.presentPaywall(PaywallOrigin.BAR) }
    } else {
        val prompt = model.todayPrompt
        if (prompt != null) {
            Spacer(Modifier.height(16.dp))
            TodayPromptRow(model, prompt)
        }
    }
    StackHeader(model)
    if (today.due.isEmpty()) {
        Card {
            Box(Modifier.fillMaxWidth().heightIn(min = 64.dp), contentAlignment = Alignment.Center) {
                Text("Nothing due today", style = TakenType.sans(16), color = Taken.colors.fgMuted)
            }
        }
    } else {
        Card { Rows(model, today.due, notDue = false) }
    }
    if (today.notDue.isNotEmpty()) {
        SectionHeader("Not today")
        Card { Rows(model, today.notDue, notDue = true) }
    }
}

@Composable
private fun Rows(model: AppModel, items: List<ItemDay>, notDue: Boolean) {
    Column {
        items.forEachIndexed { index, entry ->
            if (index > 0) RowDivider()
            // Not today: a weekly item shows the week today is in, with the line that goes with it.
            val shown = if (notDue) model.notTodayRow(entry) else TodayRules.NotTodayRow(entry, "")
            val row = shown.row
            // Each row's remembered state (its moment, its menu, its ring's settle) follows its item, not its place, as
            // SwiftUI's ForEach by id does: archiving or deleting one row never plays another's moment.
            key(row.item.id) {
                ItemRow(
                    row = row,
                    today = model.today.day,
                    clock = model.clock,
                    now = model.now,
                    expanded = model.expandedItemId == row.item.id,
                    nextLabel = if (notDue) model.nextLabel(entry) else null,
                    note = if (notDue) shown.note else null,
                    locked = model.isLocked,
                    editing = model.editingStack,
                    logs = model.rowLogs[row.item.id] ?: 0,
                    offersSetTime = model.offersSetTime(row),
                    actions = RowActions(
                        onTap = { model.tap(row) },
                        onUndoLast = { model.undoLastDose(row) },
                        // Set time logs or moves a dose, so in locked mode it opens the paywall instead.
                        onSetTime = { model.requirePro { model.sheet = Sheet.SetTime(row.item.id) } },
                        onOpenDay = { model.sheet = Sheet.Day(row.day) },
                        onEdit = { model.sheet = Sheet.EditItem(row.item.id) },
                    ),
                )
            }
        }
    }
}

/** "Stack", then the pencil (edit mode) and the "+" (Add), each a 48 dp target. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StackHeader(model: AppModel) {
    val colors = Taken.colors
    val editing = model.editingStack
    Row(Modifier.fillMaxWidth().padding(top = 20.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            "Stack",
            style = TakenType.sans(20, FontWeight.SemiBold),
            color = colors.fg,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        // The pencil: Material Symbols' Edit, with a plain tooltip (https://developer.android.com/develop/ui/compose/components/tooltip).
        TooltipBox(
            positionProvider = TooltipDefaults.rememberTooltipPositionProvider(TooltipAnchorPosition.Above),
            tooltip = { PlainTooltip { Text(if (editing) "Done" else "Edit stack") } },
            state = rememberTooltipState(),
        ) {
            Box(
                Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    // TalkBack: "Edit stack, double tap to open items instead of logging them", the iPhone's hint as Android's
                    // click label.
                    .clickable(
                        role = Role.Button,
                        onClickLabel = if (editing) "log items again" else "open items instead of logging them",
                    ) { model.setEditingStack(!editing) }
                    .semantics { contentDescription = if (editing) "Done" else "Edit stack" }
                    .testTag("edit-stack"),
                contentAlignment = Alignment.Center,
            ) {
                Crossfade(targetState = editing, label = "pencil") { on ->
                    Icon(if (on) Symbols.Check else Symbols.Edit, contentDescription = null, tint = colors.signalInk, modifier = Modifier.size(22.dp))
                }
            }
        }
        Spacer(Modifier.width(4.dp))
        Box(
            Modifier
                .size(48.dp)
                .clip(CircleShape)
                .clickable(role = Role.Button, onClickLabel = "add") { model.requirePro { model.sheet = Sheet.Add } }
                .semantics { contentDescription = "Add to stack" }
                .testTag("add-to-stack"),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(36.dp).background(colors.signalWash, CircleShape).border(1.dp, colors.signalEdge, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Symbols.Add, contentDescription = null, tint = colors.signalInk, modifier = Modifier.size(22.dp))
            }
        }
    }
}

/** For tests: the All taken check's scale on the progress line, so the moment can be checked frame by frame. */
val AllTakenCheckScale = SemanticsPropertyKey<Float>("AllTakenCheckScale")

/** The All taken check springs in from this scale (the iPhone's `pop`). */
private const val POP_FROM = 0.55f

/**
 * Today's one calm progress line: "4 of 6 taken" with a slim bar, in doses as the widgets count them. When everything
 * due is taken it becomes the All taken moment: the check springs in with the CONFIRM haptic. The moment's state lives
 * here, on the line that exists before and after the switch (the iPhone's `onChange` sits on the same Group): the tap that
 * finishes the day raises `lockInCount` in the same frame that shows All taken, so the check compares against the count
 * from before it existed.
 */
@Composable
fun ProgressSummary(summary: DaySummary, model: AppModel, lockInCount: Int, streak: Int) {
    val colors = Taken.colors
    val last = ProgressCopy.lastTime(summary, model.clock)
    val pop = remember { Animatable(1f) }
    var played by remember { mutableIntStateOf(lockInCount) }
    LaunchedEffect(lockInCount) {
        if (lockInCount > played) {
            pop.snapTo(POP_FROM)
            played = lockInCount
            pop.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessLow))
        }
        played = lockInCount
    }
    // Until the effect starts, a new count draws the check small already, so it never flashes full size first.
    val checkScale = if (lockInCount > played) POP_FROM else pop.value
    Box(
        Modifier.fillMaxWidth().clearAndSetSemantics {
            contentDescription = ProgressCopy.spoken(summary)
            testTag = "progress"
            if (summary.dueDoses > 0 && summary.allTaken) this[AllTakenCheckScale] = checkScale
        },
    ) {
        when {
            summary.dueDoses == 0 -> Text("Nothing due today", style = TakenType.sans(17), color = colors.fgMuted)
            summary.allTaken -> AllTaken(last, streak, summary.lastDose != null, checkScale)
            else -> Column {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("${summary.takenDueDoses}", style = TakenType.mono(22), color = colors.fg)
                    Text(" of ", style = TakenType.sans(18), color = colors.fgMuted)
                    Text("${summary.dueDoses}", style = TakenType.mono(22), color = colors.fg)
                    Text(" taken", style = TakenType.sans(18), color = colors.fgMuted)
                    Spacer(Modifier.weight(1f))
                    if (last != null) {
                        Text("Last ", style = TakenType.sans(14), color = colors.fgSubtle)
                        Text(last, style = TakenType.mono(14), color = colors.fgSubtle)
                    }
                }
                Spacer(Modifier.height(12.dp))
                ProgressBar(summary.takenDueDoses.toFloat() / maxOf(summary.dueDoses, 1).toFloat())
            }
        }
    }
}

@Composable
private fun AllTaken(last: String?, streak: Int, hasLast: Boolean, checkScale: Float) {
    val colors = Taken.colors
    Row(verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.size(40.dp).scale(checkScale)) {
            val radius = size.minDimension / 2
            drawCircle(Brush.radialGradient(listOf(colors.glow(0.35f), Color.Transparent), center, radius * 1.7f), radius * 1.7f)
            drawCircle(colors.signal, radius)
            val side = 20.dp.toPx()
            drawCheck(colors.onSignal, side, 3.dp.toPx(), Offset(center.x - side / 2, center.y - side / 2))
        }
        Spacer(Modifier.width(14.dp))
        Column {
            Text("All taken", style = TakenType.sans(24, FontWeight.SemiBold), color = colors.signalInk)
            Spacer(Modifier.height(3.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                if (last != null) {
                    Text("Last dose ", style = TakenType.sans(14), color = colors.fgSubtle)
                    Text(last, style = TakenType.mono(14), color = colors.fgSubtle)
                }
                if (streak > 1) {
                    Text(if (hasLast) " · " else "", style = TakenType.sans(14), color = colors.fgSubtle)
                    Text("$streak", style = TakenType.mono(14), color = colors.fgSubtle)
                    Text("-day streak", style = TakenType.sans(14), color = colors.fgSubtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** Locked mode: a slim bar under the progress line. The log stays readable; a tap opens Taken Pro. */
@Composable
private fun LockedBar(text: String, onClick: () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(colors.signalWash, shape)
            .border(1.dp, colors.signalEdge, shape)
            .clickable(role = Role.Button, onClickLabel = "open Taken Pro", onClick = onClick)
            .semantics { contentDescription = "Logging needs Taken Pro. $text." }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Symbols.LockFill, contentDescription = null, tint = colors.signalInk, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(10.dp))
        Text(text, style = TakenType.sans(15, FontWeight.Medium), color = colors.fg, modifier = Modifier.weight(1f), maxLines = 1)
        Icon(Symbols.ChevronRight, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(18.dp))
    }
}

/** Today's one quiet row (SPEC 3.1): the nudge offer or the repair, never in the way of a row. */
@Composable
private fun TodayPromptRow(model: AppModel, prompt: TodayPrompt) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    when (prompt) {
        is TodayPrompt.NudgeOffer -> Column(
            Modifier.fillMaxWidth().background(colors.bgRaised, shape).border(1.dp, colors.line, shape)
                .padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 2.dp),
        ) {
            Row(verticalAlignment = Alignment.Top) {
                Icon(Symbols.Notifications, contentDescription = null, tint = colors.signalInk, modifier = Modifier.size(18.dp).padding(top = 1.dp))
                Spacer(Modifier.width(10.dp))
                Text(RetentionCopy.nudgeOffer(prompt.minutes), style = TakenType.sans(15, FontWeight.Medium), color = colors.fg)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(Taken.shapes.cell))
                        .clickable(role = Role.Button) { model.answerNudgeOffer(turnOn = false) }.padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center,
                ) { Text(RetentionCopy.NOT_NOW, style = TakenType.sans(15, FontWeight.Medium), color = colors.fgMuted) }
                Box(
                    Modifier.heightIn(min = 48.dp).clickable(role = Role.Button) { model.answerNudgeOffer(turnOn = true) }
                        .semantics { contentDescription = RetentionCopy.TURN_ON }
                        .padding(horizontal = 4.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.height(34.dp).background(colors.signalWash, CircleShape).border(1.dp, colors.signalEdge, CircleShape)
                            .padding(horizontal = 14.dp),
                        contentAlignment = Alignment.Center,
                    ) { Text(RetentionCopy.TURN_ON, style = TakenType.sans(15, FontWeight.SemiBold), color = colors.signalInk) }
                }
            }
        }
        is TodayPrompt.Repair -> Row(
            Modifier.fillMaxWidth().background(colors.bgRaised, shape).border(1.dp, colors.line, shape),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier.weight(1f).heightIn(min = 52.dp).clip(shape)
                    .clickable(role = Role.Button, onClickLabel = "open ${Fmt.longDay(prompt.day)}") { model.sheet = Sheet.Day(prompt.day) }
                    .semantics { contentDescription = RetentionCopy.repair }
                    .padding(start = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(RetentionCopy.REPAIR_QUESTION, style = TakenType.sans(15, FontWeight.Medium), color = colors.fg)
                Spacer(Modifier.width(6.dp))
                Text(RetentionCopy.REPAIR_ACTION, style = TakenType.sans(15, FontWeight.SemiBold), color = colors.signalInk)
            }
            Box(
                Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Button) { model.closeRepair(prompt.day) }
                    .semantics { contentDescription = RetentionCopy.CLOSE },
                contentAlignment = Alignment.Center,
            ) { Icon(Symbols.Close, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(18.dp)) }
        }
        // "Log from your home screen: add the Taken widget": a tap asks the launcher to pin the stack widget (its own
        // dialog shows the widget), the close hides it; either way it is gone for good (SPEC-ANDROID 10.1).
        TodayPrompt.WidgetInvite -> {
            LaunchedEffect(Unit) { model.noteWidgetInviteShown() }
            Row(
                Modifier.fillMaxWidth().background(colors.bgRaised, shape).border(1.dp, colors.line, shape).testTag("widget-invite"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    Modifier.weight(1f).heightIn(min = 52.dp).clip(shape)
                        .clickable(role = Role.Button, onClickLabel = "add the widget") { model.closeWidgetInvite(pin = true) }
                        .padding(start = 16.dp, top = 12.dp, bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(RetentionCopy.WIDGET_INVITE, style = TakenType.sans(15, FontWeight.Medium), color = colors.fg)
                }
                Box(
                    Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Button) { model.closeWidgetInvite(pin = false) }
                        .semantics { contentDescription = RetentionCopy.CLOSE },
                    contentAlignment = Alignment.Center,
                ) { Icon(Symbols.Close, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(18.dp)) }
            }
        }
        // The trial notice and the weight offer come with their phases (NEXT 2 and 6).
        else -> Unit
    }
}

/** First run: no onboarding, just the way in. */
@Composable
private fun EmptyStack(model: AppModel) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    Column(
        Modifier.fillMaxWidth().background(colors.bgRaised, shape).border(1.dp, colors.line, shape).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CapsuleGlyph(Modifier.size(64.dp).padding(top = 8.dp), fill = colors.signal, stroke = colors.fgSubtle)
        Spacer(Modifier.height(18.dp))
        Text("Nothing in your stack yet", style = TakenType.sans(20, FontWeight.SemiBold), color = colors.fg, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        // Balanced lines, never one word alone on the second (https://developer.android.com/develop/ui/compose/text/style-paragraph).
        Text(
            "Tap what you take. It takes a few seconds.",
            style = TakenType.sans(15).copy(lineBreak = LineBreak.Heading),
            color = colors.fgSubtle,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        PrimaryButton("Add to stack", locked = model.isLocked) { model.requirePro { model.sheet = Sheet.Add } }
    }
}

/** Take all, pinned above the navigation bar: for 2 or more rows Take all logs right now, and never while editing. */
@Composable
fun TakeAllButton(model: AppModel) {
    val count = model.takeAllCount
    AnimatedVisibility(visible = TodayRules.showsTakeAll(count, model.editingStack), enter = fadeIn(), exit = fadeOut()) {
        PrimaryButton(
            "Take all",
            locked = model.isLocked,
            count = count,
            modifier = Modifier
                .padding(horizontal = 20.dp)
                .padding(top = 10.dp, bottom = 8.dp)
                .semantics {
                    contentDescription = "Take all, $count"
                }
                .testTag("take-all"),
        ) { model.requirePro { model.takeAll() } }
    }
}
