package com.tombaxter.taken.ui.todo

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.core.todo.TodoCopy
import com.tombaxter.taken.core.todo.TodoEditRules
import com.tombaxter.taken.core.todo.TodoText
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.SwitchRow
import com.tombaxter.taken.ui.components.TakenSheet
import com.tombaxter.taken.ui.components.TimeDialog
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/**
 * Tap a task: change its words or when it is due, or delete it (the iPhone's TodoEditSheet). The words (one to four
 * lines); Due; while due, Time and When (a date, or a date and a 24-hour time); Delete to-do, at once, with the list's
 * undo bar; Cancel and Save (Save waits for words). The picker starts on the time said, the day said at 09:00, or
 * tomorrow at 09:00; what is saved is a time, or the calendar date picked (`TodoEditRules`). Kept across a rotation.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodoEditSheet(model: AppModel, taskId: UUID, onDismiss: () -> Unit) {
    val todo = model.todo
    val task = todo.state.task(taskId)
    if (task == null) {
        LaunchedEffect(taskId) { onDismiss() }
        return
    }
    val colors = Taken.colors
    val clock = todo.clock
    var title by rememberSaveable(taskId) { mutableStateOf(task.title) }
    var hasDue by rememberSaveable(taskId) { mutableStateOf(task.due != null) }
    var hasTime by rememberSaveable(taskId) { mutableStateOf(task.hasTime) }
    var picked by rememberSaveable(taskId) { mutableLongStateOf(TodoEditRules.pickerDate(task.due, clock, todo.now).toEpochMilli()) }
    var pickingDate by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf(false) }
    val moment = Instant.ofEpochMilli(picked).atZone(clock.zone)
    val canSave = TodoText.clean(title) != null

    TakenSheet(onDismiss = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .navigationBarsPadding()
                .padding(bottom = 20.dp)
                .testTag("todo-edit-sheet"),
        ) {
            SheetBar(TodoCopy.EDIT_TITLE, TodoCopy.SAVE, enabled = canSave, onCancel = onDismiss) {
                todo.edit(taskId, title, TodoEditRules.savedDue(hasDue, hasTime, Instant.ofEpochMilli(picked), clock))
                onDismiss()
            }
            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Card {
                    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp, vertical = 14.dp)) {
                        if (title.isEmpty()) Text(TodoCopy.FIELD, style = TakenType.sans(17), color = colors.fgFaint)
                        BasicTextField(
                            value = title,
                            onValueChange = { title = it },
                            minLines = 1,
                            maxLines = 4,
                            textStyle = TakenType.sans(17).copy(color = colors.fg),
                            cursorBrush = SolidColor(colors.signal),
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                            modifier = Modifier.fillMaxWidth().semantics { contentDescription = TodoCopy.FIELD }.testTag("todo-field"),
                        )
                    }
                }
                Card {
                    Column {
                        SwitchRow(TodoCopy.DUE, hasDue) { hasDue = it }
                        if (hasDue) {
                            RowDivider()
                            SwitchRow(TodoCopy.TIME, hasTime) { hasTime = it }
                            RowDivider()
                            val values = @Composable {
                                ValueButton(DATE_LABEL.format(moment), "${TodoCopy.WHEN}, ${DATE_LABEL.format(moment)}") { pickingDate = true }
                                if (hasTime) {
                                    Spacer(Modifier.width(6.dp))
                                    val time = TodoText.clockTime(moment.toInstant(), clock)
                                    ValueButton(time, "${TodoCopy.TIME}, $time", mono = true) { pickingTime = true }
                                }
                            }
                            if (LocalDensity.current.fontScale >= LARGE_TEXT) {
                                // At large text the date and time go under "When", so none of them is cut.
                                Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 10.dp, bottom = 6.dp)) {
                                    Text(TodoCopy.WHEN, style = TakenType.sans(17), color = colors.fg)
                                    Row(Modifier.padding(start = 0.dp), verticalAlignment = Alignment.CenterVertically) { values() }
                                }
                            } else {
                                Row(
                                    Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = 16.dp, end = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(TodoCopy.WHEN, style = TakenType.sans(17), color = colors.fg, modifier = Modifier.weight(1f))
                                    values()
                                }
                            }
                        }
                    }
                }
                Card {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 52.dp)
                            .clickable(role = Role.Button) {
                                todo.delete(task)
                                onDismiss()
                            }
                            .padding(horizontal = 16.dp)
                            .testTag("todo-delete"),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        Text(TodoCopy.DELETE, style = TakenType.sans(16, FontWeight.Medium), color = colors.danger)
                    }
                }
            }
        }
    }

    if (pickingDate) {
        val pickerColors = DatePickerDefaults.colors(
            containerColor = colors.bgRaised,
            selectedDayContainerColor = colors.signal,
            selectedDayContentColor = colors.onSignal,
            todayContentColor = colors.signalInk,
            todayDateBorderColor = colors.signalEdge,
        )
        // Material's date picker works in UTC midnights: the calendar date goes across as one.
        val state = rememberDatePickerState(
            initialSelectedDateMillis = moment.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            colors = pickerColors,
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        val date = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                        picked = TodoEditRules.moment(date, moment.hour, moment.minute, clock.zone).toEpochMilli()
                    }
                    pickingDate = false
                }) {
                    Text("Set", style = TakenType.sans(16, FontWeight.SemiBold), color = colors.signalInk)
                }
            },
            dismissButton = {
                TextButton(onClick = { pickingDate = false }) {
                    Text(TodoCopy.CANCEL, style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted)
                }
            },
        ) {
            DatePicker(state = state, colors = pickerColors)
        }
    }
    if (pickingTime) {
        TimeDialog(title = TodoCopy.TIME, minutes = moment.hour * 60 + moment.minute, onDismiss = { pickingTime = false }) { minutes ->
            val date: LocalDate = moment.toLocalDate()
            picked = TodoEditRules.moment(date, minutes / 60, minutes % 60, clock.zone).toEpochMilli()
            pickingTime = false
        }
    }
}

/**
 * Typing instead of talking (no microphone, no on-device speech, or by choice): the same save onto the one list, as
 * said, one line per sentence (the iPhone's TodoTypeSheet). The field is focused on open; Add waits for words.
 */
