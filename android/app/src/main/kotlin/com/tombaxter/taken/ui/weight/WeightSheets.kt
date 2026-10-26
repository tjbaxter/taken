package com.tombaxter.taken.ui.weight

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.weight.HeightUnit
import com.tombaxter.taken.core.weight.WeighIn
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightFormat
import com.tombaxter.taken.core.weight.WeightGoal
import com.tombaxter.taken.core.weight.WeightGoalCopy
import com.tombaxter.taken.core.weight.WeightGoals
import com.tombaxter.taken.core.weight.WeightImport
import com.tombaxter.taken.core.weight.WeightPoint
import com.tombaxter.taken.core.weight.WeightTrend
import com.tombaxter.taken.core.weight.day
import com.tombaxter.taken.deleteWeighIn
import com.tombaxter.taken.openWeighInEditor
import com.tombaxter.taken.saveWeightGoal
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.PrimaryButton
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.SheetHeader
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.TakenSheet
import com.tombaxter.taken.ui.components.TimeDialog
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.ToastHost
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import com.tombaxter.taken.updateWeighIn
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.util.Locale

// MARK: - All weigh-ins

/**
 * All weigh-ins (SPEC 3.12), ported from Taken/Weight/WeighInList.swift: every weigh-in, newest first, with its day, time
 * and weight. A tap opens it to change the weight, the day or the time (Taken Pro after the first weigh-in, as
 * backdating a dose needs it; the paywall comes over this sheet); a swipe to the start deletes it, always, with Undo
 * (Material's swipe to dismiss, https://developer.android.com/develop/ui/compose/touch-input/user-interactions/swipe-to-dismiss,
 * and TalkBack's "Delete" action). Hiding the tab never deletes anything here; only Erase all data does. The sheet is
 * its own window, so its toast is its own too.
 */
@Composable
fun WeighInsSheet(model: AppModel, platform: Platform, onDismiss: () -> Unit) {
    val weight = model.weight
    LaunchedEffect(Unit) {
        // Edit… on today's number: the editor is already open, and back leads to the list.
        weight.editOnOpen?.let { weight.editing = it }
        weight.editOnOpen = null
    }
    TakenSheet(onDismiss = onDismiss) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().imePadding().testTag("weigh-ins-sheet")) {
            val editing = weight.editing?.let { weight.state.weighIn(it) }
            Box(Modifier.weight(1f, fill = false)) {
                if (editing != null) {
                    key(editing.id) { WeighInEditor(model, editing) }
                } else {
                    WeighInList(model, onDismiss)
                }
            }
            ToastHost(model, platform)
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun WeighInList(model: AppModel, onClose: () -> Unit) {
    val colors = Taken.colors
    val weight = model.weight
    val rows = weight.state.newestFirst
    Column(Modifier.fillMaxWidth()) {
        SheetHeader(title = WeightCopy.ALL_WEIGH_INS, onClose = onClose)
        if (rows.isEmpty()) {
            Text(WeightCopy.NO_WEIGH_INS, style = TakenType.sans(16), color = colors.fgSubtle, modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp))
            return
        }
        val shape = Taken.shapes.card
        LazyColumn(Modifier.fillMaxWidth().padding(horizontal = 20.dp), state = rememberLazyListState()) {
            itemsIndexed(rows, key = { _, it -> it.id }) { index, weighIn ->
                val top = if (index == 0) shape else 0.dp
                val bottom = if (index == rows.lastIndex) shape else 0.dp
                val rowShape = RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom)
                Column(Modifier.clip(rowShape).background(colors.bgRaised)) {
                    if (index > 0) RowDivider()
                    SwipeToDeleteWeighIn(onDelete = { model.deleteWeighIn(weighIn.id) }) {
                        WeighInRow(model, weighIn) { model.openWeighInEditor(weighIn.id) }
                    }
                }
            }
            item { Spacer(Modifier.height(12.dp)) }
        }
    }
}

