package com.tombaxter.taken.ui.paywall

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.core.reminders.TrialAsk
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.components.TakenSheet
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/**
 * The one notification ask right after a trial starts (SPEC-ANDROID 10.4, the iPhone's TrialAskSheet): the bell, "Your
 * trial has started.", both reasons in one line, and **Continue**, which opens Android's own prompt. Android adds **Not
 * now**: "Always provide the option to cancel an educational UI flow" (https://developer.android.com/training/permissions/requesting),
 * where Apple's HIG asks for one button. A swipe down or back is Not now too. It is used up only once it is on screen.
 */
@Composable
fun TrialAskSheet(model: AppModel) {
    val colors = Taken.colors
    LaunchedEffect(Unit) { model.trialAskDidAppear() }
    TakenSheet(onDismiss = { model.answerTrialAsk(proceed = false) }) {
        // Larger text than fits scrolls inside the sheet.
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(top = 12.dp, bottom = 16.dp)
                .navigationBarsPadding()
                .testTag("trial-ask"),
        ) {
            Box(Modifier.size(40.dp).background(colors.signal, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Symbols.NotificationsFill, contentDescription = null, tint = colors.onSignal, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.height(18.dp))
            Text(
                TrialAsk.TITLE,
                style = TakenType.sans(24, FontWeight.SemiBold),
                color = colors.fg,
                modifier = Modifier.semantics { heading() },
            )
            Spacer(Modifier.height(8.dp))
            Text(model.trialAskBody, style = TakenType.sans(17), color = colors.fgMuted)
            Spacer(Modifier.height(28.dp))
            val shape = RoundedCornerShape(Taken.shapes.card)
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .clip(shape)
                    .background(colors.button, shape)
                    .clickable(role = Role.Button, onClickLabel = TrialAsk.ALLOW_ACTION) {
                        model.answerTrialAsk(proceed = true)
                    }
                    .testTag("trial-ask-continue"),
                contentAlignment = Alignment.Center,
            ) {
                Text(TrialAsk.ALLOW, style = TakenType.sans(17, FontWeight.SemiBold), color = colors.buttonText)
            }
            Spacer(Modifier.height(8.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .clip(shape)
                    .clickable(role = Role.Button) { model.answerTrialAsk(proceed = false) }
                    .testTag("trial-ask-not-now"),
                contentAlignment = Alignment.Center,
            ) {
                Text(TrialAsk.NOT_NOW, style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted)
            }
        }
    }
}
