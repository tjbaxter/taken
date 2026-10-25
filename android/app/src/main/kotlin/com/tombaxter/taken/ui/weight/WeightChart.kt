package com.tombaxter.taken.ui.weight

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.WeightPicture
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.weight.WeightAxis
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightFormat
import com.tombaxter.taken.core.weight.WeightGoalCopy
import com.tombaxter.taken.core.weight.WeightMoment
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.core.weight.noon
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenColors
import com.tombaxter.taken.ui.theme.TakenType
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * The weight chart (SPEC 3.12, SPEC-ANDROID 12), ported from Taken/Weight/WeightChart.swift and drawn on a Compose
 * Canvas (https://developer.android.com/develop/ui/compose/graphics/draw/overview), the plot fixed at 196 dp: each
 * weigh-in a small dot in the look's subtle ink, the trend a smooth line in the look's signal colour through a monotone
 * cubic (Fritsch and Carlson, so the curve never swings past the values it joins, as Swift Charts' `.monotone`), a small
 * unlabelled tick on the baseline on each day a weekly dose was logged, and a y axis fitted to what is in view, never from
 * zero. With a goal: one quiet solid line at the goal, its number on the trailing axis one step brighter than the other
 * labels (or pinned to the top or bottom edge with an arrow when it is far off the data), and at most three lit points on
 * the trend, the newest percent point labelled "−5%" or "−10%". A press scrubs: the day's trend, weigh-in and point. No
 * stars, badges, dashed lines, forecast, BMI, red or green. TalkBack gets the chart's summary and one node per weigh-in,
 * dose tick, the goal line and each lit point.
 */
@Composable
internal fun WeightChart(model: AppModel, picture: WeightPicture, unit: WeightUnit, locale: Locale) {
    val colors = Taken.colors
    val window = picture.window
    val goalKg = model.weight.goal?.kg
    val today = model.today.day
    val summary = buildList {
        add(WeightCopy.spokenTrend(picture.trend.lastOrNull()?.kg, unit, locale))
        val readout = picture.readout
        if (goalKg != null && readout != null) add(WeightGoalCopy.spokenSlot(readout, goalKg, unit, locale) + ".")
        picture.change?.let { add(WeightGoalCopy.spokenChange(it.kg, it.span, unit, today, locale) + ".") }
        WeightGoalCopy.marked(picture.momentsInView)?.let { add(it) }
    }.joinToString(" ")
    if (window.isEmpty) {
        Box(
            Modifier.fillMaxWidth().height(PLOT_HEIGHT + 24.dp).semantics { contentDescription = "Weight chart. $summary" },
            contentAlignment = Alignment.Center,
        ) { Text(WeightCopy.EMPTY_RANGE, style = TakenType.sans(15), color = colors.fgSubtle) }
        return
    }
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val labelStyle = TakenType.mono(11, FontWeight.Medium)
    var selected by remember(window) { mutableStateOf<DayKey?>(null) }
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .semantics { contentDescription = "Weight chart. $summary" }
            .testTag("weight-chart"),
    ) {
        val geometry = remember(window, unit, goalKg, constraints.maxWidth, density, locale) {
            ChartGeometry.make(picture, unit, goalKg, constraints.maxWidth.toFloat(), density.density, measurer, labelStyle, locale, model.clock)
        }
        val height = with(density) { geometry.height.toDp() }
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(height)
                .pointerInput(geometry) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        if (!geometry.plot.contains(down.position)) return@awaitEachGesture
                        selected = geometry.nearestDay(down.position.x)
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            val moved = change.position - down.position
                            // A vertical drag is the page's: the scrub lets go and the page scrolls.
                            if (abs(moved.y) > viewConfiguration.touchSlop && abs(moved.y) > abs(moved.x)) break
                            if (abs(moved.x) > viewConfiguration.touchSlop) change.consume()
                            selected = geometry.nearestDay(change.position.x)
                        }
                        selected = null
                    }
                },
        ) {
            drawChart(geometry, picture, colors, measurer, labelStyle, unit, goalKg, locale, today, selected)
        }
        // TalkBack: one node per weigh-in, dose tick, the goal line and each lit point, where it sits on the chart.
        val nodeSize = 24.dp
        val half = with(density) { (nodeSize / 2).roundToPx() }
        Box(Modifier.matchParentSizeOf(height)) {
            for (tick in window.ticks) {
                val x = geometry.x(tick)
                ChartNode("${Fmt.longDay(tick)}, Weekly dose", IntOffset(x.roundToInt() - half, geometry.plot.bottom.roundToInt() - half * 2), nodeSize)
            }
            if (goalKg != null && geometry.goalShown) {
                ChartNode(
                    "${WeightGoalCopy.GOAL_LINE}, ${WeightGoalCopy.goalValue(goalKg, unit, locale)}",
                    IntOffset(geometry.plot.right.roundToInt() - half * 2, geometry.y(unit.valueFromKilograms(goalKg)).roundToInt() - half),
                    nodeSize,
                )
            }
            for (dot in window.dots) {
                ChartNode(
                    "${Fmt.longDay(dot.day)}, ${WeightFormat.spoken(dot.kg, unit, locale)}",
                    IntOffset(geometry.x(dot.day).roundToInt() - half, geometry.y(unit.valueFromKilograms(dot.kg)).roundToInt() - half),
                    nodeSize,
                )
            }
            for (moment in picture.momentsInView) {
                ChartNode(
                    "${WeightGoalCopy.pointLabel(moment)}, ${WeightGoalCopy.pointValue(moment, unit, locale)}",
                    IntOffset(geometry.x(moment.day).roundToInt() - half, geometry.y(unit.valueFromKilograms(moment.trendKg)).roundToInt() - half),
                    nodeSize,
                )
            }
        }
    }
}

