package com.tombaxter.taken.ui.item

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.core.catalog.FrequencyChoice
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.ConfirmDialog
import com.tombaxter.taken.ui.components.FrequencyMenu
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.SheetHeader
import com.tombaxter.taken.ui.components.SwitchRow
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.TakenSheet
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import java.util.UUID

/** What the item sheet is editing: the item's name, schedule and archive, saved when it closes. */
class ItemDraftState(item: Item, todayWeekday: Int) {
    var name by mutableStateOf(item.name)
    var choice by mutableStateOf(FrequencyChoice.of(item.frequency))
    var weekdays by mutableStateOf(
        (item.frequency as? Frequency.Weekdays)?.days?.takeIf { it.isNotEmpty() } ?: FrequencyChoice.defaultDays,
    )
    /** Weekly's one day (Calendar numbering): the item's own, else the day being lived. */
    var weekday by mutableStateOf(
        (item.frequency as? Frequency.Weekdays)?.days?.takeIf { it.size == 1 }?.first() ?: todayWeekday,
    )
    var archived by mutableStateOf(item.archived)
    var deleted = false

    val frequency: Frequency get() = choice.frequency(weekdays, weekday)

    /** The iPhone's save rule: an empty name keeps the old one; a new name takes its code; nothing when unchanged. */
    fun save(model: AppModel, id: UUID) {
        if (deleted) return
        model.saveItem(id, name, frequency, archived)
    }

    companion object {
        /**
         * What was typed and picked survives a rotation, a fold or a resize, which recreate the screen; the open sheet
         * itself lives in AppModel (https://developer.android.com/develop/ui/compose/state-saving).
         */
        fun saver(item: Item, todayWeekday: Int): Saver<ItemDraftState, Any> = listSaver<ItemDraftState, Any>(
            save = { draft -> listOf(draft.name, draft.choice.name, ArrayList(draft.weekdays.sorted()), draft.weekday, draft.archived) },
            restore = { saved ->
                ItemDraftState(item, todayWeekday).apply {
                    name = saved[0] as String
                    choice = FrequencyChoice.valueOf(saved[1] as String)
                    weekdays = (saved[2] as List<*>).map { it as Int }.toSet()
                    weekday = saved[3] as Int
                    archived = saved[4] as Boolean
                }
            },
        )
    }
}

/** The item sheet from Today (edit mode, or Edit item in a row's menu). It saves as it closes, by swipe, back or close. */
@Composable
fun ItemSheet(model: AppModel, itemId: UUID, onDismiss: () -> Unit) {
    val item = model.item(itemId)
    if (item == null) {
        LaunchedEffect(itemId) { onDismiss() }
        return
    }
    val weekday = model.today.day.weekday
    val draft = rememberSaveable(itemId, saver = ItemDraftState.saver(item, weekday)) { ItemDraftState(item, weekday) }
    val close = {
        draft.save(model, itemId)
        onDismiss()
    }
    TakenSheet(onDismiss = close) {
        Column(Modifier.fillMaxWidth().testTag("item-sheet")) {
            SheetHeader(title = draft.name.trim().ifEmpty { "Item" }, onClose = close)
            ItemEditorBody(model, itemId, draft, onDeleted = onDismiss)
        }
    }
}

/** The same editor pushed from Profile's Stack list, with Up and back; it saves as it leaves. */
@Composable
fun ItemEditorScreen(model: AppModel, itemId: UUID) {
    val colors = Taken.colors
    val item = model.item(itemId)
    if (item == null) {
        LaunchedEffect(itemId) { model.back() }
        return
    }
    val weekday = model.today.day.weekday
    val draft = rememberSaveable(itemId, saver = ItemDraftState.saver(item, weekday)) { ItemDraftState(item, weekday) }
    DisposableEffect(itemId) {
        onDispose { draft.save(model, itemId) }
    }
    Column(Modifier.fillMaxSize().background(colors.bg).windowInsetsPadding(WindowInsets.safeDrawing).testTag("item-screen")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Button) { model.back() }
                    .semantics { contentDescription = "Back" },
                contentAlignment = Alignment.Center,
            ) { Icon(Symbols.ArrowBack, contentDescription = null, tint = colors.fg) }
            Text(
                draft.name.trim().ifEmpty { "Item" },
                style = TakenType.sans(17, FontWeight.SemiBold),
                color = colors.fg,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 4.dp).semantics { heading() },
            )
        }
        ItemEditorBody(model, itemId, draft, onDeleted = { model.back() })
    }
}