@Composable
fun TodoTypeSheet(model: AppModel, onDismiss: () -> Unit) {
    val colors = Taken.colors
    var text by rememberSaveable { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    TakenSheet(onDismiss = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .imePadding()
                .navigationBarsPadding()
                .padding(bottom = 20.dp)
                .testTag("todo-type-sheet"),
        ) {
            SheetBar(TodoCopy.TYPE_TITLE, TodoCopy.ADD, enabled = text.isNotBlank(), onCancel = onDismiss) {
                model.todo.submitTyped(text)
                onDismiss()
            }
            val shape = RoundedCornerShape(Taken.shapes.card)
            Box(
                Modifier
                    .padding(horizontal = 20.dp)
                    .fillMaxWidth()
                    .heightIn(min = 140.dp)
                    .clip(shape)
                    .background(colors.bgRaised, shape)
                    .border(1.dp, colors.line, shape)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
            ) {
                if (text.isEmpty()) Text(TodoCopy.TYPE_PLACEHOLDER, style = TakenType.sans(17), color = colors.fgFaint)
                BasicTextField(
                    value = text,
                    onValueChange = { text = it },
                    textStyle = TakenType.sans(17).copy(color = colors.fg),
                    cursorBrush = SolidColor(colors.signal),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 116.dp)
                        .focusRequester(focus)
                        .semantics { contentDescription = TodoCopy.TYPE_TITLE }
                        .testTag("todo-type-field"),
                )
            }
            Spacer(Modifier.height(4.dp))
        }
    }
}

/** Cancel, the title, and the confirming action (Save, Add): the iPhone's sheet bar, Material's dismiss-then-confirm order. */
@Composable
private fun SheetBar(title: String, confirm: String, enabled: Boolean, onCancel: () -> Unit, onConfirm: () -> Unit) {
    val colors = Taken.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = onCancel, modifier = Modifier.heightIn(min = 48.dp).testTag("sheet-cancel")) {
            Text(TodoCopy.CANCEL, style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted)
        }
        Text(
            title,
            style = TakenType.sans(17, FontWeight.SemiBold),
            color = colors.fg,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        TextButton(onClick = onConfirm, enabled = enabled, modifier = Modifier.heightIn(min = 48.dp).testTag("sheet-confirm")) {
            Text(confirm, style = TakenType.sans(16, FontWeight.SemiBold), color = if (enabled) colors.signalInk else colors.fgFaint)
        }
    }
}

/** A value that opens its picker: "Thu 22 Oct 2026", "09:00" (Geist Mono). */
@Composable
private fun ValueButton(label: String, spoken: String, mono: Boolean = false, onClick: () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.cell)
    Box(
        Modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .clickable(role = Role.Button, onClickLabel = "change", onClick = onClick)
            .semantics { contentDescription = spoken }
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.background(colors.bgInset, shape).padding(horizontal = 10.dp, vertical = 6.dp)) {
            Text(label, style = if (mono) TakenType.mono(15) else TakenType.sans(15), color = colors.fg, maxLines = 1)
        }
    }
}

/** The edit sheet's dates in the iPhone's en_GB form: "Thu 22 Oct 2026". */
private val DATE_LABEL: DateTimeFormatter = DateTimeFormatter.ofPattern("EEE d MMM yyyy", Locale.UK)
