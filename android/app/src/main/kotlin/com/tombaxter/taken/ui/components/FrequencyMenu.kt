package com.tombaxter.taken.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.core.catalog.FrequencyChoice
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/**
 * How often, as a menu (the iPhone's FrequencyMenu; Android's exposed dropdown menu, SPEC-ANDROID 6.3): the choice in the
 * signal's ink with up and down chevrons; Daily, Every other day, Weekly, 2x daily, 3x daily, Days. TalkBack: "Fish Oil,
 * how often, Daily".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FrequencyMenu(choice: FrequencyChoice, label: String, modifier: Modifier = Modifier, onChange: (FrequencyChoice) -> Unit) {
    val colors = Taken.colors
    var open by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = open, onExpandedChange = { open = it }, modifier = modifier) {
        Row(
            Modifier
                .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
                .heightIn(min = 48.dp)
                .semantics { contentDescription = "$label, ${choice.title}" }
                .padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(choice.title, style = TakenType.sans(15, FontWeight.Medium), color = colors.signalInk)
            Spacer(Modifier.width(6.dp))
            Icon(Symbols.UnfoldMore, contentDescription = null, tint = colors.signalInk, modifier = Modifier.size(16.dp))
        }
        ExposedDropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            matchAnchorWidth = false,
            shape = RoundedCornerShape(Taken.shapes.card),
            containerColor = colors.bgRaised,
            tonalElevation = 0.dp,
            shadowElevation = 0.dp,
            border = BorderStroke(1.dp, colors.lineStrong),
        ) {
            for (option in FrequencyChoice.entries) {
                DropdownMenuItem(
                    text = { Text(option.title, style = TakenType.sans(16, if (option == choice) FontWeight.SemiBold else FontWeight.Normal)) },
                    onClick = {
                        onChange(option)
                        open = false
                    },
                    trailingIcon = if (option == choice) {
                        { Icon(Symbols.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                    } else {
                        null
                    },
                    colors = MenuDefaults.itemColors(textColor = colors.fg, trailingIconColor = colors.signalInk),
                )
            }
        }
    }
}
