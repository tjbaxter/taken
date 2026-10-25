package com.tombaxter.taken.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.coerceIn
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.ColorFilter
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.semantics.testTag
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import com.tombaxter.taken.R
import com.tombaxter.taken.TakenApp
import com.tombaxter.taken.core.surfaces.StackWidgetFace
import com.tombaxter.taken.core.surfaces.WidgetBottom
import com.tombaxter.taken.core.surfaces.TakenWidgetKind
import com.tombaxter.taken.core.surfaces.WidgetCopy
import com.tombaxter.taken.core.surfaces.WidgetRowFace
import com.tombaxter.taken.core.theme.Look
import com.tombaxter.taken.core.theme.Looks
import java.util.Locale

/**
 * The stack widget (SPEC-ANDROID 10.1), the iPhone's Home Screen widget (Shared/WidgetViews.swift): the counter "2/3" with
 * its segmented bar and TAKE ALL; from 2x2 up the rows, pending first, where one tap logs that item's next dose without
 * opening Taken, refused inside the repeat hour exactly as `logNextDoseIfPending` refuses it, and never un-taking. Locked
 * (no Pro after the first dose): read-only with the PRO mark, and a tap opens the paywall with the log kept.
 *
 * Four layouts, chosen by size (`SizeMode.Responsive`, https://developer.android.com/develop/ui/compose/glance/build-ui):
 * 2x1, 2x2, 4x2 (the iPhone's medium) and 4x4. The widget reads the files the app writes and follows them while its
 * session runs; [com.tombaxter.taken.widget.Surfaces.refresh] redraws it after every write and at the moments the day
 * changes under it.
 */
class StackWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(WidgetSizes.SMALL, WidgetSizes.TALL, WidgetSizes.MEDIUM, WidgetSizes.LARGE))

    /** The widget picker's preview at the default 4x2 and at 2x2 (one or two sizes, Google's generated previews guide). */
    override val previewSizeMode = SizeMode.Responsive(setOf(WidgetSizes.TALL, WidgetSizes.MEDIUM))

    /** Taken keeps no Glance state: the widget draws the files. */
    override val stateDefinition: GlanceStateDefinition<*>? = null

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val surfaces = (context.applicationContext as TakenApp).container.surfaces
        // Read before the content, then followed inside it (Glance's own advice for `provideGlance`).
        val initial = surfaces.read()
        // The phone's language for TalkBack's times, read once per session: a new language restarts the widget's session.
        val locale = Locale.getDefault()
        provideContent {
            val inputs by surfaces.inputs.collectAsState(initial)
            val snapshot = surfaces.snapshot(inputs)
            StackWidgetContent(StackWidgetFace(snapshot, locale), Looks.look(snapshot.theme))
        }
    }

    /** A widget Android could not draw shows Taken's card in the person's look, never Glance's stock one (NEXT 7). */
    override fun onCompositionError(context: Context, glanceId: GlanceId, appWidgetId: Int, throwable: Throwable) {
        WidgetFallback.show(context, appWidgetId, TakenWidgetKind.STACK)
    }

    /** Android 15's generated preview: the demo stack in the person's look (SPEC-ANDROID 10.1). */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val surfaces = (context.applicationContext as TakenApp).container.surfaces
        val snapshot = surfaces.demoSnapshot()
        val face = StackWidgetFace(snapshot, Locale.getDefault())
        provideContent { StackWidgetContent(face, Looks.look(snapshot.theme)) }
    }
}

/** Android's entry point for the stack widget. Each update also re-arms the refresh, which a restart cancels. */
class StackWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StackWidget()

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        (context.applicationContext as TakenApp).container.surfaces.armSoon()
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        (context.applicationContext as TakenApp).container.surfaces.armSoon()
    }
}

/** Everything the stack widget draws, at the size Glance gives it. */
@Composable
fun StackWidgetContent(face: StackWidgetFace, look: Look) {
    val context = LocalContext.current
    val palette = WidgetPalette(look, context)
    val size = LocalSize.current
    var root = GlanceModifier.widgetFrame(palette).padding(12.dp)
    face.tap.action(context)?.let { root = root.clickable(it) }
    Box(root.semantics { testTag = "stack-widget" }) {
        when {
            size.width >= WidgetSizes.MEDIUM.width && size.height >= WidgetSizes.LARGE.height -> Large(face, palette, size.height)
            size.width >= WidgetSizes.MEDIUM.width && size.height >= WidgetSizes.MEDIUM.height -> Medium(face, palette, size.height)
            size.height >= WidgetSizes.TALL.height -> Tall(face, palette, size.height)
            else -> Small(face, palette)
        }
    }
}

