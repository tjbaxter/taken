package com.tombaxter.taken.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.PaywallOrigin
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/**
 * Profile > Taken Pro (SPEC-ANDROID 9.5): the status line, See plans while Pro is off, Manage subscription (Play's
 * subscription center, the online way to cancel Play's policy asks for, https://support.google.com/googleplay/android-developer/answer/9900533),
 * and the privacy policy. No Restore button: on Android Taken asks Google Play for the account's purchases each time it
 * opens and resumes, as Google documents (https://developer.android.com/google/play/billing/integrate), and the footnote
 * says so. The paywall keeps a Restore link for an explicit check.
 */
@Composable
fun ProSection(model: AppModel, platform: Platform) {
    val colors = Taken.colors
    val pro = model.pro
    val active = model.proActive
    val status = pro.status
    val line = if (status == null && !pro.settled) "Checking" else ProCopy.statusLine(status, model.now, model.clock.zone)
    val forGood = active && status != null && (status.reason == ProReason.LIFETIME || status.reason == ProReason.FOUNDING)
    // Manage matters to subscribers, to anyone without Pro (an ended plan restarts there), and to a lifetime member whose
    // subscription still renews (the iPhone's rule).
    val showsManage = !active || status == null || !forGood || status.renewingSubscription
    Section("Taken Pro")
    Card {
        Column {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 52.dp).semantics(mergeDescendants = true) {}.padding(horizontal = 16.dp)
                    .testTag("pro-status"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(8.dp).background(if (active) colors.signal else colors.fgFaint, CircleShape))
                Spacer(Modifier.width(10.dp))
                Text(line, style = TakenType.sans(16, FontWeight.Medium), color = if (active) colors.signalInk else colors.fg)
            }
            if (forGood && status?.renewingSubscription == true) {
                RowDivider()
                Text(ProCopy.RENEWING_NEXT_TO_PRO_FOR_GOOD, style = TakenType.sans(15), color = colors.fgMuted, modifier = Modifier.padding(16.dp))
            }
            if (pro.waitingForApproval && !active) {
                RowDivider()
                Text(ProCopy.WAITING, style = TakenType.sans(15), color = colors.fgMuted, modifier = Modifier.padding(16.dp))
            }
            if (!active) {
                RowDivider()
                LinkRow("See plans", icon = Symbols.ChevronRight) { model.presentPaywall(PaywallOrigin.SETTINGS) }
            }
            if (showsManage) {
                RowDivider()
                LinkRow("Manage subscription", icon = Symbols.OpenInNew) { platform.openUrl(model.manageSubscriptionUrl) }
            }
            RowDivider()
            LinkRow("Privacy Policy", icon = Symbols.OpenInNew) { platform.openUrl(ProCopy.PRIVACY_URL) }
        }
    }
    Footnote(ProCopy.RESTORE_AUTOMATIC)
}
