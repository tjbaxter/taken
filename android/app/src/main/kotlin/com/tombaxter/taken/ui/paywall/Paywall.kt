package com.tombaxter.taken.ui.paywall

import android.animation.ValueAnimator
import androidx.compose.animation.animateColorAsState
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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.Haptic
import com.tombaxter.taken.OffersPhase
import com.tombaxter.taken.PurchaseOutcome
import com.tombaxter.taken.RestoreOutcome
import com.tombaxter.taken.core.pro.PlanOffer
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.TrialStep
import com.tombaxter.taken.ui.components.CapsuleGlyph
import com.tombaxter.taken.ui.components.CloseButton
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.drawCheck
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Taken Pro (SPEC-ANDROID 9.6): what Pro is, three plans, one button, the terms Play asks for, and the way out. No
 * carousel, no countdown, nothing pressing (PRO.md). A full-screen dialog in Taken's look with a visible close, which
 * system back and predictive back also close.
 *
 * Google Play's Subscriptions policy shapes it (https://support.google.com/googleplay/android-developer/answer/9900533):
 * before the purchase it says the price, how often it is charged, how long the trial lasts and what it then costs, how to
 * cancel, and that logging needs Pro while the record stays readable without it; the billed amount is the most prominent
 * price ("about $1.67 / month" stays smaller, since annual plans that "most prominently display their pricing in terms of
 * monthly cost" are a violation); and the close is always visible ("Dismiss button is missing or not clearly visible" is a
 * violation).
 */
@Composable
fun PaywallHost(model: AppModel, platform: Platform) {
    if (model.paywall == null) return
    Dialog(
        onDismissRequest = { model.closePaywall() },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Paywall(model, platform)
    }
}

private enum class Busy { BUYING, RESTORING }

private data class Note(val text: String, val lit: Boolean)

