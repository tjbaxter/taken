package com.tombaxter.taken.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.Sheet
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.ui.components.AvatarImage
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.ConfirmDialog
import com.tombaxter.taken.ui.components.InkButton
import com.tombaxter.taken.ui.components.MonoTimeButton
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.SettingRow
import com.tombaxter.taken.ui.components.SwitchRow
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.rememberPhoto
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** Profile and About copy, Android wording where the iPhone names itself (SPEC-ANDROID 6.4 and 14.3). */
object ProfileCopy {
    const val ABOUT = "Everything stays on this phone. No accounts. No ads. No tracking."
    const val HEALTH =
        "Taken is a personal log. It is not a medical device and does not diagnose, treat, cure, or prevent any medical condition. Ask a healthcare professional for medical advice, diagnosis, or treatment."
    const val LOOK_FOOTNOTE = "The widgets follow it."
    const val LOOK_HINT = "Applies this look to Taken and its widgets."
    const val DAY_FOOTNOTE = "Doses count for the day you wake up into."
    const val SUPPORT_URL = "https://tjbaxter.github.io/taken/"

    /** "14-day streak · 97% over 30 days", or the line before the first dose. */
    fun streakLine(hasDoses: Boolean, streak: Int, percent: Int?): String {
        if (!hasDoses) return "Your streak starts with your first dose."
        val days = if (streak == 1) "1-day streak" else "$streak-day streak"
        return if (percent == null) days else "$days · $percent% over 30 days"
    }

    val all: List<String> get() = listOf(ABOUT, HEALTH, LOOK_FOOTNOTE, LOOK_HINT, DAY_FOOTNOTE, streakLine(false, 0, null))
}

/**
 * Profile (SPEC-ANDROID 6.3 and 7.1): a full screen with Up and back, changes saved as they are made. CORE's sections, in
 * the iPhone's order: the header (photo, name, streak), Stack, Look, Your day, Feel, Data, About. Reminder, Taken Pro and
 * Weight join with their phases.
 */
@Composable
fun ProfileScreen(model: AppModel, platform: Platform) {
    val colors = Taken.colors
    var name by remember { mutableStateOf(model.profile.name) }
    var confirmErase by remember { mutableStateOf(false) }
    DisposableEffect(Unit) { onDispose { model.setProfileName(name) } }

    Column(Modifier.fillMaxSize().background(colors.bg).windowInsetsPadding(WindowInsets.safeDrawing).testTag("profile")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Button) { model.back() }
                    .semantics { contentDescription = "Back" },
                contentAlignment = Alignment.Center,
            ) { Icon(Symbols.ArrowBack, contentDescription = null, tint = colors.fg) }
            Text("Profile", style = TakenType.sans(17, FontWeight.SemiBold), color = colors.fg, modifier = Modifier.padding(start = 4.dp).semantics { heading() })
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp).imePadding(),
        ) {
            Header(model, platform, name, onName = { name = it }, onSubmit = { model.setProfileName(name) })
            StackSection(model)
            Section("Look", trailing = model.theme.title)
            Card { Box(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) { LookPicker(model.theme) { model.setLook(it) } } }
            Footnote(ProfileCopy.LOOK_FOOTNOTE)
            Section("Your day")
            Card {
                SettingRow("Wake-up time") { MonoTimeButton("Wake-up time", model.settings.wakeMinutes) { model.setWakeMinutes(it) } }
            }
            Footnote(ProfileCopy.DAY_FOOTNOTE)
            Section("Feel")
            Card { SwitchRow("Haptics", checked = model.hapticsOn) { model.setHaptics(it) } }
            Section("Data")
            Card {
                Column {
                    LinkRow("Export CSV") { platform.shareCsv(model.csv()) }
                    RowDivider()
                    LinkRow("Erase all data", danger = true) { confirmErase = true }
                }
            }
            Section("About")
            Card {
                Column {
                    Text(ProfileCopy.ABOUT, style = TakenType.sans(16), color = colors.fg, modifier = Modifier.padding(16.dp))
                    RowDivider()
                    Text(ProfileCopy.HEALTH, style = TakenType.sans(15), color = colors.fgMuted, modifier = Modifier.padding(16.dp))
                    RowDivider()
                    SettingRow("Version") { Text(platform.versionName, style = TakenType.mono(15), color = colors.fgSubtle) }
                    RowDivider()
                    LinkRow("Support") { platform.openUrl(ProfileCopy.SUPPORT_URL) }
                }
            }
        }
    }

    if (confirmErase) {
        ConfirmDialog(
            title = "Erase all data?",
            message = com.tombaxter.taken.AppModel.ERASE_MESSAGE,
            confirm = "Erase all data",
            onConfirm = {
                confirmErase = false
                model.eraseAll()
                name = ""
            },
            onDismiss = { confirmErase = false },
        )
    }
}

