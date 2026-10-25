package com.tombaxter.taken.ui.weight

import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateTo
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.rememberSplineBasedDecay
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.calculateTargetValue
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.FlingBehavior
import androidx.compose.foundation.gestures.ScrollScope
import androidx.compose.foundation.gestures.ScrollableDefaults
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.Sheet
import com.tombaxter.taken.clearWeightGoal
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.weight.WeighIn
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightEntry
import com.tombaxter.taken.core.weight.WeightFigure
import com.tombaxter.taken.core.weight.WeightFold
import com.tombaxter.taken.core.weight.WeightFormat
import com.tombaxter.taken.core.weight.WeightGoalCopy
import com.tombaxter.taken.core.weight.WeightLine
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.core.weight.day
import com.tombaxter.taken.deleteWeighIn
import com.tombaxter.taken.editWeighIn
import com.tombaxter.taken.hideWeightTab
import com.tombaxter.taken.openWeightGoal
import com.tombaxter.taken.requestWeightEntry
import com.tombaxter.taken.saveWeighIn
import com.tombaxter.taken.setWeightUnit
import com.tombaxter.taken.ui.components.PrimaryButton
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.shell.AvatarButton
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.ToastHost
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import com.tombaxter.taken.weightAccess
import com.tombaxter.taken.weightFigure
import com.tombaxter.taken.weightLine
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.tombaxter.taken.setWeightRange
import com.tombaxter.taken.weightPicture
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * The Weight tab (SPEC 3.12; SPEC-ANDROID 12; REDESIGN.md, "Weight tab page: entry first, 2026-10-22"), ported from
 * Taken/Weight/WeightTabRootView.swift and WeightEntryView.swift: one vertical scroll with two screens. Screen one is the
 * big number, the small line under it and a chevron; screen two is the trend, how close it is to the goal, the chart card
 * and All weigh-ins, one scroll down. The page height is measured with the keyboard left out and frozen while typing, so
 * the number never moves; the Weigh in bar rides on the keyboard (the IME's inset, edge to edge,
 * https://developer.android.com/develop/ui/compose/system/insets). Off until the person turns it on in Profile or from
 * Today's one-time offer. Weight never shows on Today (apart from the offer), in the widgets, the tile, the nudge, the
 * streak or History.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WeightScreen(model: AppModel, platform: Platform) {
    val colors = Taken.colors
    val weight = model.weight
    val locale = weightLocale()
    val scroll = rememberScrollState()
    val focusManager = LocalFocusManager.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    var foldPx by remember { mutableIntStateOf(0) }
    var gapBelowPx by remember { mutableIntStateOf(0) }
    var lineBottomPx by remember { mutableIntStateOf(0) }
    var barTopPx by remember { mutableIntStateOf(0) }
    val frozenPage = remember { IntArray(1) }
    val still = animationsOff(model)

    // Typing ends whenever the page goes (another tab, Profile, the background): the draft goes with it.
    DisposableEffect(Unit) {
        onDispose {
            weight.entryFocused = false
            weight.draft = ""
        }
    }
    // Back closes the keyboard without saving, as VoiceOver's escape does on the iPhone.
    BackHandler(enabled = weight.entryFocused) { focusManager.clearFocus() }
    // Any drag of the page ends typing (the iPhone's scrollDismissesKeyboard(.immediately)).
    LaunchedEffect(scroll) {
        scroll.interactionSource.interactions.collect { interaction ->
            if (interaction is DragInteraction.Start && weight.entryFocused) focusManager.clearFocus()
        }
    }
    // The keyboard put away by its own key or a back gesture ends typing too, so the number never waits half-typed.
    val imeVisible = WindowInsets.isImeVisible
    var imeSeen by remember { mutableStateOf(false) }
    LaunchedEffect(imeVisible, weight.entryFocused) {
        if (!weight.entryFocused) imeSeen = false
        else if (imeVisible) imeSeen = true
        else if (imeSeen) focusManager.clearFocus()
    }
    // On small phones or with large text: once the keyboard has settled (0.35 s after the bar last moved), if the small
    // line comes within 16 of the Weigh in bar, the page scrolls up just enough.
    LaunchedEffect(weight.entryFocused, barTopPx) {
        if (!weight.entryFocused) return@LaunchedEffect
        delay(350)
        val clearance = with(density) { 16.dp.roundToPx() }
        if (barTopPx > 0 && lineBottomPx > barTopPx - clearance) scroll.animateScrollBy((lineBottomPx - (barTopPx - clearance)).toFloat())
    }
    // Debug captures: the trend screens open scrolled to screen two.
    LaunchedEffect(weight.demoOpensOnTrend, foldPx) {
        if (weight.demoOpensOnTrend && foldPx > 0) scroll.scrollTo(foldPx)
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(colors.bg)
            .onGloballyPositioned { c ->
                gapBelowPx = (c.findRootCoordinates().size.height - c.boundsInRoot().bottom).roundToInt().coerceAtLeast(0)
            }
            .testTag("weight"),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            // The page height: the space between the status bar and the navigation bar, frozen while typing.
            if (!weight.entryFocused || frozenPage[0] == 0) frozenPage[0] = constraints.maxHeight
            val page = with(density) { frozenPage[0].toDp() }
            val fling = rememberFoldFling(scroll, { foldPx.toFloat() }, { !weight.entryFocused })
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(scroll, flingBehavior = fling)
                    .padding(horizontal = 20.dp),
            ) {
                EntryPage(
                    model = model,
                    locale = locale,
                    modifier = Modifier.fillMaxWidth().heightIn(min = page).onSizeChanged { foldPx = it.height },
                    onLineBottom = { lineBottomPx = it },
                    onSave = { save(model, locale) { focusManager.clearFocus() } },
                    onShowTrend = {
                        scope.launch { if (still) scroll.scrollTo(foldPx) else scroll.animateScrollTo(foldPx, tween(350)) }
                    },
                    onDismissTyping = { focusManager.clearFocus() },
                )
                if (!weight.isEmpty) TrendPage(model, locale, Modifier.fillMaxWidth().heightIn(min = page))
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            if (weight.entryFocused) {
                val imePx = WindowInsets.ime.getBottom(density)
                val lift = with(density) { (imePx - gapBelowPx).coerceAtLeast(0).toDp() }
                val kg = WeightFormat.kilograms(weight.draft, weight.unit, locale)
                PrimaryButton(
                    WeightCopy.WEIGH_IN,
                    enabled = kg != null,
                    modifier = Modifier
                        .padding(bottom = lift)
                        .padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 12.dp)
                        .onGloballyPositioned { barTopPx = it.boundsInRoot().top.roundToInt() }
                        .testTag("weigh-in"),
                ) { save(model, locale) { focusManager.clearFocus() } }
            } else if (model.sheet != Sheet.WeighIns) {
                // The toast with Undo, over the bottom of screen one: the number never moves for it. All weigh-ins shows
                // its own while it is open.
                Box(Modifier.padding(bottom = 8.dp)) { ToastHost(model, platform) }
            }
        }
    }
}