@Composable
fun Paywall(model: AppModel, platform: Platform, initiallyUnlocked: Boolean = false) {
    val colors = Taken.colors
    val pro = model.pro
    val scope = rememberCoroutineScope()
    var selected by rememberSaveable { mutableStateOf(ProPlan.YEARLY) }
    var busy by remember { mutableStateOf<Busy?>(null) }
    var note by remember { mutableStateOf<Note?>(null) }
    var unlocked by remember { mutableStateOf(initiallyUnlocked) }
    val offers = pro.offers
    val answered = pro.offersPhase == OffersPhase.READY || pro.offersPhase == OffersPhase.FAILED
    val eligible = pro.introEligible == true
    fun missing(plan: ProPlan) = offers[plan] == null && answered

    // Yearly is chosen when Play returns it; otherwise the first plan it did return.
    LaunchedEffect(offers) {
        if (offers[selected] == null) ProPlan.entries.firstOrNull { offers[it] != null }?.let { selected = it }
    }

    fun celebrate(trialStarted: Boolean) {
        if (unlocked) return
        model.paywallUnlocked(trialStarted)
        note = null
        unlocked = true
        model.feedback(Haptic.CONFIRM)
        model.say("Taken Pro is on.")
        scope.launch {
            // The lit button holds a moment, then the paywall goes and the tap that opened it runs (the iPhone's 1.15 s).
            delay(if (ValueAnimator.areAnimatorsEnabled()) 1_150 else 700)
            model.closePaywall()
        }
    }

    // Pro came on another way while the paywall was up: a pending purchase approved, a purchase on another phone.
    LaunchedEffect(model.proActive) {
        if (model.proActive && !unlocked && busy == null) celebrate(trialStarted = false)
    }

    fun buy() {
        if (busy != null || unlocked) return
        val plan = selected
        busy = Busy.BUYING
        note = null
        scope.launch {
            val outcome = pro.purchase(plan)
            busy = null
            when (outcome) {
                is PurchaseOutcome.Unlocked -> celebrate(outcome.trialStarted)
                PurchaseOutcome.Pending -> note = Note(ProCopy.WAITING, lit = true)
                PurchaseOutcome.Cancelled -> Unit
                is PurchaseOutcome.Failed -> note = Note(outcome.text, lit = false)
            }
        }
    }

    fun restore() {
        if (busy != null || unlocked) return
        busy = Busy.RESTORING
        note = null
        scope.launch {
            val outcome = pro.restore()
            busy = null
            when (outcome) {
                RestoreOutcome.Restored -> celebrate(trialStarted = false)
                RestoreOutcome.Nothing -> note = Note(ProCopy.NOTHING_TO_RESTORE, lit = false)
                is RestoreOutcome.Failed -> note = Note(outcome.text, lit = false)
            }
        }
    }

    val offer = offers[selected]
    val ctaTitle = when {
        unlocked -> "Taken Pro is on"
        busy == Busy.BUYING -> "Confirming"
        busy == Busy.RESTORING -> "Restoring"
        // A plan Play did not return is never left on a spinner: the button asks again.
        offer == null -> if (answered) "Try again" else "Loading plans"
        else -> ProCopy.cta(offer, eligible)
    }
    val ctaEnabled = !unlocked && busy == null && (offer != null || answered)
    val terms = if (offer == null) ProCopy.termsWithoutPrices(selected) else ProCopy.terms(offer, eligible)
    val timeline = ProCopy.trialTimeline(offers[ProPlan.YEARLY], eligible, model.now, model.clock.zone, remindable = !platform.notificationsOff)
    // At very large text the button and terms scroll with the rest, so nothing is cut off (SPEC-ANDROID 6.2).
    val largeText = LocalDensity.current.fontScale >= 1.5f

    val content: @Composable () -> Unit = {
        Header(unlocked)
        Spacer(Modifier.height(22.dp))
        Features()
        Spacer(Modifier.height(24.dp))
        Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (plan in ProPlan.entries) {
                PlanCard(
                    plan = plan,
                    offer = offers[plan],
                    selected = selected == plan,
                    tag = ProCopy.introTag(ProCopy.liveIntro(offers[plan], eligible)),
                    missing = missing(plan),
                    answered = answered,
                    enabled = !unlocked && busy == null,
                ) {
                    if (selected != plan && !unlocked) {
                        model.feedback(Haptic.TICK)
                        selected = plan
                    }
                }
                if (plan == ProPlan.YEARLY && timeline.isNotEmpty()) TrialTimeline(timeline)
            }
        }
    }
    val dock: @Composable () -> Unit = {
        Dock(
            note = note,
            title = ctaTitle,
            enabled = ctaEnabled,
            busy = busy != null,
            unlocked = unlocked,
            terms = terms,
            onPrimary = {
                if (offer == null) {
                    scope.launch { pro.loadOffers(force = true) }
                } else {
                    buy()
                }
            },
            onRestore = { restore() },
            onPrivacy = { platform.openUrl(ProCopy.PRIVACY_URL) },
            restoreEnabled = busy == null && !unlocked,
        )
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(colors.bg)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .testTag("paywall"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TopBar(unlocked) { model.closePaywall() }
        if (largeText) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().weight(1f).verticalScroll(rememberScrollState())) {
                Column(Modifier.padding(horizontal = 20.dp)) { content() }
                Spacer(Modifier.height(16.dp))
                dock()
            }
        } else {
            Column(
                Modifier.widthIn(max = 560.dp).fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
                    .padding(bottom = 14.dp),
            ) { content() }
            Box(Modifier.widthIn(max = 560.dp).fillMaxWidth()) { dock() }
        }
    }
}

/** The glyph, Taken Pro, and the way out: a 48 dp close, always visible. */
@Composable
private fun TopBar(unlocked: Boolean, onClose: () -> Unit) {
    val colors = Taken.colors
    val lift by animateFloatAsState(if (unlocked) 1.12f else 1f, spring(dampingRatio = 0.62f, stiffness = Spring.StiffnessMedium), label = "glyph")
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = 20.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CapsuleGlyph(Modifier.size(22.dp).scale(lift))
        Spacer(Modifier.width(10.dp))
        Text(
            "Taken Pro",
            style = TakenType.sans(17, FontWeight.SemiBold),
            color = colors.fg,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        CloseButton(onClose)
    }
}

@Composable
private fun Header(unlocked: Boolean) {
    val colors = Taken.colors
    val ink by animateColorAsState(if (unlocked) colors.signalInk else colors.fg, tween(250), label = "headline")
    Column(
        Modifier.fillMaxWidth().padding(top = 10.dp).clearAndSetSemantics {
            contentDescription = "${ProCopy.HEADLINE} ${ProCopy.SUBLINE}"
            heading()
        },
    ) {
        Text(ProCopy.HEADLINE, style = TakenType.sans(34, FontWeight.SemiBold).copy(letterSpacing = (-0.5).sp), color = ink)
        Spacer(Modifier.height(10.dp))
        Text(ProCopy.SUBLINE_LINES, style = TakenType.sans(17, lineHeight = 24.sp), color = colors.fgMuted)
    }
}

