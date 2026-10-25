package com.tombaxter.taken.ui.profile

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.core.theme.Looks
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.ui.components.CapsuleGlyph
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenColors
import com.tombaxter.taken.ui.theme.TakenType

/**
 * Four looks side by side (the iPhone's LookPicker): each a live miniature in its own tokens (the glyph, a 66% bar, one
 * taken and one pending mini row), its name under it, the chosen one ringed in the current look's signal. A tap
 * recolours the app with a 0.3 s crossfade. TalkBack: "Blush look", selected.
 */
@Composable
fun LookPicker(selection: ThemeID, onSelect: (ThemeID) -> Unit) {
    val current = Taken.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (look in Looks.ALL) {
            val chosen = look.id == selection
            val swatch = TakenColors.of(look)
            Column(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(14.dp))
                    .clickable(role = Role.RadioButton, onClickLabel = "apply") { onSelect(look.id) }
                    .semantics(mergeDescendants = true) {
                        contentDescription = "${look.id.title} look"
                        selected = chosen
                        if (!chosen) stateDescription = ProfileCopy.LOOK_HINT
                    }
                    .padding(vertical = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .then(if (chosen) Modifier.border(2.dp, current.signal, RoundedCornerShape(15.dp)) else Modifier)
                        .padding(3.dp),
                ) {
                    Preview(swatch)
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    look.id.title,
                    style = TakenType.sans(13, if (chosen) FontWeight.SemiBold else FontWeight.Medium),
                    color = if (chosen) current.fg else current.fgSubtle,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun Preview(look: TakenColors) {
    val shape = RoundedCornerShape(12.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .height(92.dp)
            .background(look.bg, shape)
            .border(1.dp, look.lineStrong, shape)
            .padding(9.dp),
    ) {
        CapsuleGlyph(Modifier.size(14.dp), fill = look.signal, stroke = look.fgMuted)
        Spacer(Modifier.weight(1f))
        Canvas(Modifier.fillMaxWidth().height(4.dp)) {
            val radius = CornerRadius(size.height / 2, size.height / 2)
            drawRoundRect(look.bgInset, cornerRadius = radius)
            drawRoundRect(look.signal, size = Size(size.width * 0.66f, size.height), cornerRadius = radius)
        }
        Spacer(Modifier.height(7.dp))
        MiniRow(look, taken = true)
        Spacer(Modifier.height(7.dp))
        MiniRow(look, taken = false)
    }
}

@Composable
private fun MiniRow(look: TakenColors, taken: Boolean) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(22.dp).height(3.dp).background(look.fgSubtle, RoundedCornerShape(2.dp)))
        Spacer(Modifier.weight(1f))
        Canvas(Modifier.size(8.dp)) {
            if (taken) {
                drawCircle(look.signal)
            } else {
                drawCircle(look.lineStrong, radius = size.minDimension / 2 - 0.5.dp.toPx(), style = Stroke(1.dp.toPx()))
            }
        }
    }
}