/** 2x1: the mark, the counter and its bar on one line, TAKE ALL (or the status) under it. */
@Composable
private fun Small(face: StackWidgetFace, palette: WidgetPalette) {
    Column(GlanceModifier.fillMaxSize()) {
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            CapsuleMark(palette, 13.dp)
            Spacer(GlanceModifier.width(8.dp))
            if (!face.hasStack) {
                Text(WidgetCopy.EMPTY_TITLE, style = palette.hud(10f, palette.fgMuted), maxLines = 1)
            } else if (face.allTaken) {
                Text(WidgetCopy.ALL_TAKEN.replace('\n', ' '), style = palette.mono(16f, palette.signalInk, FontWeight.Bold), maxLines = 1)
            } else {
                Counter(face, palette, 22)
                Spacer(GlanceModifier.width(8.dp))
                Bar(face, palette, GlanceModifier.defaultWeight())
            }
            if (face.locked) {
                Spacer(GlanceModifier.width(6.dp))
                ProMark(palette)
            }
        }
        Spacer(GlanceModifier.defaultWeight())
        Bottom(face, palette)
    }
}

/** 2x2: the iPhone's small widget (header, counter, bar, TAKE ALL), and the rows that still fit under it. */
@Composable
private fun Tall(face: StackWidgetFace, palette: WidgetPalette, height: Dp) {
    Column(GlanceModifier.fillMaxSize()) {
        Header(face, palette)
        if (!face.hasStack) {
            // The empty state fills the widget rather than leaving it sparse (WT-1).
            Spacer(GlanceModifier.defaultWeight())
            CounterBlock(face, palette, counterSize = 32)
            Spacer(GlanceModifier.defaultWeight())
            return@Column
        }
        Spacer(GlanceModifier.height(6.dp))
        CounterBlock(face, palette, counterSize = 32)
        Rows(face, palette, height - 24.dp - TALL_BLOCK, divider = true, names = false)
    }
}

/** 4x2: the iPhone's medium widget, the counter block on the left and the rows on the right. */
@Composable
private fun Medium(face: StackWidgetFace, palette: WidgetPalette, height: Dp) {
    Row(GlanceModifier.fillMaxSize()) {
        Column(GlanceModifier.width(124.dp).fillMaxHeight()) {
            Header(face, palette)
            Spacer(GlanceModifier.defaultWeight())
            CounterBlock(face, palette, counterSize = 38)
        }
        Spacer(GlanceModifier.width(14.dp))
        Box(GlanceModifier.width(1.dp).fillMaxHeight().background(palette.line)) {}
        Spacer(GlanceModifier.width(14.dp))
        Box(GlanceModifier.defaultWeight().fillMaxHeight()) {
            // About 100 dp across: the code and the time, as the iPhone's Lock Screen rows; TalkBack reads the name.
            Rows(face, palette, height - 24.dp, divider = false, names = false)
        }
    }
}

/** 4x4: the counter block across the top, then as many rows as fit. */
@Composable
private fun Large(face: StackWidgetFace, palette: WidgetPalette, height: Dp) {
    Column(GlanceModifier.fillMaxSize()) {
        Header(face, palette)
        Spacer(GlanceModifier.height(8.dp))
        CounterBlock(face, palette, counterSize = 38)
        Spacer(GlanceModifier.height(10.dp))
        Box(GlanceModifier.fillMaxWidth().height(1.dp).background(palette.line)) {}
        // The rows share the height left, up to 60 dp each, so the 4x4 has no empty band under its last row.
        Rows(face, palette, height - 24.dp - LARGE_BLOCK - 11.dp, divider = false, names = true, spread = true)
    }
}

/** The 2x2 counter block's fixed height: header, counter, bar, TAKE ALL. */
private val TALL_BLOCK = 132.dp
private val LARGE_BLOCK = 150.dp

/** The mark, "TAKEN" and, while locked, the PRO mark. */
@Composable
private fun Header(face: StackWidgetFace, palette: WidgetPalette) {
    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        CapsuleMark(palette, 13.dp)
        Spacer(GlanceModifier.width(6.dp))
        Text(WidgetCopy.TAKEN, style = palette.mono(10f, palette.fg, FontWeight.Bold), maxLines = 1)
        Spacer(GlanceModifier.defaultWeight())
        if (face.locked) ProMark(palette)
    }
}

/** The small lock and PRO on a locked widget. */
@Composable
private fun ProMark(palette: WidgetPalette) {
    Row(
        GlanceModifier.background(palette.signalWash).rounded(palette.markRadius).padding(horizontal = 5.dp, vertical = 2.dp)
            .semantics { contentDescription = WidgetCopy.LOCK_MARK_SPOKEN },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Glyph(R.drawable.ic_widget_lock, palette.signalInk, 8.dp)
        Spacer(GlanceModifier.width(3.dp))
        Text(WidgetCopy.PRO, style = palette.mono(8.5f, palette.signalInk, FontWeight.Bold), maxLines = 1)
    }
}