/** What only Pro unlocks, each with a check in the look's signal. */
@Composable
private fun Features() {
    val colors = Taken.colors
    Column(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        for (line in ProCopy.features) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(22.dp).background(colors.signal, CircleShape), contentAlignment = Alignment.Center) {
                    Canvas(Modifier.size(14.dp)) {
                        drawCheck(colors.onSignal, size.minDimension, 2.dp.toPx(), Offset.Zero)
                    }
                }
                Spacer(Modifier.width(12.dp))
                Text(line, style = TakenType.sans(16, FontWeight.Medium), color = colors.fg)
            }
        }
    }
}

/**
 * One plan: a radio, its name and the trial tag, and its price. A radio button for TalkBack in a selectable group, at least
 * 64 dp tall. A plan Play did not return reads "--" and cannot be chosen.
 */
@Composable
private fun PlanCard(
    plan: ProPlan,
    offer: PlanOffer?,
    selected: Boolean,
    tag: String?,
    missing: Boolean,
    answered: Boolean,
    enabled: Boolean,
    onSelect: () -> Unit,
) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    val label = cardLabel(plan, offer, tag, missing)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clip(shape)
            .background(if (selected) colors.signalWash else colors.bgRaised, shape)
            .border(if (selected) 1.5.dp else 1.dp, if (selected) colors.signal else colors.line, shape)
            .selectable(selected = selected, enabled = enabled && !missing, role = Role.RadioButton, onClick = onSelect)
            .semantics { contentDescription = label }
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .testTag("plan-${plan.raw}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f).clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically) {
            Radio(selected)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(plan.title, style = TakenType.sans(17, FontWeight.SemiBold), color = colors.fg.copy(alpha = if (missing) 0.55f else 1f))
                if (tag != null) {
                    Spacer(Modifier.height(4.dp))
                    Text(tag, style = TakenType.sans(13, FontWeight.SemiBold), color = colors.signalInk)
                }
            }
            Spacer(Modifier.width(8.dp))
            PriceBlock(offer, selected, answered)
        }
    }
}

@Composable
private fun PriceBlock(offer: PlanOffer?, selected: Boolean, answered: Boolean) {
    val colors = Taken.colors
    if (offer == null) {
        Text(if (answered) "--" else "···", style = TakenType.mono(16), color = colors.fgFaint)
        return
    }
    val (amount, unit) = ProCopy.price(offer)
    Column(horizontalAlignment = Alignment.End) {
        // The billed amount is the most prominent price on the card.
        Row(verticalAlignment = Alignment.Bottom) {
            Text(amount, style = TakenType.mono(20), color = colors.fg, maxLines = 1)
            Spacer(Modifier.width(5.dp))
            Text(unit, style = TakenType.sans(14), color = if (selected) colors.fgMuted else colors.fgSubtle, maxLines = 1)
        }
        ProCopy.monthlyEquivalent(offer)?.let { monthly ->
            Spacer(Modifier.height(4.dp))
            // On the chosen card's signal wash the muted ink keeps it AA; the subtle one does on a plain card.
            Text(monthly, style = TakenType.sans(13), color = if (selected) colors.fgMuted else colors.fgSubtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A round radio, filled with the signal when chosen. */
@Composable
private fun Radio(on: Boolean) {
    val colors = Taken.colors
    val fill by animateFloatAsState(if (on) 1f else 0f, spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMedium), label = "radio")
    Box(
        Modifier.size(22.dp).border(1.5.dp, if (on) colors.signal else colors.lineStrong, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (fill > 0f) Box(Modifier.size(12.dp).scale(fill).background(colors.signal, CircleShape))
    }
}

private fun cardLabel(plan: ProPlan, offer: PlanOffer?, tag: String?, missing: Boolean): String {
    val parts = mutableListOf(plan.title)
    if (missing) parts.add("Not available right now")
    if (offer != null) {
        val period = offer.period
        parts.add(if (period != null) "${offer.displayPrice} ${ProCopy.per(period)}" else "${offer.displayPrice}, one payment")
        ProCopy.monthlyEquivalent(offer)?.let { parts.add(it.replace(" / ", " per ")) }
    }
    if (tag != null) parts.add(tag)
    return parts.joinToString(". ")
}

/**
 * The trial promise under the yearly plan: "Today", "Day 4", "Day 7", each with its line under it, left to right, or one
 * to a line when they do not fit side by side (larger text, a longer price). Calm: the look's tokens and Geist, no icons.
 */
@Composable
private fun TrialTimeline(steps: List<TrialStep>) {
    Layout(
        content = { steps.forEachIndexed { index, step -> TimelineStep(step, lit = index == 0) } },
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 2.dp)
            .clearAndSetSemantics { contentDescription = steps.joinToString(". ") { it.line } }
            .testTag("trial-timeline"),
    ) { measurables, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val gap = 10.dp.roundToPx()
        // Side by side when every step fits at its natural width (each measured once, as Compose requires).
        val natural = measurables.sumOf { it.maxIntrinsicWidth(Constraints.Infinity) } + gap * (measurables.size - 1).coerceAtLeast(0)
        if (natural <= constraints.maxWidth) {
            val placeables = measurables.map { it.measure(loose) }
            val height = placeables.maxOfOrNull { it.height } ?: 0
            layout(constraints.maxWidth, height) {
                val spare = if (placeables.size > 1) (constraints.maxWidth - placeables.sumOf { it.width }) / (placeables.size - 1) else 0
                var x = 0
                for (placeable in placeables) {
                    placeable.placeRelative(x, 0)
                    x += placeable.width + spare
                }
            }
        } else {
            // One step to a line, wrapping rather than cutting the price off.
            val placeables = measurables.map { it.measure(loose) }
            val spacing = 6.dp.roundToPx()
            val height = placeables.sumOf { it.height } + spacing * (placeables.size - 1).coerceAtLeast(0)
            layout(constraints.maxWidth, height) {
                var y = 0
                for (placeable in placeables) {
                    placeable.placeRelative(0, y)
                    y += placeable.height + spacing
                }
            }
        }
    }
}

@Composable
private fun TimelineStep(step: TrialStep, lit: Boolean) {
    val colors = Taken.colors
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(8.dp).background(if (lit) colors.signal else colors.bg, CircleShape)
                    .border(1.5.dp, if (lit) colors.signal else colors.lineStrong, CircleShape),
            )
            Spacer(Modifier.width(6.dp))
            Text(step.day, style = TakenType.sans(13, FontWeight.SemiBold), color = colors.fg)
        }
        Text(step.displayText, style = TakenType.sans(13), color = colors.fgMuted, modifier = Modifier.padding(start = 14.dp))
    }
}

