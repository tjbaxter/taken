package com.tombaxter.taken

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.tombaxter.taken.core.reminders.ReminderCopy
import com.tombaxter.taken.core.reminders.TrialAsk
import com.tombaxter.taken.core.reminders.TrialReminder
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Taken Pro's two places in the Reminders' screens, on screen (SPEC-ANDROID 9.7 and 10.4): the trial ask after a trial
 * starts, with Continue and Not now, and Profile > Reminder's Trial reminder switch, which shows only while a trial renews.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = ScreenshotTests.PHONE)
class TrialAskScreenTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun show(model: AppModel) {
        compose.setContent { TakenRoot(model, Platform.none) }
        compose.waitForIdle()
    }

    @Test
    fun theTrialAskSaysWhyAndOffersContinueAndNotNow() {
        val model = DemoScreens.make("trial-ask")
        show(model)
        compose.onNodeWithTag("trial-ask").assertExists()
        compose.onNodeWithText(TrialAsk.TITLE).assertExists()
        compose.onNodeWithText(TrialAsk.BODY).assertExists()
        compose.onNodeWithTag("trial-ask-continue").assertExists()
        compose.onNodeWithText(TrialAsk.ALLOW).assertExists()
        compose.onNodeWithTag("trial-ask-not-now").performClick()
        compose.waitForIdle()
        assertFalse(model.showsTrialAsk, "Not now: the ask goes")
        compose.onNodeWithTag("trial-ask").assertDoesNotExist()
    }

    @Test
    fun theTrialReminderSwitchShowsInReminderOnlyWhileATrialRenews() {
        val model = DemoScreens.make("settings-reminder-trial")
        show(model)
        assertTrue(model.showsTrialReminderSwitch)
        compose.onNodeWithTag("trial-reminder").performScrollTo()
        compose.onNodeWithText(ReminderCopy.TRIAL_REMINDER).assertIsOn()
        compose.onNodeWithText("${ReminderCopy.FOOTNOTE} ${TrialReminder.SETTING_FOOTNOTE}").assertExists()
        compose.onNodeWithText(ReminderCopy.TRIAL_REMINDER).performClick()
        compose.waitForIdle()
        assertFalse(model.settings.trialReminderEnabled, "off: the reminder and Today's line go with it")
        compose.onNodeWithText(ReminderCopy.TRIAL_REMINDER).assertIsOff()

        val plain = DemoScreens.make("settings-reminder")
        assertFalse(plain.showsTrialReminderSwitch, "no trial, no switch")
    }

    @Test
    fun withoutATrialReminderHasNoTrialSwitch() {
        show(DemoScreens.make("settings-reminder"))
        compose.onNodeWithText(ReminderCopy.FOOTNOTE).performScrollTo()
        compose.onNodeWithTag("trial-reminder").assertDoesNotExist()
    }
}
