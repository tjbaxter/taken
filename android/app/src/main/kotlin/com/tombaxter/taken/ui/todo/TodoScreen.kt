package com.tombaxter.taken.ui.todo

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxDefaults
import androidx.compose.material3.SwipeToDismissBoxState
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.Sheet
import com.tombaxter.taken.TodoModel
import com.tombaxter.taken.core.todo.TodoCapture
import com.tombaxter.taken.core.todo.TodoCopy
import com.tombaxter.taken.core.todo.TodoTask
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.drawCheck
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TabHeader
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The To-do tab (SPEC 3.10, SPEC-ANDROID 11; the iPhone's Taken/Todo/TodoRootView.swift): one list, the open tasks due
 * first, then Done today; a tap on the circle finishes a task, a tap on the words opens it, a swipe to the start deletes
 * it with Undo and a swipe to the end finishes it. The dock holds the undo bar, one line (the listening card, the blocker, Keep as one or a notice), the big
 * mic and "Tap to finish". Voice capture stays tap, speak, end: no choice on the way, no waveform.
 */
@Composable
fun TodoScreen(model: AppModel, platform: Platform) {
    val todo = model.todo
    val colors = Taken.colors
    val open = todo.openTasks
    val done = todo.doneToday
    val list = rememberLazyListState()

    // Due labels and Done today follow the clock while the tab is open.
    LaunchedEffect(todo) {
        while (true) {
            delay(30_000)
            todo.refresh()
        }
    }
    // A quick capture (`taken://todo/record`) starts once To-do is in front with nothing over it, so Listening and the
    // stop button are on screen when the mic opens: the iPhone's 450 ms, then up to 12 x 150 ms. The wait runs in the
    // screen's scope, not the effect's: taking the request changes the key, which would cancel the effect.
    val pending = todo.pendingRecording
    val screen = rememberCoroutineScope()
    LaunchedEffect(pending) {
        if (pending == null || !todo.takePendingRecording()) return@LaunchedEffect
        screen.launch {
            delay(450)
            var waited = 0
            while (!model.showsTodoTabUncovered && waited < 12) {
                delay(150)
                waited += 1
            }
            if (model.showsTodoTabUncovered) todo.startFromRequest()
        }
    }
    // A note just saved, or a tapped due-time notification: its task comes into view, then the request is cleared.
    val target = todo.scrollTarget
    LaunchedEffect(target) {
        val id = target ?: return@LaunchedEffect
        val openIndex = open.indexOfFirst { it.id == id }
        val doneIndex = done.indexOfFirst { it.id == id }
        val index = when {
            openIndex >= 0 -> 1 + openIndex
            doneIndex >= 0 -> 2 + open.size + doneIndex
            else -> -1
        }
        if (index >= 0) list.animateScrollToItem(index)
        todo.scrollTarget = null
    }

    Column(Modifier.fillMaxSize().background(colors.bg)) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            LazyColumn(state = list, modifier = Modifier.fillMaxSize().testTag("todo"), contentPadding = PaddingValues(bottom = 16.dp)) {
                item(key = "header") {
                    Box(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 14.dp)) {
                        TabHeader(model, title = "To-do", subtitle = TodoCopy.summary(open.size, done.size))
                    }
                }
                items(open, key = { it.id.toString() }) { task ->
                    TodoRow(todo, task) { model.sheet = Sheet.TodoEdit(task.id) }
                }
                if (done.isNotEmpty()) {
                    item(key = "done-today") {
                        Text(
                            TodoCopy.DONE_TODAY,
                            style = TakenType.sans(13, FontWeight.Medium),
                            color = colors.fgSubtle,
                            modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 26.dp, bottom = 6.dp).semantics { heading() },
                        )
                    }
                    items(done, key = { it.id.toString() }) { task ->
                        TodoRow(todo, task) { model.sheet = Sheet.TodoEdit(task.id) }
                    }
                }
            }
            if (todo.isEmpty && todo.phase == TodoCapture.Phase.IDLE && todo.blocker == null) {
                Text(
                    TodoCopy.EMPTY,
                    style = TakenType.sans(17),
                    color = colors.fgMuted,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.align(Alignment.Center).padding(horizontal = 40.dp).testTag("todo-empty"),
                )
            }
        }
        TodoDock(model, platform)
    }
}

