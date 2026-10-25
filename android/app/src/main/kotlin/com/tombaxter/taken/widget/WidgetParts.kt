package com.tombaxter.taken.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.actionParametersOf
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.size
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.tombaxter.taken.MainActivity
import com.tombaxter.taken.R
import com.tombaxter.taken.core.surfaces.WidgetTap
import com.tombaxter.taken.core.theme.Look
import com.tombaxter.taken.ui.theme.TakenColors

/**
 * A look's colours as Glance takes them (SPEC-ANDROID 10.1). Taken's roles have no Material slot of their own (the signal's
 * ink, the faint and subtle greys, the button and its lamp), so the widgets take them from the look directly, as the app's
 * screens take them from `LocalTakenColors` [Own choice: SPEC-ANDROID 10.1 named `GlanceTheme`; its `ColorProviders` are
 * Material's roles]. Blush is light and the other looks dark whatever the system says, as in the app.
 */
class WidgetPalette(val look: Look) {
    private val c = TakenColors.of(look)
    val bg = ColorProvider(c.bg)
    val bgRaised = ColorProvider(c.bgRaised)
    val bgInset = ColorProvider(c.bgInset)
    val fg = ColorProvider(c.fg)
    val fgMuted = ColorProvider(c.fgMuted)
    val fgSubtle = ColorProvider(c.fgSubtle)
    val fgFaint = ColorProvider(c.fgFaint)
    val line = ColorProvider(c.line)
    val lineDash = ColorProvider(Color((0xFF000000L or look.tokens.dashBase).toInt()).copy(alpha = look.tokens.lineDash.toFloat()))
    val signal = ColorProvider(c.signal)
    val signalInk = ColorProvider(c.signalInk)
    val signalEdge = ColorProvider(c.signalEdge)
    val signalWash = ColorProvider(c.signalWash)
    val onSignal = ColorProvider(c.onSignal)
    val button = ColorProvider(c.button)
    val buttonText = ColorProvider(c.buttonText)
    val buttonTextSoft = ColorProvider(c.buttonText.copy(alpha = 0.6f))
    val buttonLamp = ColorProvider(c.buttonLamp)
    val danger = ColorProvider(c.danger)

    /** The look's radius for panels, at most 10 dp, as the iPhone's TAKE ALL button: Signal's HUD is square-ish. */
    val panelRadius: Dp = minOf(look.radius.panel, 10f).dp
    val markRadius: Dp = look.radius.mark.dp
    val segmentRadius: Dp = minOf(look.radius.segment, 2f).dp

    /** Round lamps in the soft looks, square in the HUD ones (the iPhone's `LampShape(roundness:)`). */
    val lampRadius: Dp = (2.5f * look.radius.lampRoundness).dp
}

/**
 * Widgets cannot use an app's own fonts ("custom fonts in apps aren't supported",
 * https://developer.android.com/develop/ui/compose/glance/build-ui), so Geist Mono becomes the system monospace and
 * Geist the system sans, at the iPhone's sizes in `sp` (SPEC-ANDROID 10.1).
 */
object WidgetType {
    fun mono(size: TextUnit, color: ColorProvider, weight: FontWeight = FontWeight.Normal): TextStyle =
        TextStyle(color = color, fontSize = size, fontWeight = weight, fontFamily = FontFamily.Monospace)

    fun sans(size: TextUnit, color: ColorProvider, weight: FontWeight = FontWeight.Normal): TextStyle =
        TextStyle(color = color, fontSize = size, fontWeight = weight, fontFamily = FontFamily.SansSerif)

    /** The HUD's small caps lines ("LOGGED 07:42"): mono, the iPhone's `hudFixed`. */
    fun hud(size: Float, color: ColorProvider): TextStyle = mono(size.sp, color, FontWeight.Medium)
}

/** The launcher grid's cell sizes on a typical phone, portrait (https://developer.android.com/develop/ui/views/appwidgets/layouts). */
object WidgetSizes {
    /** (73n - 16) x (118m - 16) dp. */
    fun cells(columns: Int, rows: Int): DpSize = DpSize((73 * columns - 16).dp, (118 * rows - 16).dp)

    val SMALL = cells(2, 1)
    val TALL = cells(2, 2)
    val MEDIUM = cells(4, 2)
    val LARGE = cells(4, 4)

    /** Google's minimum touch target, which a widget row keeps (WL-4.2, https://developer.android.com/docs/quality-guidelines/widget-quality). */
    val TOUCH = 48.dp
}

/** The widget's frame: the look's canvas, the system's corner radius from Android 12 (WS-2), Android's widget background id. */
fun GlanceModifier.widgetFrame(palette: WidgetPalette): GlanceModifier {
    val framed = fillMaxSize().background(palette.bg).appWidgetBackground()
    return if (Build.VERSION.SDK_INT >= 31) framed.cornerRadius(android.R.dimen.system_app_widget_background_radius) else framed
}

/** Corner radius where Android draws one (Android 12 and later; Glance does nothing below). */
fun GlanceModifier.rounded(radius: Dp): GlanceModifier = if (radius > 0.dp) cornerRadius(radius) else this

/** A white drawable tinted with a role of the look. */
@Composable
fun Glyph(resource: Int, tint: ColorProvider, size: Dp, modifier: GlanceModifier = GlanceModifier) {
    Image(
        provider = ImageProvider(resource),
        contentDescription = null,
        colorFilter = ColorFilter.tint(tint),
        modifier = modifier.size(size),
    )
}

/** The Taken mark: the split capsule, one half lit in the signal, one outlined. */
@Composable
fun CapsuleMark(palette: WidgetPalette, size: Dp) {
    Box(GlanceModifier.size(size)) {
        Glyph(R.drawable.widget_capsule_lit, palette.signal, size)
        Glyph(R.drawable.widget_capsule_outline, palette.fgMuted, size)
    }
}

/** A small square or round lamp, lit in the signal or faint. */
@Composable
fun Lamp(color: ColorProvider, palette: WidgetPalette) {
    Box(GlanceModifier.size(5.dp).background(color).rounded(palette.lampRadius)) {}
}

/** The explicit intent every surface opens Taken with: MainActivity, carrying a `taken://` link (SPEC-ANDROID 10.3). */
fun takenIntent(context: Context, url: String): Intent =
    Intent(Intent.ACTION_VIEW, Uri.parse(url), context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

/**
 * A widget tap as Glance's action: a callback that logs without opening Taken, or Taken opened on a link. Activities start
 * only from the widget itself on Android 12 and later, never from a callback ("Apps that target Android 12 or higher
 * can't start activities from services or broadcast receivers that act as trampolines",
 * https://developer.android.com/develop/ui/compose/glance/user-interaction).
 */
fun WidgetTap.action(context: Context): Action? = when (this) {
    is WidgetTap.LogNext -> actionRunCallback<LogNextAction>(actionParametersOf(LogNextAction.ITEM to itemId.toString()))
    WidgetTap.TakeAll -> actionRunCallback<TakeAllAction>()
    is WidgetTap.Open -> actionStartActivity(takenIntent(context, url))
    WidgetTap.None -> null
}