/** "Tue 20 Oct" over "07:42", and "88.35 kg" on the right, in Geist Mono. */
@Composable
private fun WeighInRow(model: AppModel, weighIn: WeighIn, onClick: () -> Unit) {
    val colors = Taken.colors
    val unit = model.weight.unit
    val locale = weightLocale()
    val day = model.clock.day(weighIn)
    val spoken = "${Fmt.longDay(day)} at ${model.spoken(weighIn.weighedAt)}, ${WeightFormat.spoken(weighIn.kg, unit, locale)}"
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 60.dp)
            .background(colors.bgRaised)
            .clickable(role = Role.Button, onClickLabel = "change it", onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = spoken }
            .padding(horizontal = 16.dp, vertical = 6.dp)
            .testTag("weigh-in-row"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).clearAndSetSemantics { }) {
            Text(WeightCopy.listDay(day, model.today.day), style = TakenType.sans(17), color = colors.fg)
            Spacer(Modifier.height(3.dp))
            Text(Fmt.clock(weighIn.weighedAt, model.clock), style = TakenType.mono(14), color = colors.fgSubtle)
        }
        Spacer(Modifier.width(8.dp))
        Row(Modifier.clearAndSetSemantics { }, verticalAlignment = Alignment.Bottom) {
            Text(WeightFormat.value(weighIn.kg, unit, locale), style = TakenType.mono(17), color = colors.fg, modifier = Modifier.alignByBaseline())
            Spacer(Modifier.width(4.dp))
            Text(unit.symbol, style = TakenType.sans(14), color = colors.fgMuted, modifier = Modifier.alignByBaseline())
        }
        Spacer(Modifier.width(8.dp))
        Icon(Symbols.ChevronRight, contentDescription = null, tint = colors.fgFaint, modifier = Modifier.size(18.dp))
    }
}

/** Swipe to the start to delete, red only while a swipe is under way, with TalkBack's "Delete" for the same thing. */
@Composable
private fun SwipeToDeleteWeighIn(onDelete: () -> Unit, content: @Composable () -> Unit) {
    val colors = Taken.colors
    val state = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        onDismiss = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) onDelete()
            scope.launch { state.reset() }
        },
        backgroundContent = {
            val swiping = state.dismissDirection == SwipeToDismissBoxValue.EndToStart
            Box(
                Modifier.fillMaxWidth().heightIn(min = 60.dp).background(if (swiping) colors.danger else Color.Transparent).padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                if (swiping) Text(WeightCopy.DELETE, style = TakenType.sans(16, FontWeight.SemiBold), color = colors.bg)
            }
        },
        modifier = Modifier.semantics { customActions = listOf(CustomAccessibilityAction(WeightCopy.DELETE) { onDelete(); true }) },
    ) { content() }
}

/**
 * One weigh-in: its weight, day and time, or Delete weigh-in. Save is on once something changed, the weight reads in this
 * locale within the bounds, and the moment is not still to come.
 */
