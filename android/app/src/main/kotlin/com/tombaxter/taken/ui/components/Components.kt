package com.tombaxter.taken.ui.components

import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/** A section title over a card: "Stack", "Not today". Geist, sentence case, nothing else. */
@Composable
fun SectionHeader(title: String, trailing: String? = null, modifier: Modifier = Modifier) {
    val colors = Taken.colors
    Row(
        modifier = modifier.fillMaxWidth().padding(top = 22.dp, bottom = 8.dp).semantics(mergeDescendants = true) { heading() },
        verticalAlignment = Alignment.Bottom,
    ) {
        Text(title, style = TakenType.sans(15, FontWeight.SemiBold), color = colors.fgMuted)
        Spacer(Modifier.weight(1f))
        if (trailing != null) Text(trailing, style = TakenType.sans(14), color = colors.fgSubtle)
    }
}

/** A raised surface with a hairline edge and the look's corners: the list cards on Today, History and the sheets. */
@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    Box(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.bgRaised, shape)
            .border(1.dp, colors.line, shape),
    ) { content() }
}

/** A hairline between rows in a card. */
@Composable
fun RowDivider(inset: Dp = 16.dp) {
    Box(Modifier.fillMaxWidth().padding(start = inset).height(1.dp).background(Taken.colors.line))
}

/** The solid button: light on the dark looks, ink on Blush. A count after the title in Geist Mono: "Take all 2". */
@Composable
fun PrimaryButton(
    title: String,
    modifier: Modifier = Modifier,
    locked: Boolean = false,
    enabled: Boolean = true,
    count: Int? = null,
    onClick: () -> Unit,
) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .clip(shape)
            .background(colors.button.copy(alpha = if (enabled) 1f else 0.28f), shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (locked) {
            Icon(Symbols.LockFill, contentDescription = null, tint = colors.buttonText, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(title, style = TakenType.sans(17, FontWeight.SemiBold), color = colors.buttonText)
        if (count != null) {
            Spacer(Modifier.width(8.dp))
            Text("$count", style = TakenType.mono(16), color = colors.buttonText.copy(alpha = 0.7f))
        }
    }
}

/** An outline button for secondary and destructive actions. */
@Composable
fun OutlineButton(title: String, modifier: Modifier = Modifier, color: Color? = null, onClick: () -> Unit) {
    val ink = color ?: Taken.colors.fg
    val shape = RoundedCornerShape(Taken.shapes.card)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(shape)
            .border(1.dp, ink.copy(alpha = 0.45f), shape)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = TakenType.sans(16, FontWeight.SemiBold), color = ink)
    }
}

/** Title bar for sheets: a title, an optional line under it, and Close. */
@Composable
fun SheetHeader(title: String, subtitle: String? = null, subtitleColor: Color? = null, onClose: () -> Unit) {
    val colors = Taken.colors
    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f).padding(top = 6.dp).semantics(mergeDescendants = true) { heading() }) {
            Text(title, style = TakenType.sans(22, FontWeight.SemiBold), color = colors.fg)
            if (subtitle != null) {
                Spacer(Modifier.height(4.dp))
                Text(subtitle, style = TakenType.sans(15), color = subtitleColor ?: colors.fgSubtle)
            }
        }
        CloseButton(onClose)
    }
}

/** A 32 dp close disc in a 48 dp target, TalkBack "Close". */
@Composable
fun CloseButton(onClick: () -> Unit) {
    val colors = Taken.colors
    Box(
        Modifier
            .minimumInteractiveComponentSize()
            .size(48.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = "Close" },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(32.dp).background(colors.bgInset, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Symbols.Close, contentDescription = null, tint = colors.fgMuted, modifier = Modifier.size(18.dp))
        }
    }
}

/** A check mark, drawn as the iPhone's CheckShape. */
fun DrawScope.drawCheck(color: Color, side: Float, strokeWidth: Float, origin: Offset = Offset.Zero) {
    val path = Path().apply {
        moveTo(origin.x + side * 0.20f, origin.y + side * 0.53f)
        lineTo(origin.x + side * 0.42f, origin.y + side * 0.74f)
        lineTo(origin.x + side * 0.80f, origin.y + side * 0.30f)
    }
    drawPath(path, color, style = Stroke(width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round))
}