/**
 * A task: the circle (a 48 dp target), the title in two lines at most, and the due day in Geist with the time in Geist
 * Mono (`signalInk` when late), or the time a done task was done. One TalkBack node: "Call the dentist, due tomorrow at
 * 9:00 AM", double tap to mark it done, with Edit, Delete and, while offered, Keep as one as actions.
 */
@Composable
private fun TodoRow(todo: TodoModel, task: TodoTask, onEdit: () -> Unit) {
    val colors = Taken.colors
    val done = task.isDone
    val filling = task.id in todo.completing
    val washed = task.id in todo.arrived
    // A task that just came in washes in the signal (in 0.1 s, out over 0.4 s), as on the iPhone.
    val wash by animateColorAsState(if (washed) colors.signalWash else Color.Transparent, tween(if (washed) 100 else 400), label = "wash")
    val keepOffered = todo.keepOffer?.ids?.contains(task.id) == true
    // A plain `remember`, not the saveable state `rememberSwipeToDismissBoxState` keeps: the list saves a row's saveable
    // state by its key, so a task put back with Undo would come back already swiped away and be deleted again. The
    // dismiss callback is one object per row, since SwipeToDismissBox restarts its effect when the callback changes.
    val threshold = SwipeToDismissBoxDefaults.positionalThreshold
    val swipe = remember { SwipeToDismissBoxState(SwipeToDismissBoxValue.Settled, threshold) }
    val current by rememberUpdatedState(task)
    val rowScope = rememberCoroutineScope()
    // To the start deletes (the iPhone's swipe, with Undo); to the end finishes or reopens and the row springs back, as
    // Android's own swipe-to-dismiss guide does for a to-do list
    // (https://developer.android.com/develop/ui/compose/touch-input/user-interactions/swipe-to-dismiss).
    val dismiss: (SwipeToDismissBoxValue) -> Unit = remember(todo) {
        { value ->
            when (value) {
                SwipeToDismissBoxValue.EndToStart -> todo.delete(current)
                SwipeToDismissBoxValue.StartToEnd -> {
                    todo.toggle(current)
                    rowScope.launch { swipe.reset() }
                }
                SwipeToDismissBoxValue.Settled -> Unit
            }
        }
    }
    SwipeToDismissBox(
        state = swipe,
        backgroundContent = { SwipeBehind(swipe.dismissDirection, done) },
        onDismiss = dismiss,
        modifier = Modifier.clearAndSetSemantics {
            testTag = "todo-row-${task.title}"
            contentDescription = todo.spoken(task)
            onClick(label = if (done) "mark not done" else "mark done") {
                todo.toggle(task)
                true
            }
            customActions = listOfNotNull(
                CustomAccessibilityAction("Edit") {
                    onEdit()
                    true
                },
                CustomAccessibilityAction("Delete") {
                    todo.delete(task)
                    true
                },
                if (keepOffered) {
                    CustomAccessibilityAction(TodoCopy.KEEP_AS_ONE) {
                        todo.keepAsOne()
                        true
                    }
                } else {
                    null
                },
            )
        },
    ) {
        Column(Modifier.fillMaxWidth().background(colors.bg).background(wash)) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(start = 6.dp, end = 20.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TodoCheck(done = done || filling) { todo.toggle(task) }
                val words = Modifier
                    .weight(1f)
                    .heightIn(min = 48.dp)
                    .clickable(onClick = onEdit)
                    .padding(start = 6.dp, top = 10.dp, bottom = 10.dp)
                val title = @Composable { modifier: Modifier, lines: Int ->
                    // Two lines at most, so the list stays a list; the whole title is in the edit sheet and in TalkBack.
                    Text(
                        task.title,
                        style = TakenType.sans(17),
                        color = if (done) colors.fgSubtle else colors.fg,
                        textDecoration = if (done || filling) TextDecoration.LineThrough else null,
                        maxLines = lines,
                        overflow = TextOverflow.Ellipsis,
                        modifier = modifier,
                    )
                }
                if (LocalDensity.current.fontScale >= LARGE_TEXT) {
                    // At large text the due day and time go under the words, so neither squeezes the other.
                    // [Own choice: the iPhone keeps one line; at 200% it leaves the title a word or two]
                    Column(words) {
                        title(Modifier, 3)
                        Row { TrailingParts(todo, task, leading = 0.dp) }
                    }
                } else {
                    Row(words, verticalAlignment = Alignment.CenterVertically) {
                        title(Modifier.weight(1f), 2)
                        TrailingParts(todo, task)
                    }
                }
            }
            // The hairline stops at the row's 20 dp end margin, level with the due times, as the iPhone's separators do.
            Box(Modifier.fillMaxWidth().padding(start = 60.dp, end = 20.dp).height(1.dp).background(colors.line))
        }
    }
}