@Composable
private fun ItemEditorBody(model: AppModel, itemId: UUID, draft: ItemDraftState, onDeleted: () -> Unit) {
    val colors = Taken.colors
    var confirmDelete by remember { mutableStateOf(false) }
    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 28.dp)
            .imePadding()
            .navigationBarsPadding(),
    ) {
        EditorTitle("Name")
        Card {
            Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
                if (draft.name.isEmpty()) Text("Name", style = TakenType.sans(17), color = colors.fgFaint)
                BasicTextField(
                    value = draft.name,
                    onValueChange = { draft.name = it },
                    singleLine = true,
                    textStyle = TakenType.sans(17).copy(color = colors.fg),
                    cursorBrush = SolidColor(colors.signal),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Words,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Done,
                    ),
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Name" }.testTag("item-name"),
                )
            }
        }
        EditorTitle("Schedule")
        Card {
            Column {
                Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(start = 16.dp, end = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("How often", style = TakenType.sans(17), color = colors.fg, modifier = Modifier.weight(1f))
                    FrequencyMenu(draft.choice, label = "How often") { draft.choice = it }
                }
                if (draft.choice == FrequencyChoice.DAYS) {
                    Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp)) {
                        com.tombaxter.taken.ui.components.WeekdayPicker(draft.weekdays) { draft.weekdays = it }
                    }
                } else if (draft.choice == FrequencyChoice.WEEKLY) {
                    Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp)) {
                        com.tombaxter.taken.ui.components.WeekdayPicker(setOf(draft.weekday), single = true) { picked ->
                            picked.firstOrNull()?.let { draft.weekday = it }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "A change applies from today. Earlier days keep the schedule they had.",
            style = TakenType.sans(14),
            color = colors.fgSubtle,
            modifier = Modifier.padding(start = EDITOR_INSET),
        )
        // Weekly: one fixed line, never a countdown. Taken only records doses.
        if (draft.choice == FrequencyChoice.WEEKLY) {
            Spacer(Modifier.height(6.dp))
            Text(Fmt.MISSED_DOSE_NOTE, style = TakenType.sans(14), color = colors.fgSubtle, modifier = Modifier.padding(start = EDITOR_INSET))
        }
        Spacer(Modifier.height(22.dp))
        Card {
            Column {
                SwitchRow("Archive", checked = draft.archived, subtitle = "Hidden from Today. History stays.") { draft.archived = it }
                RowDivider()
                Box(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button) { confirmDelete = true }
                        .padding(horizontal = 16.dp).testTag("delete-item"),
                    contentAlignment = Alignment.CenterStart,
                ) { Text("Delete item", style = TakenType.sans(17), color = colors.danger) }
            }
        }
    }
    if (confirmDelete) {
        val name = draft.name.trim()
        ConfirmDialog(
            title = if (name.isEmpty()) "Delete this item?" else "Delete $name?",
            message = "Its log entries leave your stats. To keep its history, archive it instead.",
            confirm = "Delete",
            onConfirm = {
                confirmDelete = false
                draft.deleted = true
                model.deleteItem(itemId)
                onDeleted()
            },
            onDismiss = { confirmDelete = false },
        )
    }
}

/** Labels and footnotes start where the fields' text starts, one edge down the sheet as on the iPhone. */
private val EDITOR_INSET = 16.dp

@Composable
private fun EditorTitle(title: String) {
    Text(
        title,
        style = TakenType.sans(14, FontWeight.SemiBold),
        color = Taken.colors.fgSubtle,
        modifier = Modifier.padding(top = 20.dp, bottom = 8.dp, start = EDITOR_INSET).semantics { heading() },
    )
}
