package com.tombaxter.taken

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.res.XmlResourceParser
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ApplicationProvider
import com.tombaxter.taken.core.surfaces.TakenWidgetKind
import com.tombaxter.taken.core.surfaces.WidgetFallbackFace
import com.tombaxter.taken.core.theme.Launch
import com.tombaxter.taken.core.theme.Looks
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.ui.shell.LaunchVeil
import com.tombaxter.taken.ui.theme.TakenColors
import com.tombaxter.taken.widget.StackWidgetReceiver
import com.tombaxter.taken.widget.TodoWidgetReceiver
import com.tombaxter.taken.widget.WidgetFallback
import com.tombaxter.taken.widget.takenIntent
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Looks and icons (SPEC-ANDROID 17, NEXT 7). ThemeTests' icon cases, adapted: the iPhone ships an icon per look, Android one
 * adaptive icon for every look with its own monochrome layer for themed icons, and every layer keeps to the 66 dp safe
 * zone. The splash screen is the default look's canvas with the icon's capsule inside the 192 dp circle, and hands over to
 * Taken's theme; a light look then fades in from it once. The widgets load on Taken's canvas, and a widget Android could
 * not draw shows Taken's card in the person's look.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "xxhdpi")
class LooksTests {
    @get:Rule
    val compose = createComposeRule()

    private val app: TakenApp get() = ApplicationProvider.getApplicationContext()
    private val density: Float get() = app.resources.displayMetrics.density

    private fun draw(drawable: Drawable, sizeDp: Float): Bitmap {
        val size = (sizeDp * density).roundToInt()
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.mutate().setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return bitmap
    }

    /** How many pixels are drawn (more than a trace of alpha) inside and beyond a circle of [radiusDp] at the centre. */
    private fun coverage(bitmap: Bitmap, radiusDp: Float): Pair<Int, Int> {
        val centre = bitmap.width / 2f
        val radius = radiusDp * density + 1f
        var inside = 0
        var outside = 0
        for (y in 0 until bitmap.height) {
            for (x in 0 until bitmap.width) {
                if (Color.alpha(bitmap.getPixel(x, y)) <= 2) continue
                if (hypot(x + 0.5f - centre, y + 0.5f - centre) > radius) outside += 1 else inside += 1
            }
        }
        return inside to outside
    }

    // MARK: The launcher icon

    /** ThemeTests' testEachLookHasItsOwnIconAndSignalIsThePrimary and testTheAlternateIconsShipInTheApp, for Android. */
    @Test
    fun testOneLauncherIconForEveryLookWithItsOwnMonochromeLayer() {
        assertEquals(R.mipmap.ic_launcher, app.applicationInfo.icon, "the app's icon")
        val icon = assertIs<AdaptiveIconDrawable>(app.getDrawable(R.mipmap.ic_launcher), "an adaptive icon")
        assertNotNull(icon.background)
        assertNotNull(icon.foreground)
        assertNotNull(icon.monochrome, "its own monochrome layer, which Android 13 and later tint as a themed icon")
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(app.packageName)
        val entries = app.packageManager.queryIntentActivities(launcher, 0).map { it.activityInfo.name }
        assertEquals(listOf(MainActivity::class.java.name), entries, "one launcher entry: no activity-alias per look (SPEC-ANDROID 18)")
    }

    /**
     * "The 66x66 safe zone ... is never clipped by a shaped mask"
     * (https://developer.android.com/develop/ui/views/launch/icon_design_adaptive): the brackets, ticks, capsule and glow,
     * and the monochrome layer, stay inside it; the background fills the whole 108 dp layer with Signal's canvas.
     */
    @Test
    fun testTheIconsArtworkStaysInsideTheSafeZone() {
        val icon = app.getDrawable(R.mipmap.ic_launcher) as AdaptiveIconDrawable
        for ((name, layer) in listOf("foreground" to icon.foreground, "monochrome" to icon.monochrome!!)) {
            val (inside, outside) = coverage(draw(layer, 108f), 33f)
            assertEquals(0, outside, "the $name layer draws nothing beyond the 33 dp safe zone")
            assertTrue(inside > 0, "the $name layer draws something")
        }
        val background = draw(icon.background, 108f)
        for ((x, y) in listOf(0 to 0, background.width - 1 to background.height - 1, background.width / 2 to background.height / 2)) {
            assertEquals(255, Color.alpha(background.getPixel(x, y)), "the background is opaque everywhere")
        }
        val corner = background.getPixel(0, 0)
        val canvas = Launch.CANVAS.toInt()
        for (shift in listOf(16, 8, 0)) {
            assertTrue(
                kotlin.math.abs(((corner shr shift) and 0xFF) - ((canvas shr shift) and 0xFF)) <= 1,
                "the layer's edge is Signal's canvas, #08090A: ${Integer.toHexString(corner)}",
            )
        }
    }