@Composable
private fun WeighInEditor(model: AppModel, weighIn: WeighIn) {
    val colors = Taken.colors
    val weight = model.weight
    val unit = weight.unit
    val locale = weightLocale()
    val zone = model.clock.zone
    BackHandler { weight.editing = null }
    // What is typed and picked survives a configuration change (rotation, fold, dark mode, font size), as the editor
    // itself does (`WeightModel.editing` lives in the view model's AppModel): the To-do and item sheets keep theirs the
    // same way (https://developer.android.com/develop/ui/compose/state-saving).
    var text by rememberSaveable(weighIn.id) { mutableStateOf(WeightFormat.value(weighIn.kg, unit, locale)) }
    val start = remember { LocalDateTime.ofInstant(weighIn.weighedAt, zone) }
    var date by rememberSaveable(weighIn.id, stateSaver = DateSaver) { mutableStateOf(start.toLocalDate()) }
    var time by rememberSaveable(weighIn.id, stateSaver = TimeSaver) { mutableStateOf(start.toLocalTime().withSecond(0).withNano(0)) }
    var pickingDate by rememberSaveable(weighIn.id) { mutableStateOf(false) }
    var pickingTime by rememberSaveable(weighIn.id) { mutableStateOf(false) }
    val picked = date.atTime(time).atZone(zone).toInstant()
    val sameMinute = WeightImport.minute(picked) == WeightImport.minute(weighIn.weighedAt)
    val moment = if (sameMinute) weighIn.weighedAt else picked
    val kg = WeightFormat.kilograms(text, unit, locale)
    val weightChanged = kg != null && WeightFormat.value(kg, unit) != WeightFormat.value(weighIn.kg, unit)
    val future = !sameMinute && moment > model.now
    val canSave = kg != null && (weightChanged || !sameMinute) && !future

    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).testTag("weigh-in-editor")) {
        Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 8.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Button) { weight.editing = null }
                    .semantics { contentDescription = "Back" },
                contentAlignment = Alignment.Center,
            ) { Icon(Symbols.ArrowBack, contentDescription = null, tint = colors.fg) }
            Text(
                WeightCopy.EDIT_TITLE, style = TakenType.sans(17, FontWeight.SemiBold), color = colors.fg,
                modifier = Modifier.weight(1f).padding(start = 4.dp).semantics { heading() },
            )
            Box(
                Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(Taken.shapes.cell))
                    .clickable(enabled = canSave, role = Role.Button) {
                        if (kg == null) return@clickable
                        // A weight left as it was keeps its exact value (a pound figure round-trips through kilograms).
                        val kept = if (weightChanged) kg else weighIn.kg
                        weight.editing = null
                        model.updateWeighIn(weighIn.id, kept, moment)
                    }
                    .padding(horizontal = 12.dp)
                    .testTag("weigh-in-save"),
                contentAlignment = Alignment.Center,
            ) {
                Text(WeightCopy.SAVE, style = TakenType.sans(17, FontWeight.SemiBold), color = if (canSave) colors.signalInk else colors.fgFaint)
            }
        }
        Column(Modifier.padding(horizontal = 20.dp)) {
            EditorSection(WeightCopy.WEIGHT_FIELD)
            Card {
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) {
                        if (text.isEmpty()) Text(WeightFormat.value(0.0, unit, locale), style = TakenType.mono(22), color = colors.fgFaint)
                        BasicTextField(
                            value = text,
                            onValueChange = { text = WeightFormat.sanitize(it, locale) },
                            singleLine = true,
                            textStyle = TakenType.mono(22).copy(color = colors.fg),
                            cursorBrush = SolidColor(colors.signal),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, autoCorrectEnabled = false),
                            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Weight in ${unit.spoken}" },
                        )
                    }
                    Text(unit.symbol, style = TakenType.sans(17), color = colors.fgMuted, modifier = Modifier.clearAndSetSemantics { })
                }
            }
            EditorSection(WeightCopy.WHEN)
            Card {
                Column {
                    EditorValueRow(
                        title = "Day", value = Fmt.longDay(DayKey(date.year, date.monthValue, date.dayOfMonth)) + yearSuffix(date, model.today.day),
                        mono = false,
                    ) { pickingDate = true }
                    RowDivider()
                    EditorValueRow(title = "Time", value = String.format(Locale.ROOT, "%02d:%02d", time.hour, time.minute), mono = true) { pickingTime = true }
                }
            }
            if (future) {
                Text("That time is still to come. Pick an earlier one.", style = TakenType.sans(14), color = colors.fg, modifier = Modifier.padding(top = 8.dp, start = 16.dp))
            }
            Spacer(Modifier.height(24.dp))
            Card {
                Box(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button) { model.deleteWeighIn(weighIn.id) }
                        .padding(horizontal = 16.dp),
                    contentAlignment = Alignment.CenterStart,
                ) { Text(WeightCopy.DELETE_WEIGH_IN, style = TakenType.sans(17), color = colors.danger) }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
    if (pickingDate) {
        val nowDate = model.now.atZone(zone).toLocalDate()
        val latest = if (date.isAfter(nowDate)) date else nowDate
        DayDialog(
            title = WeightCopy.WHEN,
            initial = DayKey(date.year, date.monthValue, date.dayOfMonth),
            first = null,
            last = DayKey(latest.year, latest.monthValue, latest.dayOfMonth),
            onDismiss = { pickingDate = false },
        ) { picked ->
            pickingDate = false
            val (y, m, d) = picked.ymd
            date = LocalDate.of(y, m, d)
        }
    }
    if (pickingTime) {
        TimeDialog(title = WeightCopy.WHEN, minutes = time.hour * 60 + time.minute, onDismiss = { pickingTime = false }) { minutes ->
            pickingTime = false
            time = LocalTime.of(minutes / 60, minutes % 60)
        }
    }
}