/** "Tomorrow 09:00": the day in Geist, the time in Geist Mono. A done task shows when it was done. */
@Composable
private fun TrailingParts(todo: TodoModel, task: TodoTask, leading: androidx.compose.ui.unit.Dp = 10.dp) {
    val colors = Taken.colors
    val day: String?
    val time: String?
    if (task.isDone) {
        day = null
        time = todo.doneLabel(task) ?: return
    } else {
        val parts = todo.dueParts(task) ?: return
        day = parts.day
        time = parts.time
    }
    val ink = if (todo.isOverdue(task)) colors.signalInk else colors.fgSubtle
    Spacer(Modifier.width(leading))
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (day != null) Text(day, style = TakenType.sans(14), color = ink, maxLines = 1)
        if (day != null && time != null) Spacer(Modifier.width(4.dp))
        if (time != null) Text(time, style = TakenType.mono(13), color = ink, maxLines = 1)
    }
}

/**
 * What a swipe shows behind the row: to the start, Delete in the look's danger; to the end, Done (or Not done) in the
 * look's signal.
 */
@Composable
private fun SwipeBehind(direction: SwipeToDismissBoxValue, done: Boolean) {
    val colors = Taken.colors
    when (direction) {
        SwipeToDismissBoxValue.EndToStart -> Row(
            Modifier.fillMaxSize().background(colors.danger).padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Symbols.Delete, contentDescription = null, tint = colors.bg, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(6.dp))
            Text("Delete", style = TakenType.sans(15, FontWeight.SemiBold), color = colors.bg)
        }
        SwipeToDismissBoxValue.StartToEnd -> Row(
            Modifier.fillMaxSize().background(colors.signal).padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.Start,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Symbols.Check, contentDescription = null, tint = colors.onSignal, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(6.dp))
            Text(if (done) "Not done" else "Done", style = TakenType.sans(15, FontWeight.SemiBold), color = colors.onSignal)
        }
        SwipeToDismissBoxValue.Settled -> Unit
    }
}

/** The circle: an empty ring, or the look's signal with a check, springing in. A 48 dp target. */
@Composable
fun TodoCheck(done: Boolean, onClick: () -> Unit) {
    val colors = Taken.colors
    val fill by animateFloatAsState(
        if (done) 1f else 0f,
        spring(dampingRatio = 0.62f, stiffness = Spring.StiffnessMediumLow),
        label = "check",
    )
    Box(
        Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Checkbox, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(24.dp)) {
            val radius = size.minDimension / 2
            val stroke = 1.5.dp.toPx()
            drawCircle(if (done) colors.signal else colors.lineStrong, radius - stroke / 2, style = Stroke(stroke))
            if (fill > 0.01f) {
                drawCircle(colors.signal, radius * fill.coerceAtMost(1.1f))
                val side = size.minDimension * fill.coerceIn(0.4f, 1f)
                val origin = Offset((size.width - side) / 2, (size.height - side) / 2)
                drawCheck(colors.onSignal.copy(alpha = fill.coerceIn(0f, 1f)), side, 2.dp.toPx(), origin)
            }
        }
    }
}