    // MARK: The splash screen

    private fun resolved(theme: android.content.res.Resources.Theme, attr: Int): TypedValue =
        TypedValue().also { assertTrue(theme.resolveAttribute(attr, it, true), "attribute $attr resolves") }

    /** SPEC-ANDROID 6.1: the default look's canvas, #08090A as the iPhone's launch screen, and the capsule, then Theme.Taken. */
    @Test
    fun testTheSplashScreenIsTheDefaultLooksCanvasWithTheCapsule() {
        val main = app.packageManager.getActivityInfo(ComponentName(app, MainActivity::class.java), 0)
        assertEquals(R.style.Theme_Taken_Starting, main.theme, "MainActivity starts on the splash screen's theme")
        val theme = app.resources.newTheme().apply { applyStyle(R.style.Theme_Taken_Starting, true) }
        val canvas = (0xFF000000L or Launch.CANVAS).toInt()
        assertEquals(canvas, resolved(theme, androidx.core.splashscreen.R.attr.windowSplashScreenBackground).data)
        assertEquals(canvas, resolved(theme, android.R.attr.windowSplashScreenBackground).data, "Android 12 and later's own")
        assertEquals(R.drawable.splash_icon, resolved(theme, androidx.core.splashscreen.R.attr.windowSplashScreenAnimatedIcon).resourceId)
        assertEquals(R.style.Theme_Taken, resolved(theme, androidx.core.splashscreen.R.attr.postSplashScreenTheme).resourceId)
        val bars = theme.obtainStyledAttributes(intArrayOf(android.R.attr.windowLightStatusBar, android.R.attr.windowLightNavigationBar))
        assertFalse(bars.getBoolean(0, true), "light status bar icons over the dark canvas")
        assertFalse(bars.getBoolean(1, true), "light navigation bar icons over the dark canvas")
        bars.recycle()
        assertEquals(canvas, app.getColor(R.color.launch_canvas))

        // "App icon without an icon background: this must be 288x288 dp and fit within a circle 192 dp in diameter"
        // (https://developer.android.com/develop/ui/views/launch/splash-screen).
        val glyph = app.getDrawable(R.drawable.splash_icon)!!
        assertEquals((288 * density).roundToInt(), glyph.intrinsicWidth)
        val (inside, outside) = coverage(draw(glyph, 288f), 96f)
        assertEquals(0, outside, "the capsule fits within the 192 dp circle")
        assertTrue(inside > 0)
    }

    /** RootView(veiled: model.theme.isLight) on the iPhone: a light look fades in from the launch canvas over 0.4 s, once. */
    @Test
    fun testALightLookFadesInFromTheSplashScreenOnce() {
        val restore = StateRestorationTester(compose)
        compose.mainClock.autoAdvance = false
        restore.setContent { LaunchVeil(Looks.BLUSH) { Box(Modifier.fillMaxSize()) } }
        compose.onNodeWithTag("launch-veil").assertExists()
        compose.mainClock.advanceTimeBy(200)
        compose.onNodeWithTag("launch-veil").assertExists()
        compose.mainClock.advanceTimeBy(Launch.VEIL_MILLIS.toLong())
        compose.onNodeWithTag("launch-veil").assertDoesNotExist()
        // A rotation, fold or resize recreates the activity: the screen stays as it is.
        restore.emulateSavedInstanceStateRestore()
        compose.mainClock.advanceTimeByFrame()
        compose.onNodeWithTag("launch-veil").assertDoesNotExist()
    }

    @Test
    fun testADarkLookStartsWithNoVeil() {
        var look by mutableStateOf(ThemeID.SIGNAL)
        compose.mainClock.autoAdvance = false
        compose.setContent { key(look) { LaunchVeil(Looks.look(look)) { Box(Modifier.fillMaxSize()) } } }
        for (dark in listOf(ThemeID.SIGNAL, ThemeID.PHOSPHOR, ThemeID.ICE)) {
            look = dark
            compose.mainClock.advanceTimeByFrame()
            compose.onNodeWithTag("launch-veil").assertDoesNotExist()
        }
    }