private fun yearSuffix(date: LocalDate, today: DayKey): String = if (date.year != today.ymd.year) " ${date.year}" else ""

@Composable
private fun EditorSection(title: String) {
    Text(
        title, style = TakenType.sans(14, FontWeight.SemiBold), color = Taken.colors.fgSubtle,
        modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 8.dp).semantics { heading() },
    )
}

@Composable
private fun EditorValueRow(title: String, value: String, mono: Boolean, onClick: () -> Unit) {
    val colors = Taken.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button, onClickLabel = "change") { onClick() }
            .semantics(mergeDescendants = true) { contentDescription = "$title, $value" }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = TakenType.sans(17), color = colors.fg, modifier = Modifier.weight(1f))
        Text(value, style = if (mono) TakenType.mono(16) else TakenType.sans(16), color = colors.fg)
        Spacer(Modifier.width(6.dp))
        Icon(Symbols.UnfoldMore, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(16.dp))
    }
}

/**
 * Material 3's date picker in a dialog (SPEC-ANDROID 6.3), in the look's colours, limited to the days that may be picked:
 * never a day still to come for a weigh-in, and only the weigh-in days' span for a goal's start. Days are UTC midnights
 * to the picker, as its state counts them.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DayDialog(title: String, initial: DayKey, first: DayKey?, last: DayKey, onDismiss: () -> Unit, onPick: (DayKey) -> Unit) {
    val colors = Taken.colors
    val dayMillis = 86_400_000L
    val state = rememberDatePickerState(
        initialSelectedDateMillis = initial.ordinal * dayMillis,
        yearRange = ((first?.ymd?.year ?: 1970))..last.ymd.year,
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                val day = DayKey(Math.floorDiv(utcTimeMillis, dayMillis).toInt())
                return day <= last && (first == null || day >= first)
            }
        },
    )
    val pickerColors = DatePickerDefaults.colors(
        containerColor = colors.bgRaised,
        titleContentColor = colors.fgMuted,
        headlineContentColor = colors.fg,
        weekdayContentColor = colors.fgSubtle,
        navigationContentColor = colors.fg,
        dayContentColor = colors.fg,
        disabledDayContentColor = colors.fgFaint,
        selectedDayContentColor = colors.onSignal,
        selectedDayContainerColor = colors.signal,
        todayContentColor = colors.signalInk,
        todayDateBorderColor = colors.signalEdge,
        dividerColor = colors.line,
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                val millis = state.selectedDateMillis
                if (millis != null) onPick(DayKey(Math.floorDiv(millis, dayMillis).toInt())) else onDismiss()
            }) { Text("Set", style = TakenType.sans(16, FontWeight.SemiBold), color = colors.signalInk) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel", style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted) }
        },
        shape = RoundedCornerShape(Taken.shapes.card),
        tonalElevation = 0.dp,
        colors = pickerColors,
    ) {
        DatePicker(
            state = state,
            colors = pickerColors,
            title = { Text(title, style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted, modifier = Modifier.padding(start = 24.dp, top = 16.dp)) },
            showModeToggle = false,
        )
    }
}

// MARK: - The goal

/**
 * Set goal or Change goal, from the Weight tab's More options menu and nowhere else (REDESIGN.md, "Goal and moments"),
 * ported from Taken/Weight/WeightGoalSheet.swift: the goal in a field like the big number's, the start (the first
 * weigh-in day unless the trend has already been at the goal, movable here), the height (asked only here, to keep goals at
 * or above BMI 18.5), two footnotes and Save. No target date, rate, plan, forecast or start-weight field. A goal below the
 * floor shows one line in the look's muted ink, never red, and no number. Logging a weigh-in does not change at all.
 */