// MARK: Dock

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TodoDock(model: AppModel, platform: Platform) {
    val todo = model.todo
    val colors = Taken.colors
    val phase = todo.phase
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.bg)
            .animateContentSize()
            .padding(start = 20.dp, end = 20.dp, top = 10.dp, bottom = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        todo.deleted?.let { UndoBar(it.title) { todo.undoDelete() } }
        val blocker = todo.blocker
        val offer = todo.keepOffer
        val notice = todo.notice
        when {
            phase == TodoCapture.Phase.LISTENING || phase == TodoCapture.Phase.SORTING -> ListeningCard(todo)
            blocker != null -> BlockerCard(blocker, onSettings = platform::openAppSettings) { model.sheet = Sheet.TodoType }
            offer != null -> KeepLine(offer.ids.size) { todo.keepAsOne() }
            notice != null -> Text(
                notice,
                style = TakenType.sans(14),
                color = colors.fgMuted,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().testTag("todo-notice"),
            )
        }
        MicButton(phase, todo.level) { todo.micTapped() }
        if (phase == TodoCapture.Phase.LISTENING) {
            Text(TodoCopy.TAP_TO_FINISH, style = TakenType.sans(13), color = colors.fgSubtle)
        }
    }
}

/**
 * What is being heard: the original card (Tom 2026-10-21). The signal dot, "Listening" or "Sorting into to-dos" (with the
 * part of a long note), from 4:00 a quiet "1 minute left", once, and the newest words: four lines at most, the oldest cut
 * off at the top. No waveform, no time.
 */
@Composable
fun ListeningCard(todo: TodoModel) {
    val colors = Taken.colors
    val sorting = todo.phase == TodoCapture.Phase.SORTING
    val text = todo.transcript
    val progress = todo.sortingProgress
    val shape = RoundedCornerShape(Taken.shapes.card)
    val label = when {
        sorting -> TodoCopy.SORTING
        text.isEmpty() -> TodoCopy.LISTENING
        else -> text
    }
    val value = when {
        sorting -> progress?.let { TodoCopy.part(it.part, it.of) } ?: ""
        todo.inLastMinute -> TodoCopy.ONE_MINUTE_LEFT
        else -> ""
    }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.bgRaised, shape)
            .border(1.dp, colors.line, shape)
            .clearAndSetSemantics {
                testTag = "listening-card"
                contentDescription = label
                stateDescription = value
            }
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).alpha(if (sorting) 0.4f else 1f).background(colors.signal, CircleShape))
            Spacer(Modifier.width(8.dp))
            Text(
                if (sorting) TodoCopy.SORTING else TodoCopy.LISTENING,
                style = TakenType.sans(13, FontWeight.Medium),
                color = colors.fgMuted,
                maxLines = 1,
            )
            if (sorting && progress != null) {
                Spacer(Modifier.width(8.dp))
                Text(TodoCopy.part(progress.part, progress.of), style = TakenType.sans(13), color = colors.fgSubtle, maxLines = 1)
            }
            Spacer(Modifier.weight(1f).widthIn(min = 12.dp))
            if (!sorting && todo.inLastMinute) {
                Text(TodoCopy.ONE_MINUTE_LEFT, style = TakenType.sans(13), color = colors.fgSubtle, maxLines = 1)
            }
        }
        Spacer(Modifier.height(12.dp))
        val style = TakenType.sans(19, lineHeight = 25.sp)
        val density = LocalDensity.current
        // The newest words stay in view: the text sits on the bottom of a window exactly as tall as its last four lines,
        // measured from its own layout, and the older lines are clipped at the top (the iPhone truncates the head). Until
        // the first layout, four lines of 25 sp.
        var window by remember { mutableStateOf<androidx.compose.ui.unit.Dp?>(null) }
        val sized = window?.let { Modifier.height(it) } ?: Modifier.heightIn(max = with(density) { 25.sp.toDp() * 4 })
        Box(Modifier.fillMaxWidth().then(sized).clipToBounds(), contentAlignment = Alignment.BottomStart) {
            Text(
                if (text.isEmpty()) TodoCopy.SAY_IT else TodoCapture.tail(text),
                style = style,
                color = if (text.isEmpty()) colors.fgFaint else colors.fg,
                onTextLayout = { layout ->
                    val lines = layout.lineCount
                    val shown = if (lines > SHOWN_LINES) {
                        layout.getLineBottom(lines - 1) - layout.getLineTop(lines - SHOWN_LINES)
                    } else {
                        layout.size.height.toFloat()
                    }
                    window = with(density) { shown.toDp() }
                },
                modifier = Modifier.fillMaxWidth().wrapContentHeight(align = Alignment.Bottom, unbounded = true),
            )
        }
    }
}