/** A box as tall as the chart, over it, for TalkBack's nodes. */
private fun Modifier.matchParentSizeOf(height: androidx.compose.ui.unit.Dp): Modifier = fillMaxWidth().height(height)

@Composable
private fun ChartNode(text: String, at: IntOffset, size: androidx.compose.ui.unit.Dp) {
    Box(Modifier.offset { at }.size(size).clearAndSetSemantics { contentDescription = text })
}

private val PLOT_HEIGHT = 196.dp

/** Where everything sits, in pixels: the plot, the y axis in the unit shown, the ticks and the x labels. */
private class ChartGeometry(
    val plot: androidx.compose.ui.geometry.Rect,
    val height: Float,
    val lower: Double,
    val upper: Double,
    val goal: Double?,
    val goalShown: Boolean,
    /** The goal far off the data: pinned to the top (true) or the bottom (false). */
    val pinnedTop: Boolean?,
    val ticks: List<Double>,
    val decimals: Int,
    val xTicks: List<DayKey>,
    val xMonths: Boolean,
    private val startMillis: Long,
    private val endMillis: Long,
    private val noons: (DayKey) -> Long,
    val trendDays: List<DayKey>,
) {
    fun x(day: DayKey): Float {
        val span = (endMillis - startMillis).coerceAtLeast(1L).toFloat()
        return plot.left + (noons(day) - startMillis) / span * plot.width
    }

    /** A value in the unit shown. */
    fun y(value: Double): Float = plot.bottom - ((value - lower) / (upper - lower)).toFloat() * plot.height

    /** The trend day nearest the finger. */
    fun nearestDay(px: Float): DayKey? = trendDays.minByOrNull { abs(x(it) - px) }

    companion object {
        fun make(
            picture: WeightPicture,
            unit: WeightUnit,
            goalKg: Double?,
            width: Float,
            density: Float,
            measurer: TextMeasurer,
            labelStyle: TextStyle,
            locale: Locale,
            clock: com.tombaxter.taken.core.day.DayClock,
        ): ChartGeometry {
            val window = picture.window
            val plotHeight = 196f * density
            val lower = unit.valueFromKilograms(window.lower)
            val upper = unit.valueFromKilograms(window.upper)
            val goal = goalKg?.let { unit.valueFromKilograms(it) }
            val all = WeightAxis.ticks(lower, upper)
            var ticks = all
            var pinnedTop: Boolean? = null
            if (goal != null) {
                ticks = if (window.goalInDomain) {
                    WeightAxis.clear(ticks, goal, lower, upper, 196.0)
                } else {
                    val top = goal > upper
                    pinnedTop = top
                    // The pinned label sits 8 inside the edge.
                    val inset = 8.0 / 196.0 * (upper - lower)
                    WeightAxis.clear(ticks, if (top) upper - inset else lower + inset, lower, upper, 196.0)
                }
            }
            val decimals = WeightAxis.decimals(all)
            // The trailing axis is as wide as its widest label, and 6 apart from the plot.
            val labels = ticks.map { WeightFormat.decimal(it, decimals, decimals, locale) } +
                listOfNotNull(goalKg?.let { WeightGoalCopy.goal(it, unit, locale) })
            val axisWidth = (labels.maxOfOrNull { measurer.measure(it, labelStyle).size.width } ?: 0) + 6f * density
            val xLabelHeight = measurer.measure("0", labelStyle).size.height + 4f * density
            val plot = androidx.compose.ui.geometry.Rect(0f, 0f, (width - axisWidth).coerceAtLeast(1f), plotHeight)
            val (xTicks, months) = xTicks(window.firstDay, window.lastDay)
            return ChartGeometry(
                plot = plot,
                height = plotHeight + xLabelHeight,
                lower = lower,
                upper = upper,
                goal = goal,
                goalShown = goal != null && window.goalInDomain,
                pinnedTop = pinnedTop,
                ticks = ticks,
                decimals = decimals,
                xTicks = xTicks,
                xMonths = months,
                startMillis = clock.start(window.firstDay).toEpochMilli(),
                endMillis = clock.end(window.lastDay).toEpochMilli(),
                noons = { clock.noon(it).toEpochMilli() },
                trendDays = window.trend.map { it.day }.ifEmpty { window.dots.map { it.day } },
            )
        }

        /**
         * About four x labels [Own choice: Swift Charts' automatic marks are not documented]: days counted back from the
         * last day while the window spans two months or less ("21 Oct"), else the first of every month, every 2, 3, 6 or
         * 12 months ("Oct"), as the iPhone switches to months past 62 days so a short All never reads "Oct Oct Oct".
         */
        fun xTicks(first: DayKey, last: DayKey): Pair<List<DayKey>, Boolean> {
            val span = first.distanceTo(last)
            if (span <= 62) {
                for (step in listOf(1, 2, 3, 7, 14, 21, 28, 35)) {
                    if (span / step + 1 <= 4) return (0..span step step).map { last.adding(-it) }.reversed() to false
                }
                return listOf(last) to false
            }
            val firsts = mutableListOf<DayKey>()
            var (year, month, _) = first.ymd
            while (true) {
                val day = DayKey(year, month, 1)
                if (day > last) break
                if (day >= first) firsts.add(day)
                month += 1
                if (month > 12) {
                    month = 1
                    year += 1
                }
            }
            for (step in listOf(1, 2, 3, 6, 12, 24, 60)) {
                val chosen = firsts.filter { (it.ymd.year * 12 + it.ymd.month - 1) % step == 0 }
                if (chosen.size <= 4) return chosen to true
            }
            return firsts.take(1) to true
        }
    }
}