@Composable
fun WeightGoalSheet(model: AppModel, onDismiss: () -> Unit) {
    val colors = Taken.colors
    val weight = model.weight
    val unit = weight.unit
    val locale = weightLocale()
    val trend = WeightTrend.trend(weight.state.weighIns, model.clock)
    val existing = weight.goal
    // The typed goal, the picked start and the height survive a configuration change, as the sheet does (`model.sheet`).
    var text by rememberSaveable { mutableStateOf(weight.demoTypedGoal ?: existing?.let { WeightGoalCopy.goal(it.kg, unit, locale) } ?: "") }
    // The start the person picked in the Start row; until then the start follows the rules as the goal is typed.
    var pickedDay by rememberSaveable(stateSaver = OptionalDaySaver) { mutableStateOf(if (existing?.startPicked == true) existing.startDay else null) }
    var startPicked by rememberSaveable { mutableStateOf(existing?.startPicked == true) }
    // The height in this sheet: the stored one, or what the picker set. Kept only on Save.
    var heightCm by rememberSaveable { mutableStateOf(weight.state.heightCm) }
    var editingHeight by rememberSaveable { mutableStateOf(false) }
    var pickingStart by rememberSaveable { mutableStateOf(false) }
    var focused by remember { mutableStateOf(false) }
    val requester = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        // Focus once the sheet is up, as the iPhone's sheet does after one hop.
        delay(80)
        runCatching { requester.requestFocus() }
    }

    val goalKg = WeightFormat.kilograms(text, unit, locale)?.let { kg ->
        // A value left as the stored goal shows keeps its exact value.
        if (existing != null && WeightGoalCopy.goal(kg, unit, locale) == WeightGoalCopy.goal(existing.kg, unit, locale)) existing.kg else kg
    }
    val start = startPoint(existing, goalKg, pickedDay, trend)
    val blocked = goalKg != null && start != null && WeightGoals.floorBlocks(goalKg, start.kg, heightCm ?: 0.0)
    val canSave = goalKg != null && heightCm != null && start != null && !blocked
    val heightUnit = HeightUnit.preferred(locale)

    TakenSheet(onDismiss = onDismiss) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().imePadding()
                .padding(bottom = 16.dp).testTag("weight-goal-sheet"),
        ) {
            SheetHeader(title = WeightGoalCopy.TITLE, onClose = onDismiss)
            // The goal's field: Geist Mono 44 in a raised box whose border lights while focused, one decimal at most.
            val shape = RoundedCornerShape(Taken.shapes.card)
            Row(
                Modifier.padding(horizontal = 20.dp).padding(top = 4.dp).fillMaxWidth().background(colors.bgRaised, shape)
                    .border(1.dp, if (focused) colors.signalEdge else colors.line, shape)
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Box(Modifier.weight(1f).alignByBaseline()) {
                    if (text.isEmpty()) {
                        Text(trend.lastOrNull()?.let { WeightFormat.trend(it.kg, unit, locale) } ?: "", style = TakenType.mono(44), color = colors.fgFaint)
                    }
                    BasicTextField(
                        value = text,
                        onValueChange = { text = WeightFormat.sanitize(it, locale, maxDecimals = 1) },
                        singleLine = true,
                        textStyle = TakenType.mono(44).copy(color = colors.fg),
                        cursorBrush = SolidColor(colors.signal),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, autoCorrectEnabled = false),
                        modifier = Modifier.fillMaxWidth().focusRequester(requester).onFocusChanged { focused = it.isFocused }
                            .semantics { contentDescription = "Goal in ${unit.spoken}" }.testTag("goal-field"),
                    )
                }
                Spacer(Modifier.width(10.dp))
                Text(unit.symbol, style = TakenType.sans(22, FontWeight.Medium), color = colors.fgMuted, modifier = Modifier.alignByBaseline().clearAndSetSemantics { })
            }
            Spacer(Modifier.height(12.dp))
            Box(Modifier.padding(horizontal = 20.dp)) {
                Card {
                    Column {
                        // "Start", the trend that day, and the day, limited to the weigh-ins' span.
                        Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(WeightGoalCopy.START, style = TakenType.sans(15), color = colors.fgMuted)
                            Spacer(Modifier.width(10.dp))
                            if (start != null) Text(WeightFormat.withUnit(start.kg, unit, locale), style = TakenType.mono(15), color = colors.fg)
                            Spacer(Modifier.weight(1f))
                            if (start != null && trend.isNotEmpty()) {
                                val shown = WeightGoalCopy.shortDay(start.day, model.today.day)
                                Box(
                                    Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(Taken.shapes.cell))
                                        .clickable(role = Role.Button, onClickLabel = "change") { pickingStart = true }
                                        .semantics { contentDescription = "${WeightGoalCopy.START}, ${WeightGoalCopy.spokenDay(start.day)}" },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        shown, style = TakenType.sans(15), color = colors.signalInk,
                                        modifier = Modifier.background(colors.bgInset, RoundedCornerShape(Taken.shapes.cell)).padding(horizontal = 10.dp, vertical = 6.dp),
                                    )
                                }
                            }
                        }
                        RowDivider()
                        // "Height" and Set, or the height once it is chosen.
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 52.dp)
                                .clickable(role = Role.Button, onClickLabel = "choose") { editingHeight = true }
                                .semantics(mergeDescendants = true) {
                                    contentDescription = "${WeightGoalCopy.HEIGHT}, ${heightCm?.let { heightUnit.spoken(it) } ?: "not set"}"
                                }
                                .padding(horizontal = 16.dp)
                                .testTag("goal-height"),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(WeightGoalCopy.HEIGHT, style = TakenType.sans(15), color = colors.fgMuted, modifier = Modifier.weight(1f))
                            val height = heightCm
                            if (height != null) {
                                Text(heightUnit.text(height), style = TakenType.mono(15), color = colors.fg)
                                Spacer(Modifier.width(8.dp))
                                Icon(Symbols.UnfoldMore, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(16.dp))
                            } else {
                                Text(WeightGoalCopy.SET_BUTTON, style = TakenType.sans(15, FontWeight.SemiBold), color = colors.signalInk)
                            }
                        }
                    }
                }
            }
            Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(WeightGoalCopy.FOOTNOTE, style = TakenType.sans(13), color = colors.fgSubtle)
                Text(WeightGoalCopy.HEIGHT_FOOTNOTE, style = TakenType.sans(13), color = colors.fgSubtle)
            }
            if (blocked) {
                Text(
                    WeightGoalCopy.TOO_LOW, style = TakenType.sans(15), color = colors.fgMuted,
                    modifier = Modifier.padding(horizontal = 20.dp).padding(top = 14.dp).testTag("goal-too-low"),
                )
            }
            Spacer(Modifier.height(16.dp))
            PrimaryButton(WeightGoalCopy.SAVE, enabled = canSave, modifier = Modifier.padding(horizontal = 20.dp).testTag("goal-save")) {
                if (goalKg == null || start == null) return@PrimaryButton
                model.saveWeightGoal(goalKg, start.day, startPicked, heightCm, locale)
                onDismiss()
            }
        }
    }
    if (pickingStart && start != null && trend.isNotEmpty()) {
        DayDialog(
            title = WeightGoalCopy.START,
            initial = start.day,
            first = trend.first().day,
            last = trend.last().day,
            onDismiss = { pickingStart = false },
        ) { day ->
            pickingStart = false
            pickedDay = day
            startPicked = true
        }
    }
    if (editingHeight) {
        HeightDialog(heightUnit, heightCm, onDismiss = { editingHeight = false }) { picked ->
            editingHeight = false
            heightCm = picked
        }
    }
}