/** The Taken mark: a split capsule, one half lit, one half outlined, set at 45 degrees. */
@Composable
fun CapsuleGlyph(modifier: Modifier = Modifier, fill: Color? = null, stroke: Color? = null) {
    val lit = fill ?: Taken.colors.signal
    val outline = stroke ?: Taken.colors.fgMuted
    Canvas(modifier.rotate(-45f)) {
        val side = minOf(size.width, size.height)
        val width = side * 0.98f
        val height = side * 0.44f
        val lineWidth = maxOf(1f, side * 0.075f)
        val gap = maxOf(1f, side * 0.05f)
        val half = (width - gap) / 2
        val left = (size.width - width) / 2
        val top = (size.height - height) / 2
        val radius = CornerRadius(height / 2, height / 2)
        clipRect(left = left, top = top, right = left + half, bottom = top + height) {
            drawRoundRect(lit, topLeft = Offset(left, top), size = Size(width, height), cornerRadius = radius)
        }
        clipRect(left = left + half + gap, top = top, right = left + width, bottom = top + height) {
            drawRoundRect(
                outline,
                topLeft = Offset(left + lineWidth / 2, top + lineWidth / 2),
                size = Size(width - lineWidth, height - lineWidth),
                cornerRadius = CornerRadius((height - lineWidth) / 2, (height - lineWidth) / 2),
                style = Stroke(lineWidth),
            )
            drawRect(outline, topLeft = Offset(left + half + gap, top), size = Size(lineWidth, height))
        }
    }
}

/** A slim bar that fills with the day: at least 6 dp once above 0. */
@Composable
fun ProgressBar(fraction: Float, modifier: Modifier = Modifier) {
    val colors = Taken.colors
    val value = fraction.coerceIn(0f, 1f)
    Canvas(modifier.fillMaxWidth().height(6.dp)) {
        val radius = CornerRadius(size.height / 2, size.height / 2)
        drawRoundRect(colors.bgInset, cornerRadius = radius)
        if (value > 0f) {
            val width = maxOf(6.dp.toPx(), size.width * value)
            drawRoundRect(colors.signal, size = Size(width, size.height), cornerRadius = radius)
        }
    }
}

/** Seven weekday toggles, Monday first (Calendar numbering: 1 = Sunday). Weekly picks one. */
@Composable
fun WeekdayPicker(selection: Set<Int>, single: Boolean = false, onChange: (Set<Int>) -> Unit) {
    val colors = Taken.colors
    val order = listOf(2, 3, 4, 5, 6, 7, 1)
    val names = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    val letters = listOf("M", "T", "W", "T", "F", "S", "S")
    val shape = RoundedCornerShape(Taken.shapes.cell)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        order.forEachIndexed { index, weekday ->
            val on = selection.contains(weekday)
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = 48.dp)
                    .clip(shape)
                    .background(if (on) colors.button else colors.bgInset, shape)
                    .clickable(role = Role.Checkbox, onClickLabel = names[index]) {
                        onChange(
                            when {
                                single -> setOf(weekday)
                                on -> selection - weekday
                                else -> selection + weekday
                            },
                        )
                    }
                    .semantics {
                        contentDescription = names[index] + if (on) ", selected" else ""
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(letters[index], style = TakenType.sans(14, FontWeight.SemiBold), color = if (on) colors.buttonText else colors.fgMuted)
            }
        }
    }
}

/** A plain row with a title and something on the right, at least 48 dp tall. */
@Composable
fun SettingRow(title: String, modifier: Modifier = Modifier, trailing: @Composable () -> Unit) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = TakenType.sans(17), color = Taken.colors.fg, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
        trailing()
    }
}

/** The profile photo in a circle, or the initials, or a person when there is neither. */
@Composable
fun AvatarImage(initials: String?, photo: androidx.compose.ui.graphics.ImageBitmap?, size: Dp, modifier: Modifier = Modifier) {
    val colors = Taken.colors
    Box(
        modifier.size(size).clip(CircleShape).background(colors.bgInset).border(1.dp, colors.lineStrong, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        when {
            photo != null -> androidx.compose.foundation.Image(
                bitmap = photo, contentDescription = null, modifier = Modifier.size(size),
                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
            )
            initials != null -> Text(
                initials,
                style = TakenType.sans((size.value * 0.38f).toInt().coerceAtLeast(10), FontWeight.SemiBold),
                color = colors.fg,
            )
            else -> Icon(Symbols.PersonFill, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(size * 0.5f))
        }
    }
}

/** A small text button in the signal's ink, 48 dp tall. */
@Composable
fun InkButton(title: String, modifier: Modifier = Modifier, weight: FontWeight = FontWeight.Medium, onClick: () -> Unit) {
    Box(
        modifier
            .heightIn(min = 48.dp)
            .widthIn(min = 48.dp)
            .clip(RoundedCornerShape(Taken.shapes.cell))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = TakenType.sans(15, weight), color = Taken.colors.signalInk)
    }
}