/** Weigh in: read the number, close the keyboard, then save, so the digits stay as today's without a flash. */
private fun save(model: AppModel, locale: Locale, closeKeyboard: () -> Unit) {
    val kg = WeightFormat.kilograms(model.weight.draft, model.weight.unit, locale) ?: return
    closeKeyboard()
    model.weight.entryFocused = false
    model.weight.draft = ""
    model.saveWeighIn(kg, locale)
}

/** The person's locale for numbers and units, read so a language change recomposes the page. */
@Composable
internal fun weightLocale(): Locale = LocalConfiguration.current.locales.get(0)

/** Android's "Remove animations" (animator duration scale 0), and debug captures, which hold still. */
@Composable
internal fun animationsOff(model: AppModel): Boolean {
    val context = LocalContext.current
    return remember(model.isDemo) {
        model.isDemo || Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/**
 * Where a fling comes to rest (`WeightFold.snap`): one that would stop between the number and the top of the trend lands
 * on whichever is nearer, so a flick goes all the way; below the fold, scrolling is free; off while typing. The decay is
 * Compose's own spline (https://developer.android.com/develop/ui/compose/touch-input/pointer-input/scroll), so the
 * projected stop is where the platform's fling would have ended.
 */
@Composable
private fun rememberFoldFling(scroll: ScrollState, fold: () -> Float, enabled: () -> Boolean): FlingBehavior {
    val decay = rememberSplineBasedDecay<Float>()
    val default = ScrollableDefaults.flingBehavior()
    return remember(scroll, decay, default) {
        object : FlingBehavior {
            override suspend fun ScrollScope.performFling(initialVelocity: Float): Float {
                val foldValue = fold()
                if (!enabled() || foldValue <= 0f) return with(default) { performFling(initialVelocity) }
                val current = scroll.value.toFloat()
                val projected = current + decay.calculateTargetValue(0f, initialVelocity)
                val snapped = WeightFold.snap(projected.toDouble(), foldValue.toDouble()).toFloat()
                if (snapped == projected) return with(default) { performFling(initialVelocity) }
                var last = 0f
                AnimationState(initialValue = 0f, initialVelocity = initialVelocity).animateTo(
                    targetValue = snapped - current,
                    animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow),
                    sequentialAnimation = true,
                ) {
                    val delta = value - last
                    val consumed = scrollBy(delta)
                    last = value
                    // The edge of the page: nothing left to scroll.
                    if (abs(delta) > 0.5f && abs(consumed) < 0.01f) cancelAnimation()
                }
                return 0f
            }
        }
    }
}

// MARK: - Screen one

/**
 * Screen one: More options and the avatar top right, one big number in the middle (the last weigh-in in grey with the
 * signal caret, or today's in the look's ink), one small line under it, and a small chevron at the bottom. Nothing else.
 */
@Composable
private fun EntryPage(
    model: AppModel,
    locale: Locale,
    modifier: Modifier,
    onLineBottom: (Int) -> Unit,
    onSave: () -> Unit,
    onShowTrend: () -> Unit,
    onDismissTyping: () -> Unit,
) {
    val weight = model.weight
    val focused = weight.entryFocused
    Column(
        // A tap anywhere outside the number closes the keyboard without saving. The down is never consumed, so a drag
        // from anywhere still scrolls the page.
        modifier.pointerInput(Unit) {
            awaitEachGesture {
                awaitFirstDown()
                val up = waitForUpOrCancellation()
                if (up != null && model.weight.entryFocused) {
                    up.consume()
                    onDismissTyping()
                }
            }
        },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TopBar(model)
        // Two weights above and three below: the block's centre sits 40% of the way down the free space.
        Spacer(Modifier.height(16.dp))
        Spacer(Modifier.weight(2f))
        Block(model, locale, onLineBottom, onSave)
        Spacer(Modifier.height(16.dp))
        Spacer(Modifier.weight(3f))
        Chevron(visible = !weight.isEmpty && !focused, onShowTrend)
    }
}

/** More options and the avatar exactly where TabHeader puts the avatar on the other tabs, and an invisible "Weight" heading. */
@Composable
private fun TopBar(model: AppModel) {
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(1.dp).semantics { heading(); contentDescription = WeightCopy.TAB })
        Spacer(Modifier.weight(1f))
        MoreMenu(model)
        Spacer(Modifier.width(4.dp))
        AvatarButton(model)
    }
}