@Composable
private fun Header(model: AppModel, platform: Platform, name: String, onName: (String) -> Unit, onSubmit: () -> Unit) {
    val colors = Taken.colors
    Column(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .size(96.dp)
                .clip(CircleShape)
                .clickable(role = Role.Button) { platform.pickPhoto() }
                .semantics { contentDescription = if (model.photo == null) "Add a profile photo" else "Change your profile photo" },
            contentAlignment = Alignment.Center,
        ) {
            AvatarImage(Profile(name).initials, rememberPhoto(model.photo), 92.dp)
            Box(
                Modifier.align(Alignment.BottomEnd).size(30.dp).background(colors.button, CircleShape).border(2.dp, colors.bg, CircleShape),
                contentAlignment = Alignment.Center,
            ) { Icon(Symbols.PhotoCameraFill, contentDescription = null, tint = colors.buttonText, modifier = Modifier.size(16.dp)) }
        }
        Spacer(Modifier.height(14.dp))
        Box(Modifier.widthIn(max = 320.dp).fillMaxWidth().heightIn(min = 48.dp), contentAlignment = Alignment.Center) {
            if (name.isEmpty()) Text("Your name", style = TakenType.sans(22, FontWeight.SemiBold), color = colors.fgFaint, textAlign = TextAlign.Center)
            BasicTextField(
                value = name,
                onValueChange = { onName(it.take(80)) },
                singleLine = true,
                textStyle = TakenType.sans(22, FontWeight.SemiBold).copy(color = colors.fg, textAlign = TextAlign.Center),
                cursorBrush = SolidColor(colors.signal),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { onSubmit() }),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Your name" },
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            ProfileCopy.streakLine(model.state.doses.isNotEmpty(), model.streak, model.adherence.percent),
            style = TakenType.sans(15),
            color = colors.fgSubtle,
            textAlign = TextAlign.Center,
        )
        if (model.photo != null) {
            InkButton("Remove photo") { model.removeProfilePhoto() }
        }
    }
}

/** Stack: active items (a tap opens the item, a swipe left deletes), Reorder, + Add to stack, then archived items. */
@Composable
private fun StackSection(model: AppModel) {
    val colors = Taken.colors
    var reordering by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<Item?>(null) }
    val active = model.activeItems
    val showsReorder = reordering && active.size > 1

    Row(Modifier.fillMaxWidth().padding(top = 22.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Stack", style = TakenType.sans(15, FontWeight.SemiBold), color = colors.fgMuted, modifier = Modifier.weight(1f).semantics { heading() })
        if (active.size > 1) InkButton(if (showsReorder) "Done" else "Reorder") { reordering = !showsReorder }
    }
    Card {
        Column {
            if (active.isEmpty()) {
                Text("Nothing in your stack yet", style = TakenType.sans(16), color = colors.fgSubtle, modifier = Modifier.padding(16.dp))
                RowDivider()
            }
            active.forEachIndexed { index, item ->
                if (index > 0) RowDivider()
                if (showsReorder) {
                    ReorderRow(model, item, index, active.size)
                } else {
                    SwipeToDelete(item, onDelete = { pendingDelete = item }) {
                        StackRow(item, archived = false) { model.openProfileItem(item.id) }
                    }
                }
            }
            if (active.isNotEmpty()) RowDivider()
            Row(
                Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button) { model.requirePro { model.sheet = Sheet.Add } }
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Symbols.Add, contentDescription = null, tint = colors.signalInk, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text("Add to stack", style = TakenType.sans(17, FontWeight.Medium), color = colors.signalInk)
            }
            for (item in model.archivedItems) {
                RowDivider()
                StackRow(item, archived = true) { model.openProfileItem(item.id) }
            }
        }
    }
    pendingDelete?.let { item ->
        ConfirmDialog(
            title = "Delete ${item.name}?",
            message = "Its log entries leave your stats. To keep its history, archive it instead.",
            confirm = "Delete ${item.name}",
            onConfirm = {
                model.deleteItem(item.id)
                pendingDelete = null
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun StackRow(item: Item, archived: Boolean, onClick: () -> Unit) {
    val colors = Taken.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 60.dp).background(colors.bgRaised).clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(item.name, style = TakenType.sans(17), color = if (archived) colors.fgMuted else colors.fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (archived) "Archived" else Fmt.frequency(item.frequency), style = TakenType.sans(14), color = colors.fgSubtle)
        }
        Icon(Symbols.ChevronRight, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(20.dp))
    }
}