/** Why voice cannot run, with the way round it: Open Settings for the microphone, and always Type it instead. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BlockerCard(blocker: TodoModel.Blocker, onSettings: () -> Unit, onType: () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    val message = when (blocker) {
        TodoModel.Blocker.MICROPHONE -> TodoCopy.MICROPHONE_OFF
        TodoModel.Blocker.UNAVAILABLE -> TodoCopy.UNAVAILABLE
        TodoModel.Blocker.DOWNLOADING -> TodoCopy.DOWNLOADING
    }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.bgRaised, shape)
            .border(1.dp, colors.line, shape)
            .padding(16.dp)
            .testTag("todo-blocker"),
    ) {
        Text(message, style = TakenType.sans(15), color = colors.fg)
        Spacer(Modifier.height(12.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val microphone = blocker == TodoModel.Blocker.MICROPHONE
            if (microphone) PillButton(TodoCopy.OPEN_SETTINGS, filled = true, onClick = onSettings)
            PillButton(TodoCopy.TYPE_INSTEAD, filled = !microphone, onClick = onType)
        }
    }
}

/** A small rounded button in the dock's cards: filled with the look's button, or outlined. */
@Composable
private fun PillButton(title: String, filled: Boolean, onClick: () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.cell)
    Box(
        Modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(if (filled) colors.button else Color.Transparent, shape)
            .border(1.dp, if (filled) Color.Transparent else colors.lineStrong, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = TakenType.sans(14, FontWeight.SemiBold), color = if (filled) colors.buttonText else colors.fg)
    }
}

/** "3 to-dos from your note   Keep as one": one quiet tap puts a split note back together. */
@Composable
private fun KeepLine(count: Int, onKeep: () -> Unit) {
    val colors = Taken.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Text(TodoCopy.fromYourNote(count), style = TakenType.sans(14), color = colors.fgMuted, maxLines = 1)
        Box(
            Modifier
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(Taken.shapes.cell))
                .clickable(role = Role.Button, onClick = onKeep)
                .padding(horizontal = 8.dp)
                .testTag("keep-as-one"),
            contentAlignment = Alignment.Center,
        ) {
            Text(TodoCopy.KEEP_AS_ONE, style = TakenType.sans(14, FontWeight.SemiBold), color = colors.signalInk, maxLines = 1)
        }
    }
}

/** "Deleted: Buy milk" with Undo, for 4 s after a swipe or a delete. */
@Composable
private fun UndoBar(title: String, onUndo: () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.bgRaised, shape)
            .border(1.dp, colors.line, shape)
            .padding(start = 16.dp, end = 4.dp)
            .testTag("todo-undo-bar"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            TodoCopy.deleted(title),
            style = TakenType.sans(14),
            color = colors.fgMuted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Box(
            Modifier
                .heightIn(min = 48.dp)
                .widthIn(min = 64.dp)
                .clip(RoundedCornerShape(Taken.shapes.cell))
                .clickable(role = Role.Button, onClick = onUndo)
                .testTag("todo-undo"),
            contentAlignment = Alignment.Center,
        ) {
            Text(TodoCopy.UNDO, style = TakenType.sans(14, FontWeight.SemiBold), color = colors.signalInk)
        }
    }
}

/**
 * The big round mic (76 dp). Listening, it becomes a stop square with a ring that breathes with the voice; starting or
 * saving, a spinner, and it waits. TalkBack: "New voice to-do", "Stop and sort".
 */