/**
 * The overflow button left of the avatar (Material's three dots, TalkBack "More options"): Kilograms and Pounds with a
 * check on the one in use, a divider, Set goal… (or Change goal… and Clear goal), a divider, and Hide Weight tab, which
 * acts at once with Undo and asks nothing, because nothing is deleted. Clear goal does the same. Flat, with the look's
 * hairline, as Today's long-press menu.
 */
@Composable
private fun MoreMenu(model: AppModel) {
    val colors = Taken.colors
    val weight = model.weight
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier
                .size(48.dp)
                .clip(androidx.compose.foundation.shape.CircleShape)
                .clickable(role = Role.Button) { open = true }
                .semantics { contentDescription = WeightCopy.MORE }
                .testTag("weight-more"),
            contentAlignment = Alignment.Center,
        ) { Icon(Symbols.MoreVert, contentDescription = null, tint = colors.fgMuted, modifier = Modifier.size(24.dp)) }
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            shape = RoundedCornerShape(Taken.shapes.card),
            containerColor = colors.bgInset,
            tonalElevation = 0.dp,
            shadowElevation = 0.dp,
            border = BorderStroke(1.dp, colors.lineStrong),
        ) {
            val itemColors = MenuDefaults.itemColors(
                textColor = colors.fg,
                trailingIconColor = colors.signalInk,
                disabledTextColor = colors.fgFaint,
            )
            for (unit in WeightUnit.entries) {
                val chosen = weight.unit == unit
                DropdownMenuItem(
                    text = { Text(unit.menuTitle, style = TakenType.sans(16)) },
                    onClick = {
                        open = false
                        model.setWeightUnit(unit)
                    },
                    trailingIcon = if (chosen) {
                        { Icon(Symbols.Check, contentDescription = null, modifier = Modifier.size(20.dp)) }
                    } else {
                        null
                    },
                    colors = itemColors,
                    modifier = Modifier.semantics { selected = chosen },
                )
            }
            HorizontalDivider(color = colors.line)
            if (weight.goal == null) {
                DropdownMenuItem(
                    text = { Text(WeightGoalCopy.SET_GOAL, style = TakenType.sans(16)) },
                    onClick = {
                        open = false
                        model.openWeightGoal()
                    },
                    // Dimmed until there is a weigh-in to start from.
                    enabled = !weight.isEmpty,
                    colors = itemColors,
                )
            } else {
                DropdownMenuItem(
                    text = { Text(WeightGoalCopy.CHANGE_GOAL, style = TakenType.sans(16)) },
                    onClick = {
                        open = false
                        model.openWeightGoal()
                    },
                    enabled = !weight.isEmpty,
                    colors = itemColors,
                )
                DropdownMenuItem(
                    text = { Text(WeightGoalCopy.CLEAR_GOAL, style = TakenType.sans(16)) },
                    onClick = {
                        open = false
                        model.clearWeightGoal()
                    },
                    colors = itemColors,
                )
            }
            HorizontalDivider(color = colors.line)
            DropdownMenuItem(
                text = { Text(WeightCopy.HIDE_TAB, style = TakenType.sans(16)) },
                onClick = {
                    open = false
                    model.hideWeightTab()
                },
                colors = itemColors,
                modifier = Modifier.testTag("hide-weight-tab"),
            )
        }
    }
}