/** Swipe left to delete (SwipeToDismissBox), with TalkBack's "Delete" action for the same thing. */
@Composable
private fun SwipeToDelete(item: Item, onDelete: () -> Unit, content: @Composable () -> Unit) {
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
            Box(Modifier.fillMaxSize().background(colors.danger).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Text("Delete", style = TakenType.sans(16, FontWeight.SemiBold), color = colors.bg)
            }
        },
        modifier = Modifier.semantics {
            customActions = listOf(CustomAccessibilityAction("Delete") { onDelete(); true })
        },
    ) { content() }
}

/** Reorder mode: a drag handle on each row, and TalkBack's Move up and Move down (SPEC-ANDROID 6.3). */
@Composable
private fun ReorderRow(model: AppModel, item: Item, index: Int, count: Int) {
    val colors = Taken.colors
    var offset by remember(item.id) { mutableFloatStateOf(0f) }
    var rowHeight by remember { mutableFloatStateOf(1f) }
    val moves = buildList {
        if (index > 0) add(CustomAccessibilityAction("Move up") { model.moveItems(setOf(index), index - 1); true })
        if (index < count - 1) add(CustomAccessibilityAction("Move down") { model.moveItems(setOf(index), index + 2); true })
    }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 60.dp)
            .onSizeChanged { rowHeight = it.height.toFloat().coerceAtLeast(1f) }
            .graphicsLayer { translationY = offset }
            .background(colors.bgRaised)
            .semantics(mergeDescendants = true) {
                contentDescription = "${item.name}, ${Fmt.frequency(item.frequency)}"
                customActions = moves
            }
            .padding(start = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(item.name, style = TakenType.sans(17), color = colors.fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(Fmt.frequency(item.frequency), style = TakenType.sans(14), color = colors.fgSubtle)
        }
        Box(
            Modifier
                .size(56.dp)
                .pointerInput(item.id, index) {
                    detectDragGestures(
                        onDragEnd = {
                            val steps = (offset / rowHeight).roundToInt()
                            val target = (index + steps).coerceIn(0, count - 1)
                            offset = 0f
                            if (target != index) model.moveItems(setOf(index), if (target > index) target + 1 else target)
                        },
                        onDragCancel = { offset = 0f },
                    ) { change, drag ->
                        change.consume()
                        offset += drag.y
                    }
                },
            contentAlignment = Alignment.Center,
        ) { Icon(Symbols.DragHandle, contentDescription = null, tint = colors.fgSubtle) }
    }
}

@Composable
private fun Section(title: String, trailing: String? = null) {
    val colors = Taken.colors
    Row(Modifier.fillMaxWidth().padding(top = 22.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = TakenType.sans(15, FontWeight.SemiBold), color = colors.fgMuted, modifier = Modifier.weight(1f).semantics { heading() })
        if (trailing != null) Text(trailing, style = TakenType.sans(14, FontWeight.Medium), color = colors.signalInk)
    }
}

@Composable
private fun Footnote(text: String) {
    Text(text, style = TakenType.sans(14), color = Taken.colors.fgSubtle, modifier = Modifier.padding(top = 8.dp, start = 4.dp))
}

@Composable
private fun LinkRow(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector? = null, danger: Boolean = false, onClick: () -> Unit) {
    val colors = Taken.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(title, style = TakenType.sans(17), color = if (danger) colors.danger else colors.signalInk)
        if (icon != null) Icon(icon, contentDescription = null, tint = colors.fgSubtle)
    }
}
