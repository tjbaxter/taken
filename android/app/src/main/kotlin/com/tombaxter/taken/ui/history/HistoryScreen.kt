package com.tombaxter.taken.ui.history

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.Sheet
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.stack.Adherence
import com.tombaxter.taken.core.stack.DayStatus
import com.tombaxter.taken.core.stack.HistoryCell
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.drawCheck
import com.tombaxter.taken.ui.shell.TabHeader
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/**
 * History (SPEC 3.2): the streak and the last 30 days, then five weeks of days, Monday first, today in the bottom row. A
 * tap on a day opens it, to see when everything was taken or to log a dose that was forgotten.
 */
@Composable
fun HistoryScreen(model: AppModel) {
    val colors = Taken.colors
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.bg)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 28.dp)
            .testTag("history"),
    ) {
        TabHeader(model, title = "History", subtitle = "The last five weeks")
        if (model.hasStack || model.state.doses.isNotEmpty()) {
            Spacer(Modifier.height(22.dp))
            StatsRow(model.streak, model.adherence)
            Spacer(Modifier.height(16.dp))
            Card {
                Box(Modifier.padding(14.dp)) {
                    HistoryGrid(model.history) { day -> model.sheet = Sheet.Day(day) }
                }
            }
            Spacer(Modifier.height(12.dp))
            Text("Tap a day to see it, or to log a dose you forgot.", style = TakenType.sans(14), color = colors.fgSubtle)
            Spacer(Modifier.height(28.dp))
            Row(verticalAlignment = Alignment.Top) {
                Icon(Symbols.Lock, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                // Android wording (SPEC-ANDROID 6.4).
                Text("Your log stays on this phone. No account, no ads, no tracking.", style = TakenType.sans(14), color = colors.fgSubtle)
            }
        } else {
            Spacer(Modifier.height(28.dp))
            Text("Your days show up here once your stack is in.", style = TakenType.sans(16), color = colors.fgMuted)
        }
    }
}

/** Five weeks, Monday first, today in the last row. Lit = everything due was taken. */
@Composable
fun HistoryGrid(rows: List<List<HistoryCell>>, onSelect: (com.tombaxter.taken.core.day.DayKey) -> Unit) {
    val colors = Taken.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (letter in Fmt.weekdayLetters) {
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text(letter, style = TakenType.sans(12, FontWeight.Medium), color = colors.fgSubtle)
                }
            }
        }
        Spacer(Modifier.height(2.dp))
        for (week in rows) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (cell in week) {
                    DayCell(cell, Modifier.weight(1f)) { onSelect(cell.day) }
                }
            }
        }
    }
}

private fun spokenCell(cell: HistoryCell): String {
    val date = Fmt.longDay(cell.day)
    return when (cell.status) {
        DayStatus.COMPLETE -> "$date, all taken"
        DayStatus.PARTIAL -> "$date, partly taken"
        DayStatus.MISSED -> "$date, nothing taken"
        DayStatus.NOTHING_DUE -> "$date, nothing due"
        DayStatus.FUTURE -> "$date, upcoming"
    }
}

@Composable
private fun DayCell(cell: HistoryCell, modifier: Modifier, onClick: () -> Unit) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.cell)
    val future = cell.status == DayStatus.FUTURE
    val background = when (cell.status) {
        DayStatus.COMPLETE -> Modifier.background(colors.signalWash, shape).border(1.dp, colors.signalEdge, shape)
        DayStatus.FUTURE -> Modifier.border(1.dp, colors.line, shape)
        else -> Modifier.background(colors.bgInset, shape)
    }
    val today = if (cell.isToday) Modifier.border(1.5.dp, colors.fg, shape) else Modifier
    val numberColor = when {
        cell.isToday -> colors.fg
        cell.status == DayStatus.COMPLETE -> colors.signalInk
        future -> colors.fgFaint
        else -> colors.fgSubtle
    }
    Box(
        modifier
            .aspectRatio(1f)
            .clip(shape)
            .then(background)
            .then(today)
            .clickable(enabled = !future, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = spokenCell(cell)
                if (future) disabled()
            },
    ) {
        Text(
            "${cell.day.dayOfMonth}",
            style = TakenType.mono(9),
            color = numberColor,
            modifier = Modifier.padding(start = 5.dp, top = 3.dp).clearAndSetSemantics { },
        )
        Canvas(Modifier.fillMaxSize().clearAndSetSemantics { }) {
            val cx = size.width / 2
            val cy = size.height / 2 + 3.dp.toPx()
            when (cell.status) {
                DayStatus.COMPLETE -> {
                    val side = 16.dp.toPx()
                    drawCheck(colors.signalInk, side, 2.2.dp.toPx(), Offset(cx - side / 2, cy - side / 2))
                }
                DayStatus.PARTIAL -> drawRoundRect(
                    colors.signalInk.copy(alpha = 0.7f),
                    topLeft = Offset(cx - 5.5.dp.toPx(), cy - 1.5.dp.toPx()),
                    size = androidx.compose.ui.geometry.Size(11.dp.toPx(), 3.dp.toPx()),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.5.dp.toPx()),
                )
                DayStatus.MISSED, DayStatus.NOTHING_DUE -> drawCircle(colors.fgFaint, radius = 1.5.dp.toPx(), center = Offset(cx, cy))
                DayStatus.FUTURE -> Unit
            }
        }
    }
}

/** The streak and the last 30 days. */
@Composable
private fun StatsRow(streak: Int, adherence: Adherence) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Stat(
            label = "Streak", value = "$streak", unit = if (streak == 1) "day" else "days",
            spoken = "Streak, $streak ${if (streak == 1) "day" else "days"}", modifier = Modifier.weight(1f),
        )
        val percent = adherence.percent
        Stat(
            label = "Last 30 days", value = percent?.toString() ?: "--", unit = if (percent == null) "" else "%",
            spoken = if (percent != null) "Last 30 days, $percent percent taken" else "Last 30 days, nothing due yet",
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun Stat(label: String, value: String, unit: String, spoken: String, modifier: Modifier) {
    val colors = Taken.colors
    val shape = RoundedCornerShape(Taken.shapes.card)
    Column(
        modifier
            .background(colors.bgRaised, shape)
            .border(1.dp, colors.line, shape)
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .clearAndSetSemantics { contentDescription = spoken },
    ) {
        Text(label, style = TakenType.sans(14, FontWeight.Medium), color = colors.fgSubtle)
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value, style = TakenType.mono(28), color = colors.fg)
            Spacer(Modifier.width(if (unit == "%") 1.dp else 5.dp))
            Text(unit, style = TakenType.sans(16), color = colors.fgMuted, modifier = Modifier.padding(bottom = 3.dp))
        }
    }
}