private fun DrawScope.drawChart(
    geometry: ChartGeometry,
    picture: WeightPicture,
    colors: TakenColors,
    measurer: TextMeasurer,
    labelStyle: TextStyle,
    unit: WeightUnit,
    goalKg: Double?,
    locale: Locale,
    today: DayKey,
    selected: DayKey?,
) {
    val window = picture.window
    val plot = geometry.plot
    val hairline = 1.dp.toPx()

    // The x grid and its labels: days, or months past 62 days.
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, if (geometry.xMonths) "MMM" else "dMMM")
    val formatter = DateTimeFormatter.ofPattern(pattern, locale)
    for (day in geometry.xTicks) {
        val x = geometry.x(day)
        drawLine(colors.line, Offset(x, plot.top), Offset(x, plot.bottom), hairline)
        val (y, m, d) = day.ymd
        val text = measurer.measure(formatter.format(LocalDate.of(y, m, d)), labelStyle.copy(color = colors.fgSubtle))
        val left = x.coerceIn(plot.left, (plot.right - text.size.width).coerceAtLeast(plot.left))
        drawText(text, topLeft = Offset(left, plot.bottom + 4.dp.toPx()))
    }
    // The y grid and its labels on the trailing side, never one too close to the goal's own label.
    for (tick in geometry.ticks) {
        val y = geometry.y(tick)
        drawLine(colors.line, Offset(plot.left, y), Offset(plot.right, y), hairline)
        val text = measurer.measure(WeightFormat.decimal(tick, geometry.decimals, geometry.decimals, locale), labelStyle.copy(color = colors.fgSubtle))
        drawText(text, topLeft = Offset(plot.right + 6.dp.toPx(), y - text.size.height / 2f))
    }
    // Weekly dose ticks on the baseline: unlabelled, never a drug name.
    val tickTop = geometry.y(geometry.lower + (geometry.upper - geometry.lower) * 0.05)
    for (day in window.ticks) {
        val x = geometry.x(day)
        drawLine(colors.fgSubtle, Offset(x, plot.bottom), Offset(x, tickTop), 1.25.dp.toPx(), cap = StrokeCap.Round)
    }
    // One quiet solid line at the goal: never dashed, never green, no flag. Its number one step brighter, with no grid.
    val goal = geometry.goal
    if (goal != null && goalKg != null) {
        if (geometry.goalShown) {
            val y = geometry.y(goal)
            drawLine(colors.fgFaint, Offset(plot.left, y), Offset(plot.right, y), hairline)
            val text = measurer.measure(WeightGoalCopy.goal(goalKg, unit, locale), labelStyle.copy(color = colors.fgMuted))
            drawText(text, topLeft = Offset(plot.right + 6.dp.toPx(), y - text.size.height / 2f))
        } else {
            geometry.pinnedTop?.let { top -> drawPinnedGoal(top, WeightGoalCopy.goal(goalKg, unit, locale), plot, measurer, labelStyle, colors) }
        }
    }
    // The weigh-ins: small dots in the subtle ink (Swift Charts' symbol size 22, a circle about 5.3 across).
    val dotRadius = 2.65.dp.toPx()
    for (dot in window.dots) {
        drawCircle(colors.fgSubtle, dotRadius, Offset(geometry.x(dot.day), geometry.y(unit.valueFromKilograms(dot.kg))))
    }
    // The trend: one smooth line in the signal colour.
    val points = window.trend.map { Offset(geometry.x(it.day), geometry.y(unit.valueFromKilograms(it.kg))) }
    if (points.size >= 2) {
        drawPath(
            monotonePath(points), colors.signal,
            style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
    }
    // The lit points, always drawn lit (the moment plays on screen one), each a bead that cuts the line.
    val inView = picture.momentsInView
    for (moment in inView) {
        drawLitBead(Offset(geometry.x(moment.day), geometry.y(unit.valueFromKilograms(moment.trendKg))), colors)
    }
    // The one label: on the newest point in view if it is 5% or 10%, and never once the goal is reached.
    val newest = inView.lastOrNull()
    val label = if (picture.moments.any { it.isGoal } || newest == null) null else WeightGoalCopy.chartLabel(newest)
    if (newest != null && label != null) {
        val text = measurer.measure(label, labelStyle.copy(color = colors.fgMuted))
        val x = geometry.x(newest.day)
        val y = geometry.y(unit.valueFromKilograms(newest.trendKg))
        // 8 right of and 12 above the point, flipped left or below if it would leave the plot.
        val right = x + 8.dp.toPx() + text.size.width <= plot.right
        val above = y - 12.dp.toPx() - text.size.height / 2f >= plot.top
        val left = if (right) x + 8.dp.toPx() else x - 8.dp.toPx() - text.size.width
        val centreY = if (above) y - 12.dp.toPx() else y + 12.dp.toPx()
        drawText(text, topLeft = Offset(left, centreY - text.size.height / 2f))
    }
    // The scrub: a rule on the day and its popover above the plot.
    if (selected != null) {
        val x = geometry.x(selected)
        drawLine(colors.lineStrong, Offset(x, plot.top), Offset(x, plot.bottom), hairline)
        drawPopover(selected, x, picture, geometry, colors, measurer, unit, goalKg, locale, today)
    }
}

