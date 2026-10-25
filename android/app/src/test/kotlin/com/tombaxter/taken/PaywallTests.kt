package com.tombaxter.taken

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.tombaxter.taken.billing.ProStore
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.PlayEntitlement
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.data.MemoryPersistence
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
import kotlinx.coroutines.MainScope
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import com.tombaxter.taken.notify.NotificationHost
import com.tombaxter.taken.voice.VoiceHost

/**
 * The paywall, the intro paywall, locked Today and Profile's Taken Pro section on screen (SPEC-ANDROID 9.5 and 9.6), over
 * the real ProStore and a fake Google Play: what Play's Subscriptions policy asks to be shown before a purchase is shown,
 * the close always works, a purchase runs the tap that opened the paywall, and Manage opens Play's subscription center.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h914dp-420dpi")
class PaywallTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val zone = ZoneId.of("Europe/London")
    private val now = Instant.parse("2026-10-28T09:14:00Z")

    private class Opened(val urls: MutableList<String>) : Platform, VoiceHost by VoiceHost.none, NotificationHost by NotificationHost.none {
        override val touchExploration = false
        override fun shareCsv(make: () -> String) = Unit
        override fun pickPhoto() = Unit
        override fun openUrl(url: String) {
            urls.add(url)
        }
        override val versionName = "1.0.0"
        override val notificationsOff = false
    }

    private val urls = mutableListOf<String>()
    private var trialsStarted = 0

    private val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = Instant.parse("2026-10-20T08:00:00Z"), sortIndex = 0)

    /** Taken over a fake Play: a stack with Vitamin D3, logged yesterday unless `firstRun`. */
    private fun open(play: FakeBilling, firstRun: Boolean = false, ledger: ProLedger? = null): AppModel {
        val state = StackState(items = listOf(vd3))
        if (!firstRun) state.logDose(vd3.id, now.minus(Duration.ofDays(1)), zone)
        val file = ledger ?: ProLedger(firstSeenAt = now.minus(Duration.ofDays(2)), firstDoseAt = state.doses.firstOrNull()?.takenAt)
        val persistence = MemoryPersistence(stack = state, ledger = file)
        val scope = MainScope()
        val store = ProStore(play, persistence::updateLedger, scope, clock = { now }, locale = { Locale.US })
        val model = AppModel(
            persistence, state, file, Profile(), null, store, clockNow = { now }, zone = { zone }, locale = { Locale.US }, scope = scope,
        )
        model.onTrialStarted = { trialsStarted += 1 }
        compose.setContent { TakenRoot(model, Opened(urls)) }
        store.attach(compose.activity)
        store.foreground()
        store.resumed()
        compose.waitForIdle()
        return model
    }

    @Test
    fun testALockedTapOpensThePaywallAndThePurchaseLogsTheDose() {
        val play = FakeBilling()
        val model = open(play)
        assertTrue(model.isLocked, "the first dose was yesterday and there is no Pro")
        compose.onNodeWithText("Start 7 days on us").assertIsDisplayed()

        compose.onNodeWithTag("row-Vitamin D3").performClick()
        compose.waitForIdle()
        assertEquals(PaywallOrigin.ACTION, model.paywall?.origin)
        // Play's Subscriptions policy: price, period, trial, what it becomes, how to cancel, before the purchase.
        compose.onNodeWithText("7 days on us, then $19.99 per year. Renews automatically until cancelled. Cancel anytime in Google Play.").assertIsDisplayed()
        compose.onNodeWithText(ProCopy.NEEDS_PRO).assertIsDisplayed()
        val timeline = compose.onNodeWithTag("trial-timeline").fetchSemanticsNode()
        assertEquals(
            listOf("Today: full Pro. Day 4: we remind you. Day 7: $19.99 a year starts"),
            timeline.config.getOrNull(SemanticsProperties.ContentDescription),
            "the trial promise, read as one line",
        )
        compose.onNodeWithContentDescription("Close").assertIsDisplayed()
        compose.onNodeWithTag("plan-yearly").assertIsSelected()
        val card = compose.onNodeWithTag("plan-yearly").fetchSemanticsNode()
        assertEquals(Role.RadioButton, card.config.getOrNull(SemanticsProperties.Role), "a radio button for TalkBack")
        assertEquals(
            listOf("Yearly. $19.99 per year. about $1.67 per month. 7 days on us"),
            card.config.getOrNull(SemanticsProperties.ContentDescription),
        )

        play.buys(now)
        compose.onNodeWithTag("paywall-cta").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Taken Pro is on").assertExists()
        assertNotNull(model.paywall, "the lit button holds a moment")
        compose.mainClock.advanceTimeBy(1_500)
        compose.waitForIdle()
        assertNull(model.paywall)
        assertEquals(2, model.state.doses.size, "the tap that opened the paywall ran")
        assertEquals(1, trialsStarted, "the Reminders phase hears that a trial started")
        assertTrue(model.proActive)
        assertEquals(1, play.launches.size)
    }

    @Test
    fun testTheCloseAlwaysWorksAndLogsNothing() {
        val model = open(FakeBilling())
        compose.onNodeWithTag("row-Vitamin D3").performClick()
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Close").performClick()
        compose.waitForIdle()
        assertNull(model.paywall)
        assertEquals(1, model.state.doses.size, "nothing logged")
        assertTrue(model.isLocked, "the record stays readable, logging stays locked")
    }

    @Test
    fun testOtherPlansSayTheirOwnTerms() {
        val model = open(FakeBilling(products = FakeBilling.catalog(trial = false)))
        model.presentPaywall(PaywallOrigin.BAR)
        compose.waitForIdle()
        compose.onNodeWithText("Continue").assertIsDisplayed()
        compose.onNodeWithText("$19.99 per year. ${ProCopy.RENEWAL_TERMS}").assertIsDisplayed()
        compose.onNodeWithTag("trial-timeline").assertDoesNotExist()
        compose.onNodeWithTag("plan-monthly").performClick()
        compose.onNodeWithText("$3.99 per month. ${ProCopy.RENEWAL_TERMS}").assertIsDisplayed()
        compose.onNodeWithTag("plan-lifetime").performClick()
        compose.onNodeWithText(ProCopy.LIFETIME_TERMS).assertIsDisplayed()
    }

    @Test
    fun testTheIntroPaywallFollowsTheFirstDoseOnce() {
        val model = open(FakeBilling(), firstRun = true, ledger = ProLedger(firstSeenAt = now))
        assertEquals(com.tombaxter.taken.core.pro.ProAccess.FIRST_SESSION, model.access)
        compose.onNodeWithTag("row-Vitamin D3").performClick()
        compose.waitForIdle()
        assertEquals(1, model.state.doses.size, "the first dose needs no Pro")
        assertNull(model.paywall, "not at once: the dose lights up first")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1_600))
        compose.waitForIdle()
        assertEquals(PaywallOrigin.INTRO, model.paywall?.origin, "about 1.5 s after the first dose")
        assertNotNull(model.ledger?.introShownAt)
        model.closePaywall()
        compose.waitForIdle()
        model.didBecomeActive()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1_600))
        compose.waitForIdle()
        assertNull(model.paywall, "never on its own a second time")
    }

    @Test
    fun testProfileShowsTheTrialAndManageOpensPlay() {
        val bought = FakeBilling.purchase(ProPlan.YEARLY.productId, now.minus(Duration.ofDays(3)))
        val ledger = ProLedger(
            firstSeenAt = now.minus(Duration.ofDays(5)), firstDoseAt = now.minus(Duration.ofDays(4)),
            trialEnds = mapOf(PlayEntitlement.trialKey(bought.purchaseTime) to bought.purchaseTime.plus(Duration.ofDays(7))),
        )
        val model = open(FakeBilling(held = listOf(bought)), ledger = ledger)
        model.openProfile()
        compose.waitForIdle()
        compose.onNodeWithTag("pro-status").performScrollTo()
        compose.onNodeWithText("Trial · ends 1 Nov").assertIsDisplayed()
        compose.onNodeWithText(ProCopy.RESTORE_AUTOMATIC).assertExists()
        compose.onNodeWithText("See plans").assertDoesNotExist()
        compose.onNodeWithText("Manage subscription").performScrollTo().performClick()
        assertEquals(
            "https://play.google.com/store/account/subscriptions?sku=com.tombaxter.taken.pro.yearly&package=com.tombaxter.taken",
            urls.last(),
        )
    }

    @Test
    fun testProfileWithoutProOffersThePlans() {
        val model = open(FakeBilling())
        model.openProfile()
        compose.waitForIdle()
        compose.onNodeWithTag("pro-status").performScrollTo()
        compose.onNodeWithText("Not active").assertIsDisplayed()
        compose.onNodeWithText("See plans").performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(PaywallOrigin.SETTINGS, model.paywall?.origin)
    }
}
