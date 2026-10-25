package com.tombaxter.taken

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.view.ContextThemeWrapper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.test.core.app.ApplicationProvider
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.captureRoboImage
import com.github.takahirom.roborazzi.captureScreenRoboImage
import com.tombaxter.taken.core.theme.Looks
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.ui.shell.LaunchVeil
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
import com.tombaxter.taken.ui.theme.TakenType
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sign
import kotlin.math.sin

/**
 * Looks and icons for Tom (SPEC-ANDROID 15.3, NEXT 7), drawn by Robolectric's native graphics as a phone draws them:
 *
 * - `launcher-icon`: the adaptive icon under three launcher masks, as a themed icon on a light and a dark wallpaper (the
 *   tints are examples: the launcher takes them from the wallpaper), its layers with the 72 dp viewport and the 66 dp safe
 *   zone, on two home screens, and the Play store icon under Play's own mask next to the iPhone's icon.
 * - `splash`: the splash screen from the theme's own resources (core-splashscreen's window, which Android 9 to 11 show;
 *   Android 12 and later draw the same canvas and icon at the same sizes).
 * - `launch_<look>`: Today 0.1 s after the splash screen hands over, in every look: Blush fading in from the launch
 *   canvas, the dark looks already there.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ScreenshotTests.PHONE)
@OptIn(ExperimentalRoborazziApi::class)
class LooksScreenshotTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val app: TakenApp get() = ApplicationProvider.getApplicationContext()
    private val density: Float get() = app.resources.displayMetrics.density

    // MARK: The launcher icon

    /** A launcher's mask over the icon's 72 dp viewport, as a path in a square of [side] pixels. */
    private enum class Mask(val label: String) {
        CIRCLE("CIRCLE"),
        SQUIRCLE("SQUIRCLE"),
        ROUNDED("ROUNDED SQUARE");

        fun path(side: Float): Path = when (this) {
            CIRCLE -> Path().apply { addCircle(side / 2, side / 2, side / 2, Path.Direction.CW) }
            ROUNDED -> Path().apply { addRoundRect(RectF(0f, 0f, side, side), side * 0.2f, side * 0.2f, Path.Direction.CW) }
            SQUIRCLE -> Path().apply {
                // |x|^4 + |y|^4 = 1, a superellipse.
                for (i in 0..360) {
                    val t = Math.toRadians(i.toDouble())
                    val x = cos(t).let { sign(it) * abs(it).pow(0.5) }
                    val y = sin(t).let { sign(it) * abs(it).pow(0.5) }
                    val px = (side / 2 * (1 + x)).toFloat()
                    val py = (side / 2 * (1 + y)).toFloat()
                    if (i == 0) moveTo(px, py) else lineTo(px, py)
                }
                close()
            }
        }
    }

    private fun icon(): AdaptiveIconDrawable = app.getDrawable(R.mipmap.ic_launcher) as AdaptiveIconDrawable

    /** The 108 dp layer's bounds when the 72 dp viewport fills [side] pixels: 18 dp beyond it on every side. */
    private fun Drawable.drawAsLayer(canvas: Canvas, side: Int) {
        val extra = side / 4
        mutate().setBounds(-extra, -extra, side + extra, side + extra)
        draw(canvas)
    }

    /** The icon as a launcher draws it: masked, in colour or tinted as a themed icon (background, monochrome). */
    private fun masked(sizeDp: Float, mask: Mask, themed: Pair<Int, Int>? = null): Bitmap {
        val side = (sizeDp * density).roundToInt()
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.clipPath(mask.path(side.toFloat()))
        val icon = icon()
        if (themed == null) {
            icon.background.drawAsLayer(canvas, side)
            icon.foreground.drawAsLayer(canvas, side)
        } else {
            canvas.drawColor(themed.first)
            val mono = icon.monochrome!!.mutate()
            mono.colorFilter = PorterDuffColorFilter(themed.second, PorterDuff.Mode.SRC_IN)
            mono.drawAsLayer(canvas, side)
        }
        return bitmap
    }

    /** The two layers whole, with the 72 dp viewport (white) and the 66 dp safe zone (red) drawn over them. */
    private fun keylines(sizeDp: Float): Bitmap {
        val side = (sizeDp * density).roundToInt()
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val icon = icon()
        for (layer in listOf(icon.background, icon.foreground)) {
            layer.mutate().setBounds(0, 0, side, side)
            layer.draw(canvas)
        }
        val unit = side / 108f
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 1.5f * density }
        stroke.color = android.graphics.Color.argb(170, 255, 255, 255)
        canvas.drawRect(18 * unit, 18 * unit, 90 * unit, 90 * unit, stroke)
        stroke.color = android.graphics.Color.argb(220, 0xFF, 0x5F, 0x57)
        canvas.drawCircle(side / 2f, side / 2f, 33 * unit, stroke)
        return bitmap
    }

    /** A PNG under a rounded mask of [radius] (a fraction of its side), as Play and the iPhone show their icons. */
    private fun maskedFile(path: String, sizeDp: Float, mask: (Float) -> Path): Bitmap {
        val source = BitmapFactory.decodeFile(path) ?: error("cannot read $path")
        val side = (sizeDp * density).roundToInt()
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.clipPath(mask(side.toFloat()))
        canvas.drawBitmap(Bitmap.createScaledBitmap(source, side, side, true), 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG))
        return bitmap
    }

    private val label = TextStyle(fontFamily = TakenType.mono, fontSize = 10.sp, letterSpacing = 1.sp, color = Color(0xFFA1A1AA))
    private val heading = TextStyle(fontFamily = TakenType.sans, fontSize = 15.sp, color = Color(0xFFF4F4F5))

    @Composable
    private fun Tile(bitmap: Bitmap, size: Dp, caption: String) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(124.dp)) {
            Image(bitmap.asImageBitmap(), contentDescription = null, modifier = Modifier.size(size))
            Spacer(Modifier.height(8.dp))
            Text(caption, style = label, textAlign = TextAlign.Center)
        }
    }

    /** One home screen: the icon and its themed form at a launcher's size, with the label under each. */
    @Composable
    private fun HomeScreen(wallpaper: Color, ink: Color, themed: Pair<Int, Int>) {
        Row(
            Modifier.fillMaxWidth().background(wallpaper).padding(vertical = 18.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            for (bitmap in listOf(masked(56f, Mask.CIRCLE), masked(56f, Mask.CIRCLE, themed), masked(56f, Mask.SQUIRCLE))) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Image(bitmap.asImageBitmap(), contentDescription = null, modifier = Modifier.size(56.dp))
                    Spacer(Modifier.height(6.dp))
                    Text("Taken", style = TextStyle(fontSize = 12.sp, color = ink))
                }
            }
        }
    }

    @Test
    @Config(qualifiers = "w411dp-h800dp-420dpi")
    fun theLauncherIcon() {
        // Example themed tints, light and dark: the launcher picks its own from the wallpaper.
        val lightThemed = android.graphics.Color.rgb(0xD3, 0xE3, 0xFD) to android.graphics.Color.rgb(0x04, 0x1E, 0x49)
        val darkThemed = android.graphics.Color.rgb(0x1F, 0x2A, 0x3A) to android.graphics.Color.rgb(0xA8, 0xC7, 0xFA)
        compose.setContent {
            Column(
                Modifier.fillMaxSize().background(Color(0xFF1C1D21)).padding(horizontal = 16.dp, vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Text("Taken for Android: launcher icon", style = heading)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    for (mask in Mask.entries) Tile(masked(96f, mask), 96.dp, mask.label)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Tile(masked(96f, Mask.CIRCLE, lightThemed), 96.dp, "THEMED, LIGHT")
                    Tile(masked(96f, Mask.CIRCLE, darkThemed), 96.dp, "THEMED, DARK")
                    Tile(keylines(108f), 108.dp, "LAYERS, 72 DP\nAND SAFE ZONE")
                }
                HomeScreen(Color(0xFF2E323A), Color(0xFFF4F4F5), darkThemed)
                HomeScreen(Color(0xFFE2DED8), Color(0xFF1C1D21), lightThemed)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    Tile(
                        maskedFile("../store-assets/icon-512.png", 112f) { side ->
                            Path().apply { addRoundRect(RectF(0f, 0f, side, side), side * 0.3f, side * 0.3f, Path.Direction.CW) }
                        },
                        112.dp,
                        "GOOGLE PLAY\nICON-512.PNG",
                    )
                    Tile(
                        maskedFile("../../Taken/Assets.xcassets/AppIcon.appiconset/AppIcon.png", 112f) { side ->
                            Mask.SQUIRCLE.path(side)
                        },
                        112.dp,
                        "IPHONE\nFOR COMPARISON",
                    )
                }
            }
        }
        compose.waitForIdle()
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/launcher-icon.png")
    }

    // MARK: The splash screen

    /**
     * core-splashscreen's own window background, from Taken's splash theme: the canvas, the 288 dp icon and the ring that
     * keeps it to the 192 dp circle, which Android 12 and later draw from the same attributes.
     */
    @Test
    fun theSplashScreen() {
        val themed = ContextThemeWrapper(app, R.style.Theme_Taken_Starting)
        val splash = ContextCompat.getDrawable(themed, androidx.core.splashscreen.R.drawable.compat_splash_screen_no_icon_background)!!
        val metrics = app.resources.displayMetrics
        val bitmap = Bitmap.createBitmap(metrics.widthPixels, metrics.heightPixels, Bitmap.Config.ARGB_8888)
        splash.setBounds(0, 0, bitmap.width, bitmap.height)
        splash.draw(Canvas(bitmap))
        bitmap.captureRoboImage("build/outputs/roborazzi/splash.png")
    }

    // MARK: The launch

    @Test
    fun theLaunchInEveryLook() {
        var current by mutableStateOf<AppModel?>(null)
        compose.setContent {
            val model = current ?: return@setContent
            key(model) { WithSystemBars { LaunchVeil(Looks.look(model.theme)) { TakenRoot(model, Platform.none) } } }
        }
        // The window is laid out once, with the clock running, before the clock is held for the captures.
        current = DemoScreens.make("today")
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        for (look in ThemeID.entries) {
            current = DemoScreens.make("today", look)
            compose.mainClock.advanceTimeByFrame()
            compose.mainClock.advanceTimeBy(100)
            captureScreenRoboImage("build/outputs/roborazzi/launch_${look.raw}.png")
        }
        compose.mainClock.autoAdvance = true
    }
}