private fun DrawScope.drawPinnedGoal(top: Boolean, text: String, plot: androidx.compose.ui.geometry.Rect, measurer: TextMeasurer, style: TextStyle, colors: TakenColors) {
    val measured = measurer.measure(text, style.copy(color = colors.fgMuted))
    val right = size.width
    val centreY = if (top) plot.top + 8.dp.toPx() else plot.bottom - 8.dp.toPx()
    val textLeft = right - measured.size.width
    drawText(measured, topLeft = Offset(textLeft, centreY - measured.size.height / 2f))
    // A small arrow before the number, pointing to where the goal lies.
    val arrowX = textLeft - 2.dp.toPx() - 3.dp.toPx()
    val h = 3.5.dp.toPx()
    val path = Path().apply {
        if (top) {
            moveTo(arrowX, centreY + h)
            lineTo(arrowX, centreY - h)
            moveTo(arrowX - 2.5.dp.toPx(), centreY - h + 2.5.dp.toPx())
            lineTo(arrowX, centreY - h)
            lineTo(arrowX + 2.5.dp.toPx(), centreY - h + 2.5.dp.toPx())
        } else {
            moveTo(arrowX, centreY - h)
            lineTo(arrowX, centreY + h)
            moveTo(arrowX - 2.5.dp.toPx(), centreY + h - 2.5.dp.toPx())
            lineTo(arrowX, centreY + h)
            lineTo(arrowX + 2.5.dp.toPx(), centreY + h - 2.5.dp.toPx())
        }
    }
    drawPath(path, colors.fgMuted, style = Stroke(width = 1.2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
}

/** A lit point on the line: a 12 dp circle in the card's colour, the glow, and the 8 dp signal dot. */
private fun DrawScope.drawLitBead(at: Offset, colors: TakenColors) {
    drawCircle(colors.bgRaised, 6.dp.toPx(), at)
    drawCircle(Brush.radialGradient(listOf(colors.glow(0.35f), Color.Transparent), at, 8.dp.toPx()), 8.dp.toPx(), at)
    drawCircle(colors.signal, 4.dp.toPx(), at)
}

/** "3 Aug", the trend, the day's weigh-in and, on a point's day, its fact, on the inset surface with a strong hairline. */
private fun DrawScope.drawPopover(
    day: DayKey,
    x: Float,
    picture: WeightPicture,
    geometry: ChartGeometry,
    colors: TakenColors,
    measurer: TextMeasurer,
    unit: WeightUnit,
    goalKg: Double?,
    locale: Locale,
    today: DayKey,
) {
    val window = picture.window
    val trend = window.trend.firstOrNull { it.day == day }
    val weighIn = window.dots.filter { it.day == day }.minOfOrNull { it.kg }
    val moment: WeightMoment? = picture.moments.firstOrNull { it.day == day }
    val lines = mutableListOf<List<TextLayoutResult>>()
    lines += listOf(measurer.measure(WeightGoalCopy.shortDay(day, today), TakenType.sans(12).copy(color = colors.fgSubtle)))
    if (trend != null) {
        lines += listOf(
            measurer.measure(WeightGoalCopy.TREND + " ", TakenType.sans(12).copy(color = colors.fgMuted)),
            measurer.measure(WeightFormat.trend(trend.kg, unit, locale), TakenType.mono(15, FontWeight.Medium).copy(color = colors.fg)),
        )
    }
    if (weighIn != null) {
        lines += listOf(measurer.measure("${WeightGoalCopy.WEIGH_IN} ${WeightFormat.value(weighIn, unit, locale)}", TakenType.mono(13, FontWeight.Medium).copy(color = colors.fgMuted)))
    }
    if (moment != null && goalKg != null) {
        lines += listOf(measurer.measure(WeightGoalCopy.pointFact(moment, goalKg, unit, locale), TakenType.sans(12).copy(color = colors.signalInk)))
    }
    val padX = 8.dp.toPx()
    val padY = 6.dp.toPx()
    val gap = 2.dp.toPx()
    val width = lines.maxOf { row -> row.sumOf { it.size.width } } + padX * 2
    val height = lines.sumOf { row -> row.maxOf { it.size.height } }.toFloat() + gap * (lines.size - 1) + padY * 2
    val left = (x - width / 2).coerceIn(0f, (size.width - width).coerceAtLeast(0f))
    val top = geometry.plot.top - height
    val radius = CornerRadius(7.dp.toPx(), 7.dp.toPx())
    drawRoundRect(colors.bgInset, Offset(left, top), Size(width, height), radius)
    drawRoundRect(colors.lineStrong, Offset(left, top), Size(width, height), radius, style = Stroke(1.dp.toPx()))
    var y = top + padY
    for (row in lines) {
        val rowHeight = row.maxOf { it.size.height }
        var cx = left + padX
        for (part in row) {
            drawText(part, topLeft = Offset(cx, y + (rowHeight - part.size.height)))
            cx += part.size.width
        }
        y += rowHeight + gap
    }
}

/**
 * A monotone cubic through the points (Fritsch and Carlson 1980, "Monotone Piecewise Cubic Interpolation"): tangents
 * averaged from the neighbouring slopes, zero at a turn, and scaled back where they would overshoot, as cubic Béziers.
 */
internal fun monotonePath(points: List<Offset>): Path {
    val path = Path()
    if (points.isEmpty()) return path
    path.moveTo(points[0].x, points[0].y)
    if (points.size == 1) return path
    val n = points.size
    val slopes = FloatArray(n - 1) { i ->
        val dx = points[i + 1].x - points[i].x
        if (dx == 0f) 0f else (points[i + 1].y - points[i].y) / dx
    }
    val tangents = FloatArray(n)
    tangents[0] = slopes[0]
    tangents[n - 1] = slopes[n - 2]
    for (i in 1 until n - 1) {
        tangents[i] = if (slopes[i - 1] * slopes[i] <= 0f) 0f else (slopes[i - 1] + slopes[i]) / 2f
    }
    for (i in 0 until n - 1) {
        if (slopes[i] == 0f) {
            tangents[i] = 0f
            tangents[i + 1] = 0f
            continue
        }
        val a = tangents[i] / slopes[i]
        val b = tangents[i + 1] / slopes[i]
        val h = a * a + b * b
        if (h > 9f) {
            val t = 3f / sqrt(h)
            tangents[i] = t * a * slopes[i]
            tangents[i + 1] = t * b * slopes[i]
        }
    }
    for (i in 0 until n - 1) {
        val p0 = points[i]
        val p1 = points[i + 1]
        val third = (p1.x - p0.x) / 3f
        path.cubicTo(p0.x + third, p0.y + tangents[i] * third, p1.x - third, p1.y - tangents[i + 1] * third, p1.x, p1.y)
    }
    return path
}

/**
 * W, 30D, 90D, Y and All as Material's single-choice segmented buttons in the look's own tokens (SPEC-ANDROID 6.3): the
 * chosen range on the inset surface, the rest in subtle ink, no check icon. TalkBack reads each as a radio button with
 * the iPhone's spoken names ("Week", "30 days").
 */
@Composable
internal fun RangePicker(selection: WeightRange, onSelect: (WeightRange) -> Unit) {
    val colors = Taken.colors
    val ranges = WeightRange.entries
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("weight-ranges")) {
        ranges.forEachIndexed { index, range ->
            SegmentedButton(
                selected = range == selection,
                onClick = { onSelect(range) },
                shape = SegmentedButtonDefaults.itemShape(index, ranges.size, androidx.compose.foundation.shape.RoundedCornerShape(Taken.shapes.cell)),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = colors.bgInset,
                    activeContentColor = colors.fg,
                    activeBorderColor = colors.lineStrong,
                    inactiveContainerColor = colors.bg,
                    inactiveContentColor = colors.fgSubtle,
                    inactiveBorderColor = colors.line,
                ),
                icon = {},
                modifier = Modifier.semantics { contentDescription = range.spoken }.testTag("range-${range.raw}"),
                label = {
                    BasicText(
                        range.label,
                        style = TakenType.mono(13, FontWeight.Medium).copy(
                            color = if (range == selection) colors.fg else colors.fgSubtle, textAlign = TextAlign.Center,
                        ),
                        maxLines = 1,
                        softWrap = false,
                        autoSize = TextAutoSize.StepBased(minFontSize = 8.sp, maxFontSize = 13.sp),
                        modifier = Modifier.clearAndSetSemantics { },
                    )
                },
            )
        }
    }
}
