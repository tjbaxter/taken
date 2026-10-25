package com.tombaxter.taken

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.captureScreenRoboImage
import com.tombaxter.taken.core.theme.ThemeID
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
 * emulator. Names follow the iPhone's scripts/screenshots.sh, with the look after an underscore. Phone size is the Play
 * store's 1080 x 1920 (`w360dp-h640dp-xxhdpi`); there is also a small phone, a landscape tablet and 200% text.
 * `./gradlew :app:recordRoborazziDebug` writes them to app/build/outputs/roborazzi; CI uploads them as
 * android-screenshots.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ScreenshotTests.PHONE)
@OptIn(ExperimentalRoborazziApi::class)
class ScreenshotTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private var current by mutableStateOf<AppModel?>(null)
    private var fontScale by mutableFloatStateOf(1f)

    private fun start() {
        compose.setContent {
            val model = current ?: return@setContent
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, density.fontScale * fontScale)) {
                // A new model is a new screen: nothing carries over from the last capture.
                key(model) { TakenRoot(model, Platform.none) }
            }
        }
    }

    private fun capture(name: String, model: AppModel, scale: Float = 1f, interact: () -> Unit = {}) {
        fontScale = scale
        current = model
        compose.waitForIdle()
        interact()
        compose.waitForIdle()
        captureScreenRoboImage("build/outputs/roborazzi/$name.png")
    }

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

    /** 200% text, Android 14's largest (https://developer.android.com/about/versions/14/features). */
    @Test
    fun largerText() {
        start()
        for (screen in listOf("today", "today-edit", "item", "log", "add")) {
            capture("${screen}_signal_font200", DemoScreens.make(screen), scale = 2f)
        }
    }

    @Test
    @Config(qualifiers = SMALL_PHONE)
    fun smallPhone() {
        start()
        for (screen in listOf("today", "today-edit", "add", "day")) {
            capture("${screen}_signal_small", DemoScreens.make(screen))
        }
    }

    @Test
    @Config(qualifiers = TABLET)
    fun landscapeTablet() {
        start()
        for (screen in listOf("today", "log", "settings")) {
            capture("${screen}_signal_tablet", DemoScreens.make(screen))
        }
    }

    @Test
    fun storeSets() {
        start()
        for (stack in listOf(com.tombaxter.taken.core.demo.DemoStack.US, com.tombaxter.taken.core.demo.DemoStack.NEUTRAL)) {
            capture("store-today_${stack.raw}", DemoScreens.make("today", ThemeID.SIGNAL, stack))
        }
    }

    companion object {
        /** The Play store's phone screenshot: 360 x 640 dp at xxhdpi is 1080 x 1920 pixels (SPEC-ANDROID 14.2). */
        const val PHONE = "w360dp-h640dp-xxhdpi"
        const val SMALL_PHONE = "w320dp-h568dp-xhdpi"
        const val TABLET = "w1280dp-h800dp-land-xhdpi"
    }
}