/**
 * The block: the figure line and the small line, one tap target. A tap brings the keyboard once Pro allows it; a long
 * press on today's number opens Edit… and Delete. The real text field lies over the figure, invisible, for the keyboard
 * and TalkBack; a layer over the whole block takes the touches, so a tap goes through the Pro rule first.
 */
@Composable
private fun Block(model: AppModel, locale: Locale, onLineBottom: (Int) -> Unit, onSave: () -> Unit) {
    val weight = model.weight
    val focused = weight.entryFocused
    val todays = todaysWeighIn(model)
    val locked = model.weightAccess == ProAccess.LOCKED
    var menu by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().heightIn(min = 160.dp), contentAlignment = Alignment.Center) {
        Column(Modifier.fillMaxWidth().padding(vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(contentAlignment = Alignment.Center) {
                FigureLine(model, locale)
                if (model.weightAccess.allowsLogging) {
                    EntryField(model, locale, todays, Modifier.matchParentSize(), onSave)
                } else {
                    LockedField(model, locale, todays, Modifier.matchParentSize())
                }
            }
            Spacer(Modifier.height(12.dp))
            SmallLine(model, locale, Modifier.onGloballyPositioned { onLineBottom(it.boundsInRoot().bottom.roundToInt()) })
        }
        // The layer that takes touches: the field under it never sees them (Compose gives a touch to the top-most
        // sibling), so a tap always goes through the Pro rule. The down is never consumed, so a drag from the number
        // still scrolls the page; a press held past Android's long-press timeout opens the menu.
        val haptic = LocalHapticFeedback.current
        Box(
            Modifier
                .matchParentSize()
                .pointerInput(Unit) {
                    awaitEachGesture {
                        awaitFirstDown()
                        var cancelled = false
                        val up = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                            waitForUpOrCancellation().also { if (it == null) cancelled = true }
                        }
                        when {
                            up != null -> {
                                up.consume()
                                if (!model.weight.entryFocused) model.requestWeightEntry()
                            }
                            !cancelled && !model.weight.entryFocused && todaysWeighIn(model) != null -> {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                menu = true
                                waitForUpOrCancellation()?.consume()
                            }
                        }
                    }
                }
                .testTag("weight-number"),
        )
        DropdownMenu(
            expanded = menu && !focused && todays != null,
            onDismissRequest = { menu = false },
            shape = RoundedCornerShape(Taken.shapes.card),
            containerColor = Taken.colors.bgInset,
            tonalElevation = 0.dp,
            shadowElevation = 0.dp,
            border = BorderStroke(1.dp, Taken.colors.lineStrong),
        ) {
            val itemColors = MenuDefaults.itemColors(textColor = Taken.colors.fg)
            DropdownMenuItem(
                text = { Text(WeightCopy.EDIT, style = TakenType.sans(16)) },
                onClick = {
                    menu = false
                    todays?.let { model.editWeighIn(it.id) }
                },
                colors = itemColors,
            )
            DropdownMenuItem(
                text = { Text(WeightCopy.DELETE, style = TakenType.sans(16), color = Taken.colors.danger) },
                onClick = {
                    menu = false
                    todays?.let { model.deleteWeighIn(it.id) }
                },
                colors = itemColors,
            )
        }
    }
    if (locked && focused) LaunchedEffect(Unit) { weight.entryFocused = false }
}

/** Today's latest weigh-in, if there is one: the long-press menu and the field's actions act on it. */
private fun todaysWeighIn(model: AppModel): WeighIn? {
    val last = model.weight.state.last ?: return null
    return if (model.clock.day(last) == model.today.day) last else null
}

/**
 * The digits (Geist Mono Regular 72, fixed at every text size, the separator pulled in), the caret or the lock, and the
 * unit. Drawn only: TalkBack reads the field over it.
 */