@Composable
private fun MicButton(phase: TodoCapture.Phase, level: Double, onClick: () -> Unit) {
    val colors = Taken.colors
    val listening = phase == TodoCapture.Phase.LISTENING
    val busy = phase == TodoCapture.Phase.STARTING || phase == TodoCapture.Phase.SORTING
    val ring by animateFloatAsState((1.08 + 0.3 * level).toFloat(), tween(120), label = "ring")
    val ringAlpha by animateFloatAsState((0.4 + 0.6 * level).toFloat(), tween(120), label = "ringAlpha")
    Box(Modifier.size(108.dp), contentAlignment = Alignment.Center) {
        if (listening) {
            Box(
                Modifier
                    .size(76.dp)
                    .graphicsLayer {
                        scaleX = ring
                        scaleY = ring
                        alpha = ringAlpha
                    }
                    .border(2.dp, colors.signalEdge, CircleShape),
            )
        }
        Box(
            Modifier
                .size(76.dp)
                .drawBehind {
                    val radius = size.minDimension / 2
                    val reach = radius + (if (listening) 18.dp else 10.dp).toPx()
                    drawCircle(Brush.radialGradient(listOf(colors.glow(0.28f), Color.Transparent), center, reach), reach)
                }
                .clip(CircleShape)
                .background(colors.signal)
                .clickable(
                    enabled = !busy,
                    role = Role.Button,
                    onClickLabel = if (listening) "turn what you said into to-dos" else "start listening",
                    onClick = onClick,
                )
                .semantics { contentDescription = if (listening) "Stop and sort" else "New voice to-do" }
                .testTag("mic"),
            contentAlignment = Alignment.Center,
        ) {
            when (phase) {
                TodoCapture.Phase.IDLE -> Icon(Symbols.MicFill, contentDescription = null, tint = colors.onSignal, modifier = Modifier.size(32.dp))
                TodoCapture.Phase.LISTENING -> Box(Modifier.size(24.dp).background(colors.onSignal, RoundedCornerShape(5.dp)))
                TodoCapture.Phase.STARTING, TodoCapture.Phase.SORTING ->
                    CircularProgressIndicator(color = colors.onSignal, strokeWidth = 2.5.dp, modifier = Modifier.size(26.dp).scale(0.9f))
            }
        }
    }
}

/**
 * Android's rationale before its microphone prompt, shown only when Android says one is due
 * (`shouldShowRequestPermissionRationale`), with a way to say no: "Always provide the option to cancel an educational UI
 * flow" (https://developer.android.com/training/permissions/requesting).
 */
@Composable
fun MicrophoneRationale(todo: TodoModel) {
    val colors = Taken.colors
    AlertDialog(
        onDismissRequest = { todo.answerMicrophoneRationale(false) },
        containerColor = colors.bgRaised,
        titleContentColor = colors.fg,
        textContentColor = colors.fgMuted,
        shape = RoundedCornerShape(Taken.shapes.card),
        title = { Text(TodoCopy.MIC_RATIONALE_TITLE, style = TakenType.sans(20, FontWeight.SemiBold)) },
        text = { Text(TodoCopy.MIC_RATIONALE, style = TakenType.sans(15)) },
        confirmButton = {
            TextButton(onClick = { todo.answerMicrophoneRationale(true) }) {
                Text(TodoCopy.CONTINUE, style = TakenType.sans(16, FontWeight.SemiBold), color = colors.signalInk)
            }
        },
        dismissButton = {
            TextButton(onClick = { todo.answerMicrophoneRationale(false) }) {
                Text(TodoCopy.NOT_NOW, style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted)
            }
        },
        modifier = Modifier.testTag("mic-rationale"),
    )
}

/** From this font scale the rows and the edit sheet stack what sits side by side at normal sizes. */
internal const val LARGE_TEXT = 1.5f

/** The listening card shows the last four lines of what is heard (the iPhone's `lineLimit(4)`). */
private const val SHOWN_LINES = 4