    // MARK: Widgets

    /** Each widget's initialLayout, read from its widget info. */
    private fun initialLayout(info: Int): Int {
        val parser = app.resources.getXml(info)
        while (parser.next() != XmlResourceParser.END_DOCUMENT) {
            if (parser.eventType == XmlResourceParser.START_TAG && parser.name == "appwidget-provider") {
                return parser.getAttributeResourceValue("http://schemas.android.com/apk/res/android", "initialLayout", 0)
            }
        }
        error("no appwidget-provider in $info")
    }

    /** The launcher shows Taken's canvas and capsule until a widget's first drawing, never Glance's stock spinner. */
    @Test
    fun testTheWidgetsLoadOnTakensCanvas() {
        for (info in listOf(R.xml.widget_stack_info, R.xml.widget_todo_info)) {
            assertEquals(R.layout.widget_loading, initialLayout(info))
        }
        // Inflated the way a launcher inflates it: RemoteViews refuses any view a widget may not hold.
        val host = FrameLayout(app)
        val loading = RemoteViews(app.packageName, R.layout.widget_loading).apply(app, host)
        assertEquals(android.R.id.background, loading.id, "Android 12 rounds and animates the view with this id")
    }

    /** NEXT 7: a widget Android could not draw shows Taken's card, in the look the surfaces last read, with a tap into Taken. */
    @Test
    fun testAWidgetAndroidCannotDrawShowsTakensCardInTheLook() {
        val manager = AppWidgetManager.getInstance(app)
        val widgets = shadowOf(manager)
        widgets.bindAppWidgetId(41, ComponentName(app, StackWidgetReceiver::class.java))
        widgets.bindAppWidgetId(42, ComponentName(app, TodoWidgetReceiver::class.java))

        WidgetFallback.show(app, 41, TakenWidgetKind.STACK)
        WidgetFallback.show(app, 42, TakenWidgetKind.TODO)
        for ((id, kind) in listOf(41 to TakenWidgetKind.STACK, 42 to TakenWidgetKind.TODO)) {
            val face = WidgetFallbackFace.of(kind)
            val card = widgets.getViewFor(id) as ViewGroup
            val root = card.findViewById<View>(android.R.id.background) ?: card
            val colors = TakenColors.of(Looks.SIGNAL)
            assertEquals(colors.bg.toArgb(), (root.background as ColorDrawable).color, "Signal before any read of the files")
            assertEquals(face.title, card.findViewById<TextView>(R.id.widget_fallback_title).text.toString())
            assertEquals(face.hint, card.findViewById<TextView>(R.id.widget_fallback_hint).text.toString())
            assertEquals(colors.fg.toArgb(), card.findViewById<TextView>(R.id.widget_fallback_title).currentTextColor)
            assertEquals(face.spoken, root.contentDescription?.toString(), "TalkBack reads one line")
            assertTrue(root.hasOnClickListeners(), "the whole card opens Taken")
            val open = PendingIntent.getActivity(
                app, id, takenIntent(app, face.link), PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            assertNotNull(open, "the card's tap opens ${face.link}")
            assertEquals(face.link, shadowOf(open).savedIntent.data.toString())
        }

        // In the person's look once the surfaces have read it.
        kotlinx.coroutines.runBlocking {
            app.container.stores.stack.updateData { it.copy(settings = it.settings.copy(theme = ThemeID.BLUSH)) }
            app.container.surfaces.read()
        }
        assertEquals(ThemeID.BLUSH, app.container.surfaces.look)
        WidgetFallback.show(app, 41, TakenWidgetKind.STACK)
        val card = widgets.getViewFor(41) as ViewGroup
        val root = card.findViewById<View>(android.R.id.background) ?: card
        assertEquals(TakenColors.of(Looks.BLUSH).bg.toArgb(), (root.background as ColorDrawable).color, "Blush's canvas")
        assertEquals(
            TakenColors.of(Looks.BLUSH).fgMuted.toArgb(),
            card.findViewById<TextView>(R.id.widget_fallback_hint).currentTextColor,
        )
    }
}