@Composable
private fun FigureLine(model: AppModel, locale: Locale) {
    val colors = Taken.colors
    val weight = model.weight
    val unit = weight.unit
    val focused = weight.entryFocused
    val figure = model.weightFigure
    val locked = model.weightAccess == ProAccess.LOCKED
    val ghost = weight.state.last?.let { WeightFormat.value(it.kg, unit, locale) } ?: ""
    val shown = when (figure) {
        WeightFigure.Empty -> ""
        is WeightFigure.Ghost -> WeightFormat.value(figure.kg, unit, locale)
        is WeightFigure.Today -> WeightFormat.value(figure.kg, unit, locale)
        is WeightFigure.Typing -> figure.text
    }
    val grey = figure == WeightFigure.Empty || figure is WeightFigure.Ghost
    val caret = !locked && (focused || grey)
    // The caret sits after the typed digits, else before the grey ones.
    val afterDigits = focused && weight.draft.isNotEmpty()
    // The caret pulses on appear and whenever the number turns grey or empty again (after Undo).
    var pulse by remember { mutableIntStateOf(0) }
    LaunchedEffect(grey && !focused) { if (grey && !focused) pulse += 1 }
    Row(Modifier.clearAndSetSemantics { }, verticalAlignment = Alignment.Bottom) {
        Box(Modifier.alignByBaseline(), contentAlignment = Alignment.CenterStart) {
            // The box keeps the longer of the grey value and the draft, so nothing re-centres while typing.
            Digits(WeightEntry.sizing(ghost, weight.draft), Color.Transparent)
            Box(contentAlignment = Alignment.CenterStart) {
                Digits(shown, if (grey) colors.fgSubtle else colors.fg)
                if (caret) {
                    Caret(
                        blinking = focused,
                        key = if (focused) weight.draft else "resting",
                        pulse = pulse,
                        still = animationsOff(model),
                        modifier = Modifier
                            .align(if (afterDigits) Alignment.CenterEnd else Alignment.CenterStart)
                            .offset(x = if (afterDigits) 1.5.dp else (-1.5).dp),
                    )
                } else if (locked) {
                    Icon(
                        Symbols.LockFill, contentDescription = null, tint = colors.signalInk,
                        modifier = Modifier.align(Alignment.CenterStart).offset(x = (-(17 + 6)).dp).size(17.dp),
                    )
                }
            }
        }
        Spacer(Modifier.width(8.dp))
        Text(
            unit.symbol,
            style = TakenType.sans(22, FontWeight.Medium).copy(fontSize = cappedSp(22, 1.5f)),
            color = if (grey) colors.fgSubtle else colors.fgMuted,
            modifier = Modifier.alignByBaseline(),
        )
    }
}

/** A size that grows with the person's text size up to `cap` times, the iPhone's `dynamicTypeSize(...accessibility1)`. */
@Composable
private fun cappedSp(size: Int, cap: Float) = with(LocalDensity.current) {
    if (fontScale <= cap) size.sp else (size * cap).dp.toSp()
}

/** Every string in the digits box, at one fixed size so widths always match: Geist Mono Regular 72. */
@Composable
private fun Digits(text: String, color: Color) {
    val style = TakenType.monoFixed(72, FontWeight.Normal)
    if (text.isEmpty()) {
        // Nothing, at the full line height, so the caret and the unit keep their place and baseline.
        Box(Modifier.width(0.dp)) { Text("0", style = style, color = Color.Transparent, maxLines = 1, softWrap = false) }
    } else {
        Text(figureText(text), style = style, color = color, maxLines = 1, softWrap = false)
    }
}

/**
 * The digits with the last whole digit and the separator pulled together: the iPhone kerns both by -11 pt. Android's
 * letter spacing sits half before and half after each glyph, so -22 on the separator alone gives the same two gaps.
 */
internal fun figureText(text: String): AnnotatedString = buildAnnotatedString {
    val separator = text.indexOfFirst { !it.isDigit() }
    text.forEachIndexed { index, c ->
        if (index == separator) {
            withStyle(SpanStyle(letterSpacing = (-22f / 72f).em)) { append(c) }
        } else {
            append(c)
        }
    }
}

/**
 * The drawn caret: 3 by 59 in the look's signal colour. At rest it pulses three times and then holds at full strength;
 * while typing it blinks, half a second on and off with 0.1 s fades, and restarts with each key so it stays solid while
 * keys are pressed. It holds still with Android's animations removed and in debug captures.
 */
@Composable
private fun Caret(blinking: Boolean, key: String, pulse: Int, still: Boolean, modifier: Modifier) {
    val colors = Taken.colors
    val alpha = remember { Animatable(1f) }
    LaunchedEffect(blinking, key, pulse, still) {
        alpha.snapTo(1f)
        if (still) return@LaunchedEffect
        if (blinking) {
            while (true) {
                delay(400)
                alpha.animateTo(0f, tween(100))
                delay(500)
                alpha.animateTo(1f, tween(100))
                delay(100)
            }
        } else {
            repeat(3) {
                alpha.animateTo(0.3f, tween(600))
                alpha.animateTo(1f, tween(600))
            }
        }
    }
    Box(modifier.width(3.dp).height(59.dp).alpha(alpha.value).background(colors.signal, RoundedCornerShape(1.5.dp)))
}

/**
 * The real field, invisible, over the figure: the decimal keyboard (KeyboardType.Decimal, which shows the locale's
 * separator, https://developer.android.com/develop/ui/compose/text/user-input), and TalkBack's node for the number. Its
 * label and actions are the iPhone's VoiceOver ones.
 */
