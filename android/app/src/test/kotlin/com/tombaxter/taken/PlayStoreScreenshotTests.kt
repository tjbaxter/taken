package com.tombaxter.taken

import android.appwidget.AppWidgetHostView
import android.content.Context
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.captureScreenRoboImage
import com.tombaxter.taken.core.demo.DemoData
import com.tombaxter.taken.core.demo.DemoStack
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.surfaces.StackWidgetFace
import com.tombaxter.taken.core.theme.Looks
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
import com.tombaxter.taken.ui.theme.TakenType
import com.tombaxter.taken.widget.StackWidgetContent
import com.tombaxter.taken.widget.WidgetSizes
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.awt.image.BufferedImage
import java.io.File
import java.util.Locale
import javax.imageio.ImageIO
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Google Play phone screenshots (SPEC-ANDROID 14.2), drawn from the app itself on the JVM like every other screen
 * Tom sees, then committed to android/store/play/en-US/images/phoneScreenshots/ (fastlane supply's layout).
 *
 * Google's rules ("Add preview assets to showcase your app", https://support.google.com/googleplay/android-developer/answer/9866151,
 * read 25 Oct 2026): "JPEG or 24-bit PNG (no alpha)"; the long side at most twice the short; for promotion "at least
 * four screenshots with minimum 1080px resolution", 9:16 in portrait; "Screenshots must demonstrate the actual in-app
 * or in-game experience" and "Use captured footage of the app or game itself"; "Add taglines only if necessary to convey
 * the key characteristics of the app" and "Taglines should not take up more than 20% of the image"; no device imagery;
 * no ranking, price or promotion words and no calls to action such as "Download now".
 *
 * Each frame is 1215 x 2160 (405 x 720 dp at xxhdpi, 9:16): a two-line tagline in Taken's words and type, one word lit
 * as on the iPhone's store frames (tools/store-shots/frames.mjs), over the real screen on a rounded card, no device
 * frame and no status bar. The screen is the app at 404 x 760 dp drawn at 2.25 px to the dp (a 360 dpi phone), so it lays
 * out as on a phone and stays sharp: no picture is scaled. The demo is the neutral store set (no medicine names; the
 * listing check forbids them) on its Thursday at 21:41, in Signal. The story, in order (Tom's brief, 25 Oct 2026): Today
 * where one tap logs, All taken, History, a voice to-do being said, the widget; Taken Pro is left out, since the paywall shows
 * prices. [Own choices: the layout, the sizes, the colours of the widget frame's wallpaper and the tagline words.]
 *
 * Roborazzi saves each capture when CI records (`recordRoborazziDebug`); this test then drops the alpha channel, after
 * checking that every pixel is opaque, and writes app/build/outputs/roborazzi/play/phoneScreenshots/<n>.png, which the
 * screenshots job compares byte for byte with the committed files (scripts/check-play-metadata.py --rendered).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = PlayStoreScreenshotTests.FRAME)
@OptIn(ExperimentalRoborazziApi::class, ExperimentalGlanceRemoteViewsApi::class)
class PlayStoreScreenshotTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    /** One frame: its tagline (two lines, `*word*` lit) and what the card shows. */
    private class Shot(val tagline: String, val screen: String)

    private var shot by mutableStateOf<Shot?>(null)
    private var model by mutableStateOf<AppModel?>(null)
    private var taglineBottom = 0f
    private var taglineLines = 0
    private var rootHeight = 0f

    @Test
    fun thePlayStoreScreenshots() {
        compose.setContent {
            val current = shot ?: return@setContent
            key(current) {
                PlayFrame(current.tagline) {
                    if (current.screen == WIDGET) HomeScreen() else model?.let { TakenRoot(it, Platform.none) }
                }
            }
        }
        for ((index, next) in SHOTS.withIndex()) {
            val number = index + 1
            model = if (next.screen == WIDGET) null else DemoScreens.make(next.screen, ThemeID.SIGNAL, DemoStack.NEUTRAL)
            model?.let { m ->
                assertTrue(m.state.items.all { it.name in NEUTRAL_STACK }, "frame $number shows only the neutral stack: ${m.state.items.map { it.name }}")
            }
            shot = next
            compose.waitForIdle()

            // Google: taglines take at most 20% of the image. The whole band above the card, full width, stays under it.
            assertEquals(2, taglineLines, "frame $number's tagline is two lines, never wrapped: ${next.tagline}")
            assertTrue(taglineBottom / rootHeight <= MAX_TAGLINE_SHARE, "frame $number's tagline ends at ${taglineBottom / rootHeight} of the height")

            val raw = File("build/tmp/play/$number.png")
            raw.delete()
            captureScreenRoboImage(raw.path)
            // Roborazzi writes only when CI records; the unit test run checks the frames without writing them.
            if (raw.exists()) writeOpaque(raw, File("build/outputs/roborazzi/play/phoneScreenshots/$number.png"))
        }
    }

    /** The taglines: plain words, no price, ranking, promotion or call to action, at most one word lit. */
    @Test
    fun theTaglinesKeepTheRules() {
        assertTrue(SHOTS.size in 4..8, "Play takes up to 8 phone screenshots, and promotion needs 4")
        for (s in SHOTS) {
            val words = s.tagline.replace("*", "")
            for (rule in BANNED) assertTrue(!rule.containsMatchIn(words), "\"$words\" breaks $rule")
            assertTrue(s.tagline.count { it == '*' } <= 2, "\"${s.tagline}\" lights more than one word")
            assertEquals(1, s.tagline.count { it == '\n' }, "\"${s.tagline}\" is two lines")
        }
    }

    /** The frame: Signal's canvas with a low amber glow, the tagline, and the card holding the screen. */
    @Composable
    private fun PlayFrame(tagline: String, content: @Composable BoxScope.() -> Unit) {
        val tokens = Looks.SIGNAL.tokens
        val canvas = Color(0xFF000000 or tokens.bg)
        val fg = Color(0xFF000000 or tokens.fg)
        val signal = Color(0xFF000000 or tokens.signal)
        val card = RoundedCornerShape(CARD_RADIUS)
        Box(
            Modifier
                .fillMaxSize()
                .background(canvas)
                .onGloballyPositioned { rootHeight = it.size.height.toFloat() }
                .drawBehind {
                    // The iPhone frames' glow (frames.mjs LAYOUT.glow: 0.15 strong, 0.92 of the width, stretched 1.25).
                    val centre = Offset(size.width / 2f, CARD_TOP.toPx() + 260f)
                    val radius = size.width * 0.92f
                    val glow = Brush.radialGradient(
                        0f to signal.copy(alpha = 0.14f), 0.25f to signal.copy(alpha = 0.079f), 0.5f to signal.copy(alpha = 0.035f),
                        0.75f to signal.copy(alpha = 0.009f), 1f to signal.copy(alpha = 0f),
                        center = centre, radius = radius,
                    )
                    scale(1f, 1.25f, pivot = centre) { drawCircle(glow, radius = radius, center = centre) }
                },
        ) {
            Text(
                buildAnnotatedString {
                    tagline.split("*").forEachIndexed { i, part ->
                        withStyle(SpanStyle(color = if (i % 2 == 1) signal else fg)) { append(part) }
                    }
                },
                style = TextStyle(
                    fontFamily = TakenType.sans, fontWeight = FontWeight.SemiBold, fontSize = 32.sp, lineHeight = 38.sp,
                    letterSpacing = (-0.02).em, textAlign = TextAlign.Center,
                ),
                onTextLayout = { taglineLines = it.lineCount },
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = TAGLINE_TOP, start = 24.dp, end = 24.dp)
                    .fillMaxWidth()
                    .onGloballyPositioned { taglineBottom = it.boundsInRoot().bottom },
            )
            Box(
                Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = CARD_TOP)
                    .size(CARD_WIDTH, CARD_HEIGHT)
                    .clip(card)
                    .background(canvas)
                    .border(1.dp, Color.White.copy(alpha = 0.12f), card),
            ) {
                CompositionLocalProvider(LocalDensity provides Density(SCREEN_DENSITY, 1f)) { content() }
            }
        }
    }

    /**
     * The widget frame: the stack widget at 4x4 on a home screen's wallpaper, drawn by Glance into an AppWidgetHostView
     * as WidgetScreenshotTests draws it, at the card's 360 dpi so it sits on the 404 dp screen as on a phone. The
     * wallpaper is warm and plain so the dark widget reads against it. [Own choice]
     */
    @Composable
    private fun BoxScope.HomeScreen() {
        Box(
            Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(0f to Color(0xFF4E3710), 0.5f to Color(0xFF22180A), 1f to Color(0xFF0C0A08)))
                .drawBehind {
                    val centre = Offset(size.width * 0.3f, size.height * 0.15f)
                    val radius = size.maxDimension * 0.6f
                    drawCircle(
                        Brush.radialGradient(listOf(Color(0xFFFFB000).copy(alpha = 0.22f), Color(0x00FFB000)), center = centre, radius = radius),
                        radius = radius, center = centre,
                    )
                },
        )
        AndroidView(
            factory = { context -> stackWidget(context) },
            modifier = Modifier.align(Alignment.TopCenter).padding(top = WIDGET_TOP).size(WidgetSizes.LARGE),
        )
    }

    /** A launcher's widget host: synchronous, as Google's Glance screenshot tool makes it, so it is drawn before the capture. */
    private class HostView(context: Context) : AppWidgetHostView(context) {
        init {
            setExecutor(null)
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
        }
    }

    private fun stackWidget(context: Context): View {
        val config = Configuration(context.resources.configuration).apply { densityDpi = SCREEN_DPI }
        val phone = ContextThemeWrapper(context, 0).apply { applyOverrideConfiguration(config) }
        assertEquals(SCREEN_DENSITY, phone.resources.displayMetrics.density, "the widget is drawn at the card's density")
        val now = DemoScreens.now(DemoStack.NEUTRAL)
        val state = DemoData.state(now, allTaken = false, zone = DemoScreens.zone, stack = DemoStack.NEUTRAL)
        assertTrue(state.items.all { it.name in NEUTRAL_STACK })
        val face = StackWidgetFace(WidgetSnapshot(state, now, DemoScreens.zone, locked = false), Locale.US)
        val remote = runBlocking {
            GlanceRemoteViews().compose(phone, WidgetSizes.LARGE) { StackWidgetContent(face, Looks.SIGNAL) }.remoteViews
        }
        return HostView(phone).also { host -> host.addView(remote.apply(phone, host)) }
    }

    /** Play takes no alpha: every pixel must already be opaque, then the channel goes and the PNG is 24-bit. */
    private fun writeOpaque(raw: File, out: File) {
        val image = ImageIO.read(raw)
        assertEquals(FRAME_WIDTH to FRAME_HEIGHT, image.width to image.height, "${raw.name} is 9:16 at 1215 x 2160")
        val pixels = image.getRGB(0, 0, image.width, image.height, null, 0, image.width)
        assertEquals(0, pixels.count { (it ushr 24) != 0xFF }, "${raw.name} has no see-through pixel")
        val rgb = BufferedImage(image.width, image.height, BufferedImage.TYPE_INT_RGB)
        rgb.setRGB(0, 0, image.width, image.height, pixels, 0, image.width)
        out.parentFile?.mkdirs()
        assertTrue(ImageIO.write(rgb, "png", out), "wrote ${out.path}")
    }

    companion object {
        /** 405 x 720 dp at xxhdpi: 1215 x 2160 pixels, 9:16 and over 1080 px (SPEC-ANDROID 14.2). */
        const val FRAME = "w405dp-h720dp-xxhdpi"
        const val FRAME_WIDTH = 1215
        const val FRAME_HEIGHT = 2160

        /**
         * The screen on the card: 909 x 1710 pixels, a 404 x 760 dp phone at 360 dpi (2.25 px to the dp), tall enough that
         * All taken shows Not today whole above the tab bar.
         */
        const val SCREEN_DPI = 360
        const val SCREEN_DENSITY = 2.25f
        val CARD_WIDTH = 303.dp
        val CARD_HEIGHT = 570.dp
        val CARD_TOP = 114.dp
        val CARD_RADIUS = 16.dp
        val TAGLINE_TOP = 22.dp

        /** Where the widget sits on the wallpaper, in the screen's dp: a little above the middle of 760. */
        val WIDGET_TOP = 136.dp

        /** Google's limit for taglines. */
        const val MAX_TAGLINE_SHARE = 0.20f

        const val WIDGET = "widget"

        /** The neutral store set's stack (DemoData, DemoStack.NEUTRAL): supplements and a "Weekly shot", no medicine. */
        val NEUTRAL_STACK = setOf("Vitamin D3", "Weekly shot", "Fish Oil", "Creatine", "Magnesium", "Zinc")

        /** The words Google lists for preview assets, calls to action, and the house rules (no price, never "free"). */
        val BANNED = listOf(
            Regex("(?i)\\bbest\\b"), Regex("#\\s?1\\b"), Regex("(?i)\\btop\\b"), Regex("(?i)\\bnew\\b"), Regex("(?i)free"),
            Regex("(?i)discount"), Regex("(?i)\\bsale\\b"), Regex("(?i)million"), Regex("(?i)download"), Regex("(?i)install"),
            Regex("[$£€¥]\\s?\\d"), Regex("!"), Regex("[\\u2013\\u2014]"), Regex("(?i)weigh|weight|\\bkg\\b|\\blb"),
        )

        /** The story, in order. Files are named 1.png to 5.png, the order Play shows them. */
        private val SHOTS = listOf(
            Shot("Did I take it?\nKnow for *sure.*", "today"),
            Shot("One tap.\n*Done.*", "today-done"),
            Shot("Every day,\non *record.*", "log"),
            Shot("To-dos?\nJust *say* them.", "todo-recording"),
            Shot("Log it without\n*opening* the app.", WIDGET),
        )
    }
}
