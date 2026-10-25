package com.tombaxter.taken.ui.add

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.Effect
import com.tombaxter.taken.Haptic
import com.tombaxter.taken.core.catalog.AddCopy
import com.tombaxter.taken.core.catalog.AddPlan
import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.catalog.FrequencyChoice
import com.tombaxter.taken.core.catalog.Suggest
import com.tombaxter.taken.core.catalog.SuggestRow
import com.tombaxter.taken.core.catalog.Suggestion
import com.tombaxter.taken.ui.components.Announcement
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.FrequencyMenu
import com.tombaxter.taken.ui.components.PrimaryButton
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.SectionHeader
import com.tombaxter.taken.ui.components.SheetHeader
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.TakenSheet
import com.tombaxter.taken.ui.components.WeekdayPicker
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import kotlinx.coroutines.delay

/**
 * Add (SPEC 3.4, SPEC-ANDROID 7.1): tap chips, set how often each is taken, add. + CUSTOM opens type mode: the field
 * pinned under the header with suggestions under it (sized to the room, never a scroll), and the Add bar out of the way
 * while the keyboard is up.
 */
@Composable
fun AddSheet(model: AppModel, onDismiss: () -> Unit) {
    TakenSheet(onDismiss = onDismiss) {
        AddContent(model, onDismiss)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AddContent(model: AppModel, onClose: () -> Unit) {
    val colors = Taken.colors
    val seed = model.addSeed
    val selected = remember { mutableStateListOf<String>().also { it.addAll(seed?.selected ?: emptyList()) } }
    val extras = remember { mutableStateListOf<String>() }
    val choices = remember { mutableStateMapOf<String, FrequencyChoice>().also { it.putAll(seed?.choices ?: emptyMap()) } }
    val days = remember { mutableStateMapOf<String, Set<Int>>() }
    val weekly = remember { mutableStateMapOf<String, Int>() }
    var typing by remember { mutableStateOf(!seed?.query.isNullOrEmpty()) }
    var query by remember { mutableStateOf(seed?.query ?: "") }
    var focused by remember { mutableStateOf(false) }
    var spoken by remember { mutableStateOf<String?>(null) }

    val owned = model.activeItems.map { Catalog.lookupKey(it.name) }.toSet()
    val typed = query.trim()
    val weekday = model.today.day.weekday

    fun isPicked(name: String): Boolean {
        val key = Catalog.lookupKey(name)
        return (selected + extras).any { Catalog.lookupKey(it) == key }
    }

    // Text left in the field once the keyboard is down counts as a pick.
    val fieldPick = if (typing && !focused && typed.isNotEmpty() && !isPicked(typed)) listOf(typed) else emptyList()
    val picked = selected + extras + fieldPick

    fun tick() {
        if (model.hapticsOn) model.onEffect(Effect.Feel(Haptic.TICK))
    }

    fun leaveTypeMode() {
        query = ""
        typing = false
        focused = false
    }

    fun pick(name: String) {
        tick()
        if (!isPicked(name)) {
            val entry = Catalog.entryNamed(name)
            if (entry != null && entry.isChip) selected.add(entry.name) else extras.add(name)
        }
        leaveTypeMode()
    }

    fun submit() {
        val rows = Suggest.rows(Suggest.rank(query, owned = owned), Suggest.literal(query), owned, capacity = Int.MAX_VALUE)
        val first = Suggest.firstPick(rows)
        if (first != null) pick(first.name) else leaveTypeMode()
    }

    // TalkBack hears the number of suggestions once typing pauses, not on every letter.
    LaunchedEffect(query) {
        if (typed.isEmpty() || !focused) return@LaunchedEffect
        delay(400)
        spoken = AddCopy.suggestions(Suggest.rank(query, owned = owned).size)
    }

    Column(Modifier.fillMaxWidth().fillMaxHeight().testTag("add-sheet")) {
        SheetHeader(title = AddCopy.TITLE, subtitle = AddCopy.SUBTITLE, onClose = onClose)
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val stage = maxHeight
            Column(Modifier.fillMaxSize()) {
                AnimatedVisibility(visible = typing, enter = fadeIn() + slideInVertically { -it / 3 }, exit = fadeOut() + slideOutVertically { -it / 3 }) {
                    TypeArea(
                        query = query,
                        onQuery = { query = it },
                        focused = focused,
                        onFocus = { now ->
                            focused = now
                            // Losing focus with nothing typed leaves type mode; with text, the field keeps it as a pick.
                            if (!now && typed.isEmpty()) typing = false
                        },
                        stageHeight = stage.value,
                        owned = owned,
                        onPick = ::pick,
                        onSubmit = ::submit,
                    )
                }
                Column(
                    Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp)
                        .padding(bottom = 24.dp),
                ) {
                    Spacer(Modifier.height(12.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (preset in Catalog.presets) {
                            val inStack = owned.contains(Catalog.lookupKey(preset.name))
                            val isOn = selected.contains(preset.name)
                            Chip(
                                name = preset.name,
                                isOn = isOn,
                                owned = inStack,
                                value = when {
                                    inStack -> AddCopy.IN_STACK
                                    isOn -> AddCopy.SELECTED_VALUE
                                    else -> AddCopy.NOT_SELECTED_VALUE
                                },
                            ) {
                                tick()
                                if (isOn) selected.remove(preset.name) else selected.add(preset.name)
                            }
                        }
                        for (name in extras.toList()) {
                            Chip(name = name, isOn = true, owned = false, value = AddCopy.SELECTED_VALUE) {
                                tick()
                                extras.remove(name)
                            }
                        }
                        CustomChip(typing) {
                            tick()
                            if (typing) leaveTypeMode() else typing = true
                        }
                    }
                    if (picked.isNotEmpty()) {
                        SectionHeader(AddCopy.HOW_OFTEN)
                        Card {
                            Column {
                                picked.forEachIndexed { index, name ->
                                    if (index > 0) RowDivider()
                                    val choice = choices[name] ?: AddPlan.defaultChoice(name)
                                    Column {
                                        Row(
                                            Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(start = 16.dp, end = 10.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                        ) {
                                            Text(
                                                name, style = TakenType.sans(16, FontWeight.Medium), color = colors.fg, maxLines = 1,
                                                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                                            )
                                            FrequencyMenu(choice, label = "$name, ${AddCopy.HOW_OFTEN.lowercase()}") { next ->
                                                if (next != choice) tick()
                                                choices[name] = next
                                            }
                                        }
                                        if (choice == FrequencyChoice.DAYS) {
                                            Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp)) {
                                                WeekdayPicker(days[name] ?: FrequencyChoice.defaultDays) { days[name] = it }
                                            }
                                        } else if (choice == FrequencyChoice.WEEKLY) {
                                            Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp)) {
                                                WeekdayPicker(setOf(weekly[name] ?: weekday), single = true) { weekly[name] = it.firstOrNull() ?: weekday }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if (!focused) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.line))
            PrimaryButton(
                if (picked.isEmpty()) AddCopy.ADD else "${AddCopy.ADD} ${picked.size}",
                enabled = picked.isNotEmpty(),
                modifier = Modifier.padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 8.dp).testTag("add-button"),
            ) {
                val drafts = AddPlan.drafts(
                    selected = selected.toList(), extras = extras.toList() + fieldPick, choices = choices.toMap(), days = days.toMap(),
                    weekly = weekly.toMap(), weekday = weekday,
                )
                if (drafts.isNotEmpty()) {
                    // Adding needs no Pro until the first dose; in locked mode it opens the paywall.
                    model.requirePro {
                        model.addItems(drafts)
                        onClose()
                    }
                }
            }
        }
        Announcement(spoken)
    }
}

/** The pinned field and the suggestions under it, as many rows as fit (`AddPlan.rowCapacity`). */
@Composable
private fun TypeArea(
    query: String,
    onQuery: (String) -> Unit,
    focused: Boolean,
    onFocus: (Boolean) -> Unit,
    stageHeight: Float,
    owned: Set<String>,
    onPick: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    val colors = Taken.colors
    val focus = remember { FocusRequester() }
    val fieldHeight = 50f
    val rowHeight = 48f
    val capacity = AddPlan.rowCapacity(available = stageHeight - 8 - fieldHeight - 8 - 8, rowHeight = rowHeight)
    val typed = query.trim()
    val rows = if (focused && typed.isNotEmpty()) {
        Suggest.rows(Suggest.rank(query, owned = owned), Suggest.literal(query), owned, capacity)
    } else {
        emptyList()
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val shape = RoundedCornerShape(Taken.shapes.cell)
        Row(
            Modifier
                .fillMaxWidth()
                .height(50.dp)
                .background(colors.bgRaised, shape)
                .border(1.dp, if (focused) colors.signalEdge else colors.line, shape)
                .padding(start = 14.dp, end = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (query.isEmpty()) Text(AddCopy.FIELD_PROMPT, style = TakenType.sans(17), color = colors.fgFaint)
                BasicTextField(
                    value = query,
                    onValueChange = onQuery,
                    singleLine = true,
                    textStyle = TakenType.sans(17).copy(color = colors.fg),
                    cursorBrush = SolidColor(colors.signal),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Words,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(onDone = { onSubmit() }),
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focus)
                        .onFocusChanged { onFocus(it.isFocused) }
                        .semantics { contentDescription = AddCopy.FIELD_LABEL }
                        .testTag("add-field"),
                )
            }
            if (query.isNotEmpty()) {
                Box(
                    Modifier.size(48.dp).clip(RoundedCornerShape(24.dp)).clickable(role = Role.Button) { onQuery("") }
                        .semantics { contentDescription = AddCopy.CLEAR },
                    contentAlignment = Alignment.Center,
                ) { Icon(Symbols.Close, contentDescription = null, tint = colors.fgFaint, modifier = Modifier.size(18.dp)) }
            }
        }
        if (rows.isNotEmpty()) {
            Card {
                Column {
                    rows.forEachIndexed { index, row ->
                        if (index > 0) RowDivider()
                        SuggestionRow(row, query, onPick)
                    }
                }
            }
        }
    }
}

@Composable
private fun SuggestionRow(row: SuggestRow, query: String, onPick: (String) -> Unit) {
    val colors = Taken.colors
    val enabled = row.isEnabled
    Row(
        Modifier
            .fillMaxWidth()
            .height(48.dp)
            .clickable(enabled = enabled, role = Role.Button) { onPick(row.name) }
            .semantics {
                contentDescription = when (row) {
                    is SuggestRow.Match -> row.suggestion.alias?.let { "${row.name}, $it" } ?: row.name
                    is SuggestRow.Literal -> AddCopy.literal(row.text)
                }
                if (!enabled) stateDescription = AddCopy.IN_STACK
            }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when (row) {
            is SuggestRow.Match -> {
                Text(matchText(row.suggestion, query), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                val alias = row.suggestion.alias
                if (alias != null) {
                    Spacer(Modifier.width(6.dp))
                    Text("· $alias", style = TakenType.sans(15), color = colors.fgFaint, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            is SuggestRow.Literal -> Text(
                "+ " + AddCopy.literal(row.text),
                style = TakenType.sans(17, FontWeight.Medium),
                color = if (row.owned) colors.fgFaint else colors.signalInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
        }
        Spacer(Modifier.weight(1f))
        if (!enabled) Icon(Symbols.Check, contentDescription = null, tint = colors.fgFaint, modifier = Modifier.size(16.dp))
    }
}

/** What was typed muted, the rest emphasised (Suggest.segments): "Tur|meric". A typo or alias match has no typed part. */
@Composable
private fun matchText(suggestion: Suggestion, query: String): androidx.compose.ui.text.AnnotatedString {
    val colors = Taken.colors
    return annotatedMatch(suggestion, query, colors)
}

private fun annotatedMatch(suggestion: Suggestion, query: String, colors: com.tombaxter.taken.ui.theme.TakenColors) = buildAnnotatedString {
    val name = suggestion.entry.name
    if (suggestion.owned) {
        withStyle(SpanStyle(color = colors.fgFaint, fontFamily = TakenType.sans, fontSize = TakenType.sans(17).fontSize)) { append(name) }
        return@buildAnnotatedString
    }
    val segments = if (suggestion.alias == null && suggestion.tier < 3) Suggest.segments(name, query) else listOf(Suggest.Segment(name, false))
    for (segment in segments) {
        val style = if (segment.typed) {
            SpanStyle(color = colors.fgMuted, fontFamily = TakenType.sans, fontWeight = FontWeight.Normal, fontSize = TakenType.sans(17).fontSize)
        } else {
            SpanStyle(color = colors.fg, fontFamily = TakenType.sans, fontWeight = FontWeight.SemiBold, fontSize = TakenType.sans(17).fontSize)
        }
        withStyle(style) { append(segment.text) }
    }
}

/** A chip: mono caps, the look's control corners. Lit with a small lamp when picked; faint with a check when owned. */
@Composable
private fun Chip(name: String, isOn: Boolean, owned: Boolean, value: String, onClick: () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.control)
    Row(
        Modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(if (isOn) colors.signalWash else colors.bgRaised, shape)
            .border(1.dp, if (isOn) colors.signalEdge else colors.line, shape)
            .clickable(enabled = !owned, role = Role.Checkbox, onClick = onClick)
            .semantics {
                contentDescription = name
                stateDescription = value
            }
            .padding(horizontal = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (owned) {
            Icon(Symbols.Check, contentDescription = null, tint = colors.fgFaint, modifier = Modifier.size(12.dp))
            Spacer(Modifier.width(7.dp))
        } else if (isOn) {
            Box(Modifier.size(6.dp).background(colors.signal, RoundedCornerShape(if (Taken.colors.isLight) 3.dp else 0.dp)))
            Spacer(Modifier.width(7.dp))
        }
        Text(
            name.uppercase(),
            style = TakenType.monoCapsFixed(12),
            color = when {
                owned -> colors.fgFaint
                isOn -> colors.signalInk
                else -> colors.fg
            },
            maxLines = 1,
        )
    }
}

/** "+ CUSTOM", or "− CUSTOM" in the signal while typing. */
@Composable
private fun CustomChip(typing: Boolean, onClick: () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.control)
    Box(
        Modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .then(if (typing) Modifier.background(colors.signalWash, shape) else Modifier)
            .border(1.dp, if (typing) colors.signalEdge else colors.lineStrong, shape)
            .clickable(role = Role.Checkbox, onClick = onClick)
            .semantics {
                contentDescription = AddCopy.CUSTOM_CHIP
                stateDescription = if (typing) AddCopy.SELECTED_VALUE else AddCopy.NOT_SELECTED_VALUE
            }
            .padding(horizontal = 13.dp)
            .testTag("custom-chip"),
        contentAlignment = Alignment.Center,
    ) {
        Text(if (typing) "− CUSTOM" else "+ CUSTOM", style = TakenType.monoCapsFixed(12), color = if (typing) colors.signalInk else colors.fgMuted)
    }
}