@Composable
private fun EntryField(model: AppModel, locale: Locale, todays: WeighIn?, modifier: Modifier, onSave: () -> Unit) {
    val weight = model.weight
    val unit = weight.unit
    val focused = weight.entryFocused
    val requester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    var rangeAnnounced by remember { mutableStateOf(false) }
    LaunchedEffect(weight.entryRequested) {
        if (!weight.entryRequested) return@LaunchedEffect
        weight.entryRequested = false
        withFrameNanos { }
        runCatching { requester.requestFocus() }
        keyboard?.show()
    }
    val label = if (todays == null) WeightCopy.fieldLabel(unit) else WeightCopy.TODAYS_WEIGH_IN
    val actions = if (!focused && todays != null) {
        listOf(
            CustomAccessibilityAction(WeightCopy.EDIT_WEIGH_IN) { model.editWeighIn(todays.id); true },
            CustomAccessibilityAction(WeightCopy.DELETE_WEIGH_IN) { model.deleteWeighIn(todays.id); true },
        )
    } else {
        emptyList()
    }
    BasicTextField(
        value = weight.draft,
        onValueChange = { typed ->
            val clean = WeightFormat.sanitize(typed, locale, unit.decimals)
            weight.draft = clean
            if (!rangeAnnounced && WeightEntry.showsRangeHint(clean, unit, locale)) {
                rangeAnnounced = true
                model.say(WeightCopy.spokenRangeHint(unit))
            }
        },
        singleLine = true,
        textStyle = TextStyle(color = Color.Transparent, fontSize = 1.sp),
        cursorBrush = SolidColor(Color.Transparent),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done, autoCorrectEnabled = false),
        keyboardActions = KeyboardActions(onDone = { onSave() }),
        modifier = modifier
            .focusRequester(requester)
            .onFocusChanged { state ->
                if (state.isFocused == weight.entryFocused) return@onFocusChanged
                weight.entryFocused = state.isFocused
                if (!state.isFocused) {
                    weight.draft = ""
                    rangeAnnounced = false
                }
            }
            .semantics {
                contentDescription = label
                if (!focused && todays != null) stateDescription = WeightFormat.spoken(todays.kg, unit, locale)
                customActions = actions
            }
            .testTag("weight-field"),
    )
}

/**
 * While logging needs Taken Pro (or Play's first answer is still on its way): no field, so no keyboard; TalkBack's node
 * opens Taken Pro, and Delete stays open, as removing a dose does.
 */
@Composable
private fun LockedField(model: AppModel, locale: Locale, todays: WeighIn?, modifier: Modifier) {
    val unit = model.weight.unit
    Box(
        modifier.semantics {
            contentDescription = if (todays == null) WeightCopy.fieldLabel(unit) else WeightCopy.TODAYS_WEIGH_IN
            if (todays != null) stateDescription = WeightFormat.spoken(todays.kg, unit, locale)
            role = Role.Button
            onClick(label = "open Taken Pro") { model.requestWeightEntry(); true }
            if (todays != null) {
                customActions = listOf(CustomAccessibilityAction(WeightCopy.DELETE_WEIGH_IN) { model.deleteWeighIn(todays.id); true })
            }
        },
    )
}

/**
 * The small line under the number (`WeightEntry.line`): the range hint while typing, the moment a save just lit, how
 * close the trend is after a save with a goal, else the last weigh-in. Changes crossfade over 0.2 s.
 */
@Composable
private fun SmallLine(model: AppModel, locale: Locale, modifier: Modifier) {
    val weight = model.weight
    val unit = weight.unit
    val line = model.weightLine(locale)
    val spoken = when (line) {
        WeightLine.Range -> WeightCopy.spokenRangeHint(unit)
        WeightLine.Last -> WeightCopy.spokenLastLine(weight.state.last, unit, model.now, model.clock, locale)
        is WeightLine.Closing -> weight.goal?.let { WeightGoalCopy.spokenVisit(line.readout, it.kg, unit, locale) } ?: ""
        is WeightLine.Moment -> weight.goal?.let { WeightGoalCopy.spokenMoment(line.moment, it.kg, unit, locale) } ?: ""
    }
    AnimatedContent(
        targetState = line,
        contentKey = { it.kind },
        transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(200)) },
        label = "weight-line",
        modifier = modifier.fillMaxWidth().clearAndSetSemantics {
            contentDescription = spoken
            testTag = "weight-line"
        },
    ) { shown ->
        LineContent(model, locale, shown)
    }
}

