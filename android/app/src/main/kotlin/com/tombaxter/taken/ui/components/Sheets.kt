package com.tombaxter.taken.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimeInput
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.TimePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/**
 * A sheet as Taken draws it: Material 3's `ModalBottomSheet` (which handles back and predictive back), on the look's
 * canvas with the look's corners and no stock colour. Full height for Add, the item and the day; `skipPartiallyExpanded`
 * so it opens where it will stay.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TakenSheet(
    onDismiss: () -> Unit,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = Taken.colors
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = Taken.shapes.card + 8.dp, topEnd = Taken.shapes.card + 8.dp),
        containerColor = colors.bg,
        contentColor = colors.fg,
        scrimColor = BottomSheetDefaults.ScrimColor,
        dragHandle = { BottomSheetDefaults.DragHandle(color = colors.lineStrong) },
        content = content,
    )
}

/** A Material 3 switch in the look's colours: the lit signal when on. */
@Composable
fun TakenSwitch(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, modifier: Modifier = Modifier) {
    val colors = Taken.colors
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange,
        modifier = modifier,
        colors = SwitchDefaults.colors(
            checkedThumbColor = colors.onSignal,
            checkedTrackColor = colors.signal,
            checkedBorderColor = colors.signal,
            uncheckedThumbColor = colors.fgSubtle,
            uncheckedTrackColor = colors.bgInset,
            uncheckedBorderColor = colors.lineStrong,
        ),
    )
}

/** Material 3's time input in 24-hour form, in the look's colours (SPEC-ANDROID 6.3: the iPhone's 24-hour wheel). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TakenTimeInput(state: TimePickerState, modifier: Modifier = Modifier) {
    val colors = Taken.colors
    TimeInput(
        state = state,
        modifier = modifier,
        colors = TimePickerDefaults.colors(
            clockDialColor = colors.bgInset,
            selectorColor = colors.signal,
            containerColor = colors.bg,
            periodSelectorBorderColor = colors.lineStrong,
            clockDialSelectedContentColor = colors.onSignal,
            clockDialUnselectedContentColor = colors.fg,
            periodSelectorSelectedContainerColor = colors.signalWash,
            periodSelectorUnselectedContainerColor = colors.bg,
            periodSelectorSelectedContentColor = colors.signalInk,
            periodSelectorUnselectedContentColor = colors.fgMuted,
            timeSelectorSelectedContainerColor = colors.signalWash,
            timeSelectorUnselectedContainerColor = colors.bgInset,
            timeSelectorSelectedContentColor = colors.signalInk,
            timeSelectorUnselectedContentColor = colors.fg,
        ),
    )
}

/**
 * A time setting in Geist Mono with up and down chevrons (the iPhone's MonoTimeButton). A tap opens a dialog with a
 * 24-hour time input and "Set 20:00". TalkBack: "Wake-up time, 07:00", "Double tap to change".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MonoTimeButton(title: String, minutes: Int, onSet: (Int) -> Unit) {
    val colors = Taken.colors
    var editing by remember { mutableStateOf(false) }
    Row(
        Modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(Taken.shapes.cell))
            .clickable(role = Role.Button, onClickLabel = "change") { editing = true }
            .semantics(mergeDescendants = true) { contentDescription = "$title, ${Fmt.minutes(minutes)}" }
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(Fmt.minutes(minutes), style = TakenType.mono(16), color = colors.fg)
        Spacer(Modifier.width(6.dp))
        Icon(Symbols.UnfoldMore, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(16.dp))
    }
    if (editing) {
        TimeDialog(title = title, minutes = minutes, onDismiss = { editing = false }) { picked ->
            onSet(picked)
            editing = false
        }
    }
}

/** One time of day in a dialog: the title, a 24-hour input, and "Set 20:00". */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeDialog(title: String, minutes: Int, onDismiss: () -> Unit, onSet: (Int) -> Unit) {
    val colors = Taken.colors
    val state = rememberTimePickerState(initialHour = minutes / 60, initialMinute = minutes % 60, is24Hour = true)
    val picked = state.hour * 60 + state.minute
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.bgRaised,
        titleContentColor = colors.fg,
        textContentColor = colors.fg,
        shape = RoundedCornerShape(Taken.shapes.card),
        title = { Text(title, style = TakenType.sans(20, FontWeight.SemiBold)) },
        text = {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                TakenTimeInput(state)
            }
        },
        confirmButton = {
            TextButton(onClick = { onSet(picked) }) {
                Text("Set ${Fmt.minutes(picked)}", style = TakenType.sans(16, FontWeight.SemiBold), color = colors.signalInk)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted)
            }
        },
    )
}

/** A confirm dialog in the look: "Delete Vitamin D3?", its message, a destructive button and Cancel. */
@Composable
fun ConfirmDialog(
    title: String,
    message: String?,
    confirm: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = Taken.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.bgRaised,
        titleContentColor = colors.fg,
        textContentColor = colors.fgMuted,
        shape = RoundedCornerShape(Taken.shapes.card),
        title = { Text(title, style = TakenType.sans(20, FontWeight.SemiBold)) },
        text = message?.let { { Text(it, style = TakenType.sans(15)) } },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirm, style = TakenType.sans(16, FontWeight.SemiBold), color = colors.danger)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", style = TakenType.sans(16, FontWeight.Medium), color = colors.fg)
            }
        },
    )
}

/** A toggle row: a title, an optional line under it, and Taken's switch; the whole row toggles (one TalkBack node). */
@Composable
fun SwitchRow(title: String, checked: Boolean, subtitle: String? = null, onChange: (Boolean) -> Unit) {
    val colors = Taken.colors
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = TakenType.sans(17), color = colors.fg)
            if (subtitle != null) Text(subtitle, style = TakenType.sans(14), color = colors.fgSubtle)
        }
        TakenSwitch(checked = checked, onCheckedChange = null)
    }
}

/** A live region TalkBack reads when its sentence changes: Android's announcement (SPEC-ANDROID 6.2). */
@Composable
fun Announcement(text: String?) {
    if (text == null) return
    Box(
        Modifier
            .size(1.dp)
            .semantics {
                contentDescription = text
                liveRegion = LiveRegionMode.Polite
            },
    )
}