/** Always visible under the plans: a note, the button, the terms Play asks for, and the links. */
@Composable
private fun Dock(
    note: Note?,
    title: String,
    enabled: Boolean,
    busy: Boolean,
    unlocked: Boolean,
    terms: String,
    onPrimary: () -> Unit,
    onRestore: () -> Unit,
    onPrivacy: () -> Unit,
    restoreEnabled: Boolean,
) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    val fill by animateColorAsState(
        when {
            unlocked -> colors.signalInk
            enabled || busy -> colors.button
            else -> colors.button.copy(alpha = 0.35f)
        },
        tween(220),
        label = "cta",
    )
    Column(Modifier.fillMaxWidth().background(colors.bg)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.line))
        Column(Modifier.padding(horizontal = 20.dp).padding(top = 14.dp, bottom = 2.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (note != null) {
                Row(
                    Modifier.fillMaxWidth().semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
                    verticalAlignment = Alignment.Top,
                ) {
                    Box(Modifier.padding(top = 7.dp).size(7.dp).background(if (note.lit) colors.signal else colors.fgSubtle, CircleShape))
                    Spacer(Modifier.width(10.dp))
                    Text(note.text, style = TakenType.sans(14), color = colors.fgMuted)
                }
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .clip(shape)
                    .background(fill, shape)
                    .clickable(enabled = enabled, role = Role.Button, onClick = onPrimary)
                    .semantics { contentDescription = title }
                    .testTag("paywall-cta"),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (busy) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = colors.buttonText, strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                } else if (unlocked) {
                    Icon(Symbols.Check, contentDescription = null, tint = colors.buttonText, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                }
                Text(title, style = TakenType.sans(17, FontWeight.SemiBold), color = colors.buttonText, maxLines = 2)
            }
            Text(terms, style = TakenType.sans(13, lineHeight = 18.sp), color = colors.fgMuted, modifier = Modifier.testTag("paywall-terms"))
            Text(ProCopy.NEEDS_PRO, style = TakenType.sans(13, lineHeight = 18.sp), color = colors.fgSubtle)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                FooterLink("Restore", "Restore purchases", restoreEnabled, onRestore)
                Text("·", style = TakenType.sans(13), color = colors.fgFaint, modifier = Modifier.clearAndSetSemantics { })
                FooterLink("Privacy", "Privacy Policy", true, onPrivacy)
            }
        }
    }
}

@Composable
private fun FooterLink(title: String, spoken: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = 48.dp)
            .widthIn(min = 48.dp)
            .clip(RoundedCornerShape(Taken.shapes.cell))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = spoken }
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = TakenType.sans(13, FontWeight.Medium), color = Taken.colors.fgMuted)
    }
}