@Composable
private fun LineContent(model: AppModel, locale: Locale, line: WeightLine) {
    val colors = Taken.colors
    val weight = model.weight
    val unit = weight.unit
    val goal = weight.goal
    when (line) {
        WeightLine.Range -> PlainLine(WeightCopy.rangeHint(unit))
        WeightLine.Last -> PlainLine(WeightCopy.lastLine(weight.state.last, model.now, model.clock))
        is WeightLine.Closing -> if (goal != null) {
            WeightGoalCopy.visit(line.readout, goal.kg, unit, locale)?.let { parts ->
                Text(
                    partsText(parts, numbers = colors.fg, words = colors.fgMuted, wordsWeight = FontWeight.Normal),
                    style = TakenType.sans(15), textAlign = TextAlign.Center, maxLines = 3, modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        is WeightLine.Moment -> if (goal != null) {
            val lift = with(LocalDensity.current) { 5.dp.roundToPx() }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                LitPoint(
                    springs = !weight.momentPlayed, bead = false, still = animationsOff(model),
                    // The dot's centre 5 above the first line's baseline.
                    modifier = Modifier.alignBy { it.measuredHeight / 2 + lift },
                    onShown = { weight.momentPlayed = true },
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    partsText(
                        WeightGoalCopy.moment(line.moment, goal.kg, unit, locale), numbers = colors.signalInk,
                        words = colors.signalInk, wordsWeight = FontWeight.Medium,
                    ),
                    style = TakenType.sans(15, FontWeight.Medium), textAlign = TextAlign.Center, maxLines = 3,
                    modifier = Modifier.alignByBaseline().weight(1f, fill = false),
                )
            }
        }
    }
}

@Composable
private fun PlainLine(text: String) {
    Text(
        text, style = TakenType.sans(15), color = Taken.colors.fgSubtle, textAlign = TextAlign.Center, maxLines = 3,
        modifier = Modifier.fillMaxWidth(),
    )
}

/** Numbers with their units in Geist Mono Medium 15; words in Geist 15. */
internal fun partsText(parts: List<WeightGoalCopy.Part>, numbers: Color, words: Color, wordsWeight: FontWeight): AnnotatedString =
    buildAnnotatedString {
        for (part in parts) {
            val style = if (part.isNumber) {
                SpanStyle(fontFamily = TakenType.mono, fontWeight = FontWeight.Medium, color = numbers)
            } else {
                SpanStyle(fontFamily = TakenType.sans, fontWeight = wordsWeight, color = words)
            }
            withStyle(style) { append(part.text) }
        }
    }

/**
 * A lit point: an 8 dp circle in the look's signal colour with its glow. On the chart it sits on a 12 dp circle in the
 * card's colour that cuts the line, like a bead; beside the moment sentence on screen one it stands alone and springs in
 * 0.35 s after the save with Today's All taken spring (a fade with animations removed). Never a touch target.
 */
@Composable
internal fun LitPoint(springs: Boolean, bead: Boolean, still: Boolean, modifier: Modifier = Modifier, onShown: () -> Unit = {}) {
    val colors = Taken.colors
    val progress = remember { Animatable(if (springs && !still) 0f else 1f) }
    LaunchedEffect(springs) {
        if (!springs || progress.value >= 1f) {
            onShown()
            return@LaunchedEffect
        }
        delay(350)
        progress.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = 280f))
        onShown()
    }
    val p = progress.value
    Canvas(modifier.size(if (bead) 12.dp else 16.dp).scale(0.55f + 0.45f * p.coerceIn(0f, 1.2f)).alpha(p.coerceIn(0f, 1f))) {
        if (bead) drawCircle(colors.bgRaised, 6.dp.toPx())
        val glow = 8.dp.toPx() - 4.dp.toPx() * p.coerceIn(0f, 1f)
        drawCircle(Brush.radialGradient(listOf(colors.glow(0.7f - 0.35f * p.coerceIn(0f, 1f)), Color.Transparent), center, 4.dp.toPx() + glow), 4.dp.toPx() + glow)
        drawCircle(colors.signal, 4.dp.toPx())
    }
}

/** "Show trend": always laid out, so the block never moves when it comes or goes. */
@Composable
private fun Chevron(visible: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .padding(bottom = 8.dp)
            .size(48.dp)
            .alpha(if (visible) 1f else 0f)
            .then(
                if (visible) {
                    Modifier
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .clickable(role = Role.Button, onClick = onClick)
                        .semantics { contentDescription = WeightCopy.SHOW_TREND }
                        .testTag("show-trend")
                } else {
                    Modifier.clearAndSetSemantics { }
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Symbols.ExpandMore, contentDescription = null, tint = Taken.colors.fgSubtle, modifier = Modifier.size(20.dp))
    }
}

// MARK: - Screen two

/**
 * Screen two: "Trend" and its value, how close it is to the goal (the slot), the chart card with its ranges, the change
 * line and weekly dose ticks, and All weigh-ins. With one weigh-in day: the single dot and "Your trend starts here.".
 */