/** The start (`WeightGoals.sheetStartDay`), clamped to the weigh-ins, and the trend that day. */
private fun startPoint(existing: WeightGoal?, goalKg: Double?, pickedDay: DayKey?, trend: List<WeightPoint>): WeightPoint? {
    val last = trend.lastOrNull() ?: return null
    val day = WeightGoals.sheetStartDay(existing, goalKg, pickedDay, trend) ?: return null
    return WeightGoals.start(WeightGoal(goalKg ?: last.kg, day), trend)
}

/**
 * The height, picked from a list in a dialog [Own choice: Android has no wheel in Compose; Material's simple dialog with
 * a list of single choices stands in for the iPhone's wheel, https://m3.material.io/components/dialogs/guidelines]:
 * centimetres (100 to 230), or feet (3 to 7) and inches (0 to 11) side by side. It starts at the stored height, else
 * 170 cm or 5 ft 7 in, and nothing is kept until "Set 183 cm".
 */
@Composable
private fun HeightDialog(unit: HeightUnit, centimetres: Double?, onDismiss: () -> Unit, onSet: (Double) -> Unit) {
    val colors = Taken.colors
    val startCm = (centimetres ?: HeightUnit.DEFAULT_CENTIMETRES).let { Math.round(it).toInt() }
        .coerceIn(HeightUnit.CENTIMETRE_RANGE.first, HeightUnit.CENTIMETRE_RANGE.last)
    val imperial = centimetres?.let { HeightUnit.feetInches(it) } ?: HeightUnit.DEFAULT_FEET_INCHES
    var cm by remember { mutableStateOf(startCm) }
    var feet by remember { mutableStateOf(imperial.first.coerceIn(HeightUnit.FEET_RANGE.first, HeightUnit.FEET_RANGE.last)) }
    var inches by remember { mutableStateOf(imperial.second.coerceIn(0, 11)) }
    val picked = when (unit) {
        HeightUnit.CENTIMETRES -> cm.toDouble()
        HeightUnit.FEET_INCHES -> HeightUnit.centimetres(feet, inches)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.bgRaised,
        titleContentColor = colors.fg,
        textContentColor = colors.fg,
        shape = RoundedCornerShape(Taken.shapes.card),
        tonalElevation = 0.dp,
        title = { Text(WeightGoalCopy.HEIGHT, style = TakenType.sans(20, FontWeight.SemiBold)) },
        text = {
            Row(Modifier.fillMaxWidth().height(260.dp).testTag("height-picker"), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when (unit) {
                    HeightUnit.CENTIMETRES -> ChoiceList(HeightUnit.CENTIMETRE_RANGE.toList(), cm, { "$it cm" }, Modifier.weight(1f)) { cm = it }
                    HeightUnit.FEET_INCHES -> {
                        ChoiceList(HeightUnit.FEET_RANGE.toList(), feet, { "$it ft" }, Modifier.weight(1f)) { feet = it }
                        ChoiceList(HeightUnit.INCH_RANGE.toList(), inches, { "$it in" }, Modifier.weight(1f)) { inches = it }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSet(picked) }, modifier = Modifier.testTag("height-set")) {
                Text(WeightGoalCopy.setHeight(picked, unit), style = TakenType.sans(16, FontWeight.SemiBold), color = colors.signalInk)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel", style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted) }
        },
    )
}

/** One column of single choices, the chosen one lit and scrolled into view; TalkBack reads each as a radio button. */
@Composable
private fun ChoiceList(values: List<Int>, selected: Int, label: (Int) -> String, modifier: Modifier, onSelect: (Int) -> Unit) {
    val colors = Taken.colors
    val state = rememberLazyListState(initialFirstVisibleItemIndex = (values.indexOf(selected) - 2).coerceAtLeast(0))
    LazyColumn(modifier.border(1.dp, colors.line, RoundedCornerShape(Taken.shapes.cell)), state = state) {
        itemsIndexed(values) { _, value ->
            val chosen = value == selected
            Box(
                Modifier.fillMaxWidth().heightIn(min = 48.dp)
                    .background(if (chosen) colors.signalWash else Color.Transparent)
                    .selectable(selected = chosen, role = Role.RadioButton) { onSelect(value) },
                contentAlignment = Alignment.Center,
            ) {
                Text(label(value), style = TakenType.mono(16), color = if (chosen) colors.signalInk else colors.fg)
            }
        }
    }
}

/** A picked day as its epoch day, so a sheet's draft survives a configuration change. */
private val DateSaver = Saver<LocalDate, Long>(save = { it.toEpochDay() }, restore = { LocalDate.ofEpochDay(it) })

/** A picked time as its second of the day. */
private val TimeSaver = Saver<LocalTime, Int>(save = { it.toSecondOfDay() }, restore = { LocalTime.ofSecondOfDay(it.toLong()) })

/** The goal sheet's picked start, or none yet (nothing saved, so it starts as none again). */
private val OptionalDaySaver = Saver<DayKey?, Int>(save = { it?.ordinal }, restore = { DayKey(it) })
