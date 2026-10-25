package com.tombaxter.taken

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.WindowInsets
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.graphics.Insets
import androidx.core.view.WindowInsetsCompat
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.captureScreenRoboImage
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.ui.profile.ProfileCopy
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The screens Tom sees (SPEC-ANDROID 15.3): drawn on the JVM by Robolectric's native graphics and saved by Roborazzi, no
 * emulator. Names follow the iPhone's scripts/screenshots.sh, with the look after an underscore. The review set is a
 * current 20:9 phone (`w411dp-h914dp-420dpi`, 1080 x 2400) with a status bar and a navigation bar as window insets, so
 * the frames show what a phone shows; there is also a small phone, a landscape tablet and 200% text. The Play store set
 * has its own 9:16 size (SPEC-ANDROID 14.2). `./gradlew :app:recordRoborazziDebug` writes them to
 * app/build/outputs/roborazzi; CI uploads them as android-screenshots.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ScreenshotTests.PHONE)
@OptIn(ExperimentalRoborazziApi::class)
class ScreenshotTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private var current by mutableStateOf<AppModel?>(null)

    /** The review frames get a phone's system bars; the store frames do not (real app only, no device chrome). */
    private var systemBars = true

    /** The keyboard's height for the typing frames: Robolectric draws no keyboard, so its space shows as the inset. */
    private var keyboard by mutableStateOf(0.dp)

    private fun start() {
        compose.setContent {
            val model = current ?: return@setContent
            // A new model is a new screen: nothing carries over from the last capture.
            key(model) {
                if (systemBars) WithSystemBars(ime = keyboard) { TakenRoot(model, Platform.none) } else TakenRoot(model, Platform.none)
            }
        }
    }

    private fun capture(name: String, model: AppModel, interact: () -> Unit = {}) {
        current = model
        compose.waitForIdle()
        interact()
        compose.waitForIdle()
        save(name)
    }

    private fun save(name: String) = captureScreenRoboImage("build/outputs/roborazzi/$name.png")

    private val looks = ThemeID.entries

    /** Every CORE screen in every look: Today empty, pending, partly taken, all taken, in edit mode, with each quiet row,
     * locked; Add and its type-ahead; the item sheet; Set time; History; the day sheet; Profile. */
    @Test
    fun everyScreenInEveryLook() {
        start()
        for (look in looks) {
            for (screen in DemoScreens.screens) {
                capture("${screen}_${look.raw}", DemoScreens.make(screen, look))
            }
        }
    }

    /**
     * Taken Pro (SPEC-ANDROID 9.5 and 9.6): the paywall with the trial, after the trial was used, without the yearly plan,
     * loading and offline; Today locked and with the trial notice; Profile's Taken Pro section in each state. The ones Tom
     * reviews most in every look, the rest in Signal.
     */
    @Test
    fun takenProScreens() {
        start()
        for (look in looks) {
            for (screen in DemoScreens.proScreensEveryLook) {
                if (screen in DemoScreens.screens) continue
                capture("${screen}_${look.raw}", DemoScreens.make(screen, look)) { scrollToPro(screen) }
            }
        }
        for (screen in DemoScreens.proScreens) {
            if (screen in DemoScreens.proScreensEveryLook) continue
            capture("${screen}_signal", DemoScreens.make(screen)) { scrollToPro(screen) }
        }
    }

    /** Profile's Taken Pro section in view. */
    private fun scrollToPro(screen: String) {
        if (screen.startsWith("settings-pro")) compose.onNodeWithText(com.tombaxter.taken.core.pro.ProCopy.RESTORE_AUTOMATIC).performScrollTo()
    }

    /** What the paywall's button does: Play's PENDING answer, and Pro coming on (the button lit, before it closes). */
    @Test
    fun thePaywallAfterItsButton() {
        start()
        for (look in listOf(ThemeID.SIGNAL, ThemeID.BLUSH)) {
            capture("paywall-pending_${look.raw}", DemoScreens.make("paywall-pending", look)) {
                compose.onNodeWithTag("paywall-cta").performClick()
            }
            current = DemoScreens.make("paywall-unlocked", look)
            compose.waitForIdle()
            compose.mainClock.autoAdvance = false
            compose.onNodeWithTag("paywall-cta").performClick()
            compose.mainClock.advanceTimeBy(400)
            save("paywall-unlocked_${look.raw}")
            compose.mainClock.autoAdvance = true
            compose.waitForIdle()
        }
        // Monthly and lifetime chosen: their own terms under the button.
        capture("paywall-monthly_signal", DemoScreens.make("paywall")) { compose.onNodeWithTag("plan-monthly").performClick() }
        capture("paywall-lifetime_signal", DemoScreens.make("paywall")) { compose.onNodeWithTag("plan-lifetime").performClick() }
    }

    /** The long-press menu on a row: Undo last dose, Set time…, Edit item. */
    @Test
    fun theLongPressMenu() {
        start()
        for (look in listOf(ThemeID.SIGNAL, ThemeID.BLUSH)) {
            capture("today-menu_${look.raw}", DemoScreens.make("today", look)) {
                compose.onNodeWithTag("row-Fish Oil").performTouchInput { longClick() }
            }
        }
    }

    /**
     * What a tap on a row does (SPEC-ANDROID 7.2): the logging moment with the Compose clock held 0.1 s after a tap on
     * Magnesium (the row washed in the signal, the ring lifted), then the same tap settled, with the snackbar and Undo.
     * The settled frame logs through the model: the touch ripple is Android's RippleDrawable, which Robolectric leaves
     * drawn over the row, where a phone fades it out.
     */
    @Test
    fun theLoggingMoment() {
        start()
        for (look in listOf(ThemeID.SIGNAL, ThemeID.BLUSH)) {
            current = DemoScreens.make("today", look)
            compose.waitForIdle()
            compose.onNodeWithTag("row-Magnesium").performScrollTo()
            compose.waitForIdle()
            compose.mainClock.autoAdvance = false
            compose.onNodeWithTag("row-Magnesium").performClick()
            compose.mainClock.advanceTimeBy(100)
            save("today-row-moment_${look.raw}")
            compose.mainClock.autoAdvance = true

            val settled = DemoScreens.make("today", look)
            capture("today-logged_${look.raw}", settled) {
                settled.tap(settled.today.items.first { it.item.name == "Magnesium" })
            }
        }
    }

    /** Profile below the stack: the Look picker and Your day, then Feel, Data and About. */
    @Test
    fun profileSections() {
        start()
        for (look in listOf(ThemeID.SIGNAL, ThemeID.BLUSH)) {
            capture("settings-look_${look.raw}", DemoScreens.make("settings", look)) {
                compose.onNodeWithText(ProfileCopy.DAY_FOOTNOTE).performScrollTo()
            }
            capture("settings-data_${look.raw}", DemoScreens.make("settings", look)) {
                compose.onNodeWithText("Support").performScrollTo()
            }
        }
    }

    /**
     * 200% text, Android 14's largest (https://developer.android.com/about/versions/14/features), set as the device's
     * font scale (https://robolectric.org/device-configuration/) so the sheets, which are their own windows, scale too.
     */
    @Test
    @Config(fontScale = 2f)
    fun largerText() {
        start()
        for (screen in listOf("today", "today-edit", "item", "log", "add", "settings", "paywall", "locked")) {
            capture("${screen}_signal_font200", DemoScreens.make(screen))
        }
        capture("settings-pro-trial_signal_font200", DemoScreens.make("settings-pro-trial")) { scrollToPro("settings-pro-trial") }
    }

    @Test
    @Config(qualifiers = SMALL_PHONE)
    fun smallPhone() {
        start()
        for (screen in listOf("today", "today-edit", "add", "day", "paywall")) {
            capture("${screen}_signal_small", DemoScreens.make(screen))
        }
    }

    @Test
    @Config(qualifiers = TABLET)
    fun landscapeTablet() {
        start()
        for (screen in listOf("today", "log", "settings", "paywall")) {
            capture("${screen}_signal_tablet", DemoScreens.make(screen))
        }
    }

    /**
     * The Weight tab (SPEC-ANDROID 12): in every look, the page as it opens, typing with the keyboard's space below the
     * Weigh in bar (the keyboard itself is the system's and is not drawn on the JVM), screen two with the goal and its lit
     * points (one point and its label, and all three), and Today's one-time offer; the rest in Signal, a few in Blush.
     */
    @Test
    fun weightScreens() {
        start()
        for (look in looks) {
            for (screen in WEIGHT_EVERY_LOOK) captureWeight(screen, look)
        }
        for (screen in WeightDemo.pageScreens + WeightDemo.goalScreens) {
            if (screen in WEIGHT_EVERY_LOOK) continue
            captureWeight(screen, ThemeID.SIGNAL)
        }
        for (screen in listOf("weight-empty", "weight-goal-moment", "weight-list", "weight-goal-sheet")) captureWeight(screen, ThemeID.BLUSH)
        // The More options menu, the long press on today's number, and a press on the chart.
        capture("weight-menu_signal", DemoScreens.make("weight")) { compose.onNodeWithTag("weight-more").performClick() }
        capture("weight-longpress_signal", DemoScreens.make("weight-weighed")) {
            compose.onNodeWithTag("weight-number").performTouchInput { longClick() }
        }
        current = DemoScreens.make("weight-goal")
        compose.waitForIdle()
        compose.onNodeWithTag("weight-chart").performTouchInput { down(center) }
        compose.waitForIdle()
        save("weight-scrub_signal")
        compose.onNodeWithTag("weight-chart").performTouchInput { up() }
        compose.waitForIdle()
        for (range in listOf("week", "30d")) {
            capture("weight-trend-$range" + "_signal", DemoScreens.make("weight-trend")) { compose.onNodeWithTag("range-$range").performClick() }
        }
    }

    private fun captureWeight(screen: String, look: ThemeID, suffix: String = "") {
        keyboard = if (WeightDemo.draft(screen) != null) KEYBOARD else 0.dp
        capture("${screen}_${look.raw}$suffix", DemoScreens.make(screen, look)) {
            when (screen) {
                "weight-settings" -> compose.onNodeWithTag("weight-switch").performScrollTo()
                "weight-data" -> compose.onNodeWithTag("import-weight").performScrollTo()
            }
        }
        keyboard = 0.dp
    }

    @Test
    @Config(fontScale = 2f)
    fun weightAtLargerText() {
        start()
        for (screen in listOf("weight", "weight-entry", "weight-trend", "weight-goal", "weight-list", "weight-goal-sheet", "today-weight-offer")) {
            captureWeight(screen, ThemeID.SIGNAL, "_font200")
        }
    }

    @Test
    @Config(qualifiers = SMALL_PHONE)
    fun weightOnASmallPhone() {
        start()
        for (screen in listOf("weight", "weight-entry", "weight-goal")) captureWeight(screen, ThemeID.SIGNAL, "_small")
    }

    @Test
    @Config(qualifiers = TABLET)
    fun weightOnATablet() {
        start()
        for (screen in listOf("weight", "weight-goal")) capture("${screen}_signal_tablet", DemoScreens.make(screen))
    }

    /** The Play store's phone frames: 9:16 at 1215 x 2160, no system bars (SPEC-ANDROID 14.2). */
    @Test
    @Config(qualifiers = STORE)
    fun storeSets() {
        systemBars = false
        start()
        for (stack in listOf(com.tombaxter.taken.core.demo.DemoStack.US, com.tombaxter.taken.core.demo.DemoStack.NEUTRAL)) {
            capture("store-today_${stack.raw}", DemoScreens.make("today", ThemeID.SIGNAL, stack))
        }
    }

    companion object {
        /** A current 20:9 phone: 411 x 914 dp at 420 dpi is 1080 x 2400 pixels (Pixel class). [Own choice] */
        const val PHONE = "w411dp-h914dp-420dpi"
        const val SMALL_PHONE = "w320dp-h568dp-xhdpi"
        const val TABLET = "w1280dp-h800dp-land-xhdpi"

        /**
         * Play's phone screenshot: 405 x 720 dp at xxhdpi is 1215 x 2160 pixels, 9:16 and over 1080 px as promotion
         * needs (https://support.google.com/googleplay/android-developer/answer/9866151), and tall enough that the hero
         * frame shows a pending row above Take all. [Own choice on the size]
         */
        const val STORE = "w405dp-h720dp-xxhdpi"

        /** The Weight frames Tom sees in all four looks. */
        val WEIGHT_EVERY_LOOK = listOf("weight", "weight-entry", "weight-goal", "weight-goal-reached", "today-weight-offer")

        /** About a phone keyboard's height with its suggestion strip [Own choice for the frames]. */
        val KEYBOARD = 300.dp
    }
}

/**
 * A phone's system bars around the screen: a status bar and a gesture navigation bar, 24 dp each, given to Compose as
 * window insets (`DeviceConfigurationOverride.WindowInsets`,
 * https://developer.android.com/reference/kotlin/androidx/compose/ui/test/DeviceConfigurationOverride.Companion), since
 * Robolectric draws none. Edge-to-edge padding then shows as it does on a device. [Own choice: 24 dp]
 */
@Composable
fun WithSystemBars(statusBar: Dp = 24.dp, navigationBar: Dp = 24.dp, ime: Dp = 0.dp, content: @Composable () -> Unit) {
    val insets = with(LocalDensity.current) {
        WindowInsetsCompat.Builder()
            .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, statusBar.roundToPx(), 0, 0))
            .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, navigationBar.roundToPx()))
            .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, if (ime > 0.dp) (ime + navigationBar).roundToPx() else 0))
            .setVisible(WindowInsetsCompat.Type.ime(), ime > 0.dp)
            .build()
    }
    DeviceConfigurationOverride(DeviceConfigurationOverride.WindowInsets(insets)) { content() }
}