/** "2/3": the taken part bright, the rest faint. */
@Composable
private fun Counter(face: StackWidgetFace, palette: WidgetPalette, size: Int) {
    Row(verticalAlignment = Alignment.Bottom) {
        Text(face.counterTaken, style = palette.mono(size.toFloat(), palette.fg, FontWeight.Medium), maxLines = 1)
        Text(face.counterDue, style = palette.mono(size.toFloat(), palette.fgFaint, FontWeight.Medium), maxLines = 1)
    }
}

/** One segment per due dose: lit in the signal, unlit as an inset well with a hairline. */
@Composable
private fun Bar(face: StackWidgetFace, palette: WidgetPalette, modifier: GlanceModifier = GlanceModifier.fillMaxWidth()) {
    Row(modifier.height(4.dp)) {
        for (index in 0 until face.segments) {
            val last = index == face.segments - 1
            Box(GlanceModifier.defaultWeight().fillMaxHeight().padding(end = if (last) 0.dp else 3.dp)) {
                if (index < face.litSegments) {
                    Box(GlanceModifier.fillMaxSize().background(palette.signal).rounded(palette.segmentRadius)) {}
                } else {
                    Box(GlanceModifier.fillMaxSize().background(palette.line).rounded(palette.segmentRadius).padding(1.dp)) {
                        Box(GlanceModifier.fillMaxSize().background(palette.bgInset).rounded(palette.segmentRadius)) {}
                    }
                }
            }
        }
    }
}

/** The counter (or ALL TAKEN, or the empty stack's words), the bar, and TAKE ALL or the status line. */
@Composable
private fun CounterBlock(face: StackWidgetFace, palette: WidgetPalette, counterSize: Int) {
    Column(GlanceModifier.fillMaxWidth().semantics { contentDescription = face.spoken }) {
        when {
            !face.hasStack -> {
                Text(WidgetCopy.EMPTY_TITLE, style = palette.hud(10f, palette.fgMuted), maxLines = 1)
                Spacer(GlanceModifier.height(4.dp))
                Text(WidgetCopy.EMPTY_HINT, style = palette.hud(9f, palette.fgFaint), maxLines = 1)
            }
            face.allTaken -> {
                Text(WidgetCopy.ALL_TAKEN, style = palette.mono(24f, palette.signalInk, FontWeight.Bold), maxLines = 2)
                Spacer(GlanceModifier.height(6.dp))
                Bar(face, palette)
                Spacer(GlanceModifier.height(4.dp))
                Bottom(face, palette)
            }
            else -> {
                Counter(face, palette, counterSize)
                Spacer(GlanceModifier.height(6.dp))
                Bar(face, palette)
                Spacer(GlanceModifier.height(10.dp))
                Bottom(face, palette)
            }
        }
    }
}

/** TAKE ALL, 48 dp tall (WL-4.2), or the status line instead of it. */
@Composable
private fun Bottom(face: StackWidgetFace, palette: WidgetPalette) {
    val context = LocalContext.current
    when (val bottom = face.bottom) {
        null -> Unit
        is WidgetBottom.TakeAll -> {
            var modifier = GlanceModifier.fillMaxWidth().height(WidgetSizes.TOUCH).background(palette.button).rounded(palette.panelRadius)
            com.tombaxter.taken.core.surfaces.WidgetTap.TakeAll.action(context)?.let { modifier = modifier.clickable(it) }
            Row(
                modifier.semantics {
                    contentDescription = if (bottom.count > 1) "Take all, ${bottom.count}" else "Take all"
                    testTag = "widget-take-all"
                },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Lamp(palette.buttonLamp, palette)
                Spacer(GlanceModifier.width(6.dp))
                Text(WidgetCopy.TAKE_ALL, style = palette.mono(11f, palette.buttonText, FontWeight.Bold), maxLines = 1)
                bottom.countText?.let {
                    Spacer(GlanceModifier.width(6.dp))
                    Text(it, style = palette.mono(11f, palette.buttonTextSoft, FontWeight.Medium), maxLines = 1)
                }
            }
        }
        is WidgetBottom.Status -> Row(GlanceModifier.fillMaxWidth().height(34.dp), verticalAlignment = Alignment.CenterVertically) {
            Lamp(if (bottom.lit) palette.signal else palette.fgFaint, palette)
            Spacer(GlanceModifier.width(6.dp))
            Text(bottom.text, style = palette.hud(9.5f, palette.fgMuted), maxLines = 1)
        }
    }
}