@Composable
private fun TrendPage(model: AppModel, locale: Locale, modifier: Modifier) {
    val colors = Taken.colors
    val weight = model.weight
    val unit = weight.unit
    val picture = model.weightPicture(weight.range)
    val firstDay = picture.trend.size <= 1
    Column(modifier.padding(top = 20.dp, bottom = 28.dp).testTag("weight-trend")) {
        Headline(model, picture, unit, locale)
        Spacer(Modifier.height(16.dp))
        com.tombaxter.taken.ui.components.Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (!firstDay) {
                    RangePicker(weight.range) { model.setWeightRange(it) }
                    picture.change?.let { change ->
                        val today = model.today.day
                        Text(
                            partsText(
                                WeightGoalCopy.changeLine(change.kg, change.span, unit, today, locale), numbers = colors.fg,
                                words = colors.fgMuted, wordsWeight = FontWeight.Normal,
                            ),
                            style = TakenType.sans(15), maxLines = 2,
                            modifier = Modifier.clearAndSetSemantics {
                                contentDescription = WeightGoalCopy.spokenChange(change.kg, change.span, unit, today, locale)
                            },
                        )
                    }
                }
                WeightChart(model, picture, unit, locale)
                if (firstDay) {
                    Text(WeightCopy.TREND_STARTS, style = TakenType.sans(15), color = colors.fgSubtle)
                } else if (picture.window.ticks.isNotEmpty()) {
                    Text(WeightCopy.TICKS, style = TakenType.sans(13), color = colors.fgSubtle)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        AllWeighInsRow(model, weight.state.weighIns.size)
    }
}

/** "Trend", the trend in Geist Mono 34, and the slot: "smooths daily swings", or how close it is to the goal. One heading. */
@Composable
private fun Headline(model: AppModel, picture: com.tombaxter.taken.WeightPicture, unit: WeightUnit, locale: Locale) {
    val colors = Taken.colors
    val goal = model.weight.goal
    val trendKg = picture.trend.lastOrNull()?.kg
    val readout = picture.readout
    val spoken = run {
        val trend = WeightCopy.spokenTrend(trendKg, unit, locale)
        if (goal == null || readout == null) "${trend.removeSuffix(".")}, ${WeightCopy.TREND_CAPTION}"
        else "$trend ${WeightGoalCopy.spokenSlot(readout, goal.kg, unit, locale)}."
    }
    Column(Modifier.fillMaxWidth().clearAndSetSemantics { heading(); contentDescription = spoken }) {
        Text(WeightCopy.TREND, style = TakenType.sans(14, FontWeight.Medium), color = colors.fgSubtle)
        if (trendKg != null) {
            Spacer(Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                BasicText(
                    WeightFormat.trend(trendKg, unit, locale),
                    style = TakenType.mono(34, FontWeight.Medium).copy(color = colors.fg),
                    maxLines = 1,
                    softWrap = false,
                    autoSize = TextAutoSize.StepBased(minFontSize = (34 * 0.7f).sp, maxFontSize = 34.sp),
                    modifier = Modifier.alignByBaseline().weight(1f, fill = false),
                )
                Spacer(Modifier.width(6.dp))
                Text(unit.symbol, style = TakenType.sans(18, FontWeight.Medium), color = colors.fgMuted, modifier = Modifier.alignByBaseline())
            }
        }
        Spacer(Modifier.height(2.dp))
        if (goal != null && readout != null) {
            Text(
                partsText(WeightGoalCopy.slot(readout, goal.kg, unit, locale), numbers = colors.fg, words = colors.fgMuted, wordsWeight = FontWeight.Normal),
                style = TakenType.sans(15), maxLines = 2,
            )
        } else {
            Text(WeightCopy.TREND_CAPTION, style = TakenType.sans(15), color = colors.fgSubtle)
        }
    }
}

/** "All weigh-ins", the count in Geist Mono and a chevron: the list sheet, to edit or delete a weigh-in. */
@Composable
private fun AllWeighInsRow(model: AppModel, count: Int) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(shape)
            .background(colors.bgRaised, shape)
            .border(1.dp, colors.line, shape)
            .clickable(role = Role.Button, onClickLabel = "edit or delete a weigh-in") { model.sheet = Sheet.WeighIns }
            .clearAndSetSemantics {
                contentDescription = "${WeightCopy.ALL_WEIGH_INS}, $count"
                role = Role.Button
                onClick(label = "edit or delete a weigh-in") { model.sheet = Sheet.WeighIns; true }
                testTag = "all-weigh-ins"
            }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(WeightCopy.ALL_WEIGH_INS, style = TakenType.sans(17), color = colors.fg, modifier = Modifier.weight(1f))
        Text("$count", style = TakenType.mono(15), color = colors.fgSubtle)
        Spacer(Modifier.width(6.dp))
        Icon(Symbols.ChevronRight, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(18.dp))
    }
}