/**
 * The rows that fit in `height`, each 48 dp so every one is a full touch target (WL-4.2), and "+2 MORE" when some do not.
 * Glance holds ten children to a column, so each row carries its own divider.
 */
@Composable
private fun Rows(face: StackWidgetFace, palette: WidgetPalette, height: Dp, divider: Boolean, names: Boolean, spread: Boolean = false) {
    val fit = rowsFitting(height, face.rows.size)
    if (fit.shown == 0 && face.rows.isNotEmpty()) return
    val rowHeight = if (spread) spreadRowHeight(height, fit.shown, face.rows.size) else WidgetSizes.TOUCH
    Column(GlanceModifier.fillMaxWidth()) {
        if (face.rows.isEmpty()) {
            if (height >= WidgetSizes.TOUCH) {
                Box(GlanceModifier.fillMaxWidth().height(WidgetSizes.TOUCH), contentAlignment = Alignment.CenterStart) {
                    Text(face.emptyRows, style = palette.hud(10f, palette.fgSubtle), maxLines = 2)
                }
            }
            return@Column
        }
        face.rows.take(fit.shown).forEachIndexed { index, row ->
            RowLine(row, palette, topDivider = divider || index > 0, name = names, height = rowHeight)
        }
        face.more(fit.shown)?.let {
            Text(it, style = palette.hud(9f, palette.fgFaint), maxLines = 1, modifier = GlanceModifier.padding(top = 2.dp))
        }
    }
}

/**
 * A row's height when every row fits: the height left shared between them, never under the 48 dp touch target and at
 * most [SPREAD_MAX] [Own choice], so a large widget has no empty band under its last row. With a "+n MORE" line the rows
 * stay 48 dp.
 */
internal fun spreadRowHeight(height: Dp, shown: Int, count: Int): Dp {
    if (shown == 0 || shown < count) return WidgetSizes.TOUCH
    return (height / shown).coerceIn(WidgetSizes.TOUCH, SPREAD_MAX)
}

private val SPREAD_MAX = 60.dp

/** How many 48 dp rows fit, leaving room for the "+n MORE" line when not all of them do. */
internal data class RowFit(val shown: Int)

internal fun rowsFitting(height: Dp, count: Int): RowFit {
    val all = minOf((height.value / WidgetSizes.TOUCH.value).toInt().coerceAtLeast(0), MAX_ROWS)
    if (count <= all) return RowFit(count)
    val withMore = minOf(((height.value - MORE_LINE) / WidgetSizes.TOUCH.value).toInt().coerceAtLeast(0), MAX_ROWS)
    return RowFit(minOf(count, withMore))
}

private const val MORE_LINE = 16f

/** Glance holds ten children to a column: eight rows and the "+n MORE" line at most, on any screen. */
private const val MAX_ROWS = 8

/** One item: its mark, code, name and time or count; a tap logs it when it may. */
@Composable
private fun RowLine(row: WidgetRowFace, palette: WidgetPalette, topDivider: Boolean, name: Boolean, height: Dp = WidgetSizes.TOUCH) {
    val context = LocalContext.current
    var modifier = GlanceModifier.fillMaxWidth().height(height)
    row.tap.action(context)?.let { modifier = modifier.clickable(it) }
    Column(modifier.semantics { contentDescription = row.spoken; testTag = "widget-row-${row.code}" }) {
        if (topDivider) {
            Image(
                provider = ImageProvider(R.drawable.widget_dash),
                contentDescription = null,
                colorFilter = ColorFilter.tint(palette.lineDash),
                contentScale = ContentScale.FillBounds,
                modifier = GlanceModifier.fillMaxWidth().height(1.dp),
            )
        }
        Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            if (row.done) {
                Glyph(R.drawable.widget_dot, palette.signal, 9.dp)
            } else {
                Glyph(R.drawable.widget_ring_dashed, palette.fgFaint, 9.dp)
            }
            Spacer(GlanceModifier.width(8.dp))
            Text(
                row.code,
                style = palette.mono(11f, if (row.done) palette.signalInk else palette.fgMuted, FontWeight.Bold),
                maxLines = 1,
                modifier = GlanceModifier.width(34.dp),
            )
            if (name) {
                Text(
                    row.name,
                    style = palette.sans(12f, if (row.done) palette.fg else palette.fgMuted),
                    maxLines = 1,
                    modifier = GlanceModifier.defaultWeight(),
                )
            } else {
                Spacer(GlanceModifier.defaultWeight())
            }
            Spacer(GlanceModifier.width(4.dp))
            Text(
                row.value,
                style = if (row.valueLit) palette.mono(11f, palette.signalInk, FontWeight.Medium) else palette.hud(9f, palette.fgFaint),
                maxLines = 1,
            )
        }
    }
}
