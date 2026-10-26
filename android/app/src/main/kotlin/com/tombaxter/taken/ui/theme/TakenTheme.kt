package com.tombaxter.taken.ui.theme

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.core.theme.Look
import com.tombaxter.taken.core.theme.Looks
import com.tombaxter.taken.core.theme.ThemeID

/**
 * Taken's colours as Compose sees them: every role of a look (Shared/Theme.swift, ported in core/theme). Views never name
 * a colour of their own; they take a role from [LocalTakenColors].
 */
@Immutable
data class TakenColors(
    val id: ThemeID,
    val isLight: Boolean,
    val bg: Color,
    val bgRaised: Color,
    val bgInset: Color,
    val fg: Color,
    val fgMuted: Color,
    val fgSubtle: Color,
    val fgFaint: Color,
    val line: Color,
    val lineStrong: Color,
    val signal: Color,
    val signalInk: Color,
    val signalEdge: Color,
    val signalWash: Color,
    val onSignal: Color,
    val button: Color,
    val buttonText: Color,
    val buttonLamp: Color,
    val danger: Color,
    val glowStrength: Float,
) {
    /** The signal as a glow: `alpha` is Signal's, scaled for the look. */
    fun glow(alpha: Float): Color = signal.copy(alpha = (alpha * glowStrength).coerceIn(0f, 1f))

    companion object {
        fun of(look: Look): TakenColors {
            val t = look.tokens
            fun c(hex: Long, alpha: Double = 1.0) = Color((0xFF000000L or hex).toInt()).copy(alpha = alpha.toFloat())
            return TakenColors(
                id = look.id, isLight = look.isLight,
                bg = c(t.bg), bgRaised = c(t.bgRaised), bgInset = c(t.bgInset),
                fg = c(t.fg), fgMuted = c(t.fgMuted), fgSubtle = c(t.fgSubtle), fgFaint = c(t.fgFaint),
                line = c(t.lineBase, t.line), lineStrong = c(t.lineBase, t.lineStrong),
                signal = c(t.signal), signalInk = c(t.signalInk), signalEdge = c(t.signal, t.signalEdge),
                signalWash = c(t.signal, t.signalWash), onSignal = c(t.onSignal),
                button = c(t.button), buttonText = c(t.buttonText), buttonLamp = c(t.buttonLamp), danger = c(t.danger),
                glowStrength = look.glowStrength.toFloat(),
            )
        }
    }
}

/** The look's radius scale: cards and buttons use `card`, history cells, fields and weekday toggles half of it. */
@Immutable
data class TakenShapes(val card: Dp, val control: Dp, val mark: Dp) {
    val cell: Dp get() = card / 2
}

val LocalTakenColors = staticCompositionLocalOf { TakenColors.of(Looks.SIGNAL) }
val LocalTakenShapes = staticCompositionLocalOf { TakenShapes(card = 14.dp, control = 3.dp, mark = 2.dp) }

/** The current look's roles: `Taken.colors.fg`. */
object Taken {
    val colors: TakenColors
        @Composable get() = LocalTakenColors.current
    val shapes: TakenShapes
        @Composable get() = LocalTakenShapes.current
}

/**
 * Material 3 built entirely from a look's tokens (SPEC-ANDROID 6.1): every colour slot set, so no stock Material colour
 * can appear; no dynamic colour, since wallpaper colours would override the look; Geist in every text style; shapes from
 * the look's radius scale; the ripple tinted from `fg`.
 */
@Composable
fun TakenTheme(look: ThemeID, content: @Composable () -> Unit) {
    // A new look recolours the app with a 0.3 s crossfade of every role, as on the iPhone.
    val colors = animated(TakenColors.of(Looks.look(look)))
    val radius = Looks.look(look).radius
    val shapes = TakenShapes(card = radius.card.dp, control = radius.control.dp, mark = radius.mark.dp)
    MaterialTheme(
        colorScheme = colorScheme(colors),
        typography = TakenType.typography,
        shapes = Shapes(
            extraSmall = RoundedCornerShape(shapes.control),
            small = RoundedCornerShape(shapes.cell),
            medium = RoundedCornerShape(shapes.card),
            large = RoundedCornerShape(shapes.card),
            extraLarge = RoundedCornerShape(shapes.card + 8.dp),
        ),
    ) {
        CompositionLocalProvider(
            LocalTakenColors provides colors,
            LocalTakenShapes provides shapes,
            LocalIndication provides ripple(color = colors.fg),
        ) {
            content()
        }
    }
}

@Composable
private fun animated(target: TakenColors): TakenColors {
    @Composable
    fun fade(color: Color): Color = animateColorAsState(color, tween(300), label = "look").value
    return target.copy(
        bg = fade(target.bg), bgRaised = fade(target.bgRaised), bgInset = fade(target.bgInset), fg = fade(target.fg),
        fgMuted = fade(target.fgMuted), fgSubtle = fade(target.fgSubtle), fgFaint = fade(target.fgFaint),
        line = fade(target.line), lineStrong = fade(target.lineStrong), signal = fade(target.signal),
        signalInk = fade(target.signalInk), signalEdge = fade(target.signalEdge), signalWash = fade(target.signalWash),
        onSignal = fade(target.onSignal), button = fade(target.button), buttonText = fade(target.buttonText),
        buttonLamp = fade(target.buttonLamp), danger = fade(target.danger),
    )
}

private fun colorScheme(c: TakenColors): ColorScheme = if (c.isLight) {
    lightColorScheme(
        primary = c.signalInk, onPrimary = c.onSignal, primaryContainer = c.bgInset, onPrimaryContainer = c.fg,
        inversePrimary = c.signal, secondary = c.fgMuted, onSecondary = c.bg, secondaryContainer = c.bgInset,
        onSecondaryContainer = c.fg, tertiary = c.signalInk, onTertiary = c.onSignal, tertiaryContainer = c.bgInset,
        onTertiaryContainer = c.fg, background = c.bg, onBackground = c.fg, surface = c.bg, onSurface = c.fg,
        surfaceVariant = c.bgInset, onSurfaceVariant = c.fgMuted, surfaceTint = Color.Transparent, inverseSurface = c.fg,
        inverseOnSurface = c.bg, error = c.danger, onError = c.bg, errorContainer = c.bgInset, onErrorContainer = c.danger,
        outline = c.lineStrong, outlineVariant = c.line, scrim = Color.Black, surfaceBright = c.bgRaised,
        surfaceContainer = c.bgRaised, surfaceContainerHigh = c.bgRaised, surfaceContainerHighest = c.bgInset,
        surfaceContainerLow = c.bgRaised, surfaceContainerLowest = c.bg, surfaceDim = c.bgInset,
        primaryFixed = c.signal, primaryFixedDim = c.signal, onPrimaryFixed = c.onSignal, onPrimaryFixedVariant = c.onSignal,
        secondaryFixed = c.bgInset, secondaryFixedDim = c.bgInset, onSecondaryFixed = c.fg, onSecondaryFixedVariant = c.fgMuted,
        tertiaryFixed = c.signal, tertiaryFixedDim = c.signal, onTertiaryFixed = c.onSignal, onTertiaryFixedVariant = c.onSignal,
    )
} else {
    darkColorScheme(
        primary = c.signalInk, onPrimary = c.onSignal, primaryContainer = c.bgInset, onPrimaryContainer = c.fg,
        inversePrimary = c.signal, secondary = c.fgMuted, onSecondary = c.bg, secondaryContainer = c.bgInset,
        onSecondaryContainer = c.fg, tertiary = c.signalInk, onTertiary = c.onSignal, tertiaryContainer = c.bgInset,
        onTertiaryContainer = c.fg, background = c.bg, onBackground = c.fg, surface = c.bg, onSurface = c.fg,
        surfaceVariant = c.bgInset, onSurfaceVariant = c.fgMuted, surfaceTint = Color.Transparent, inverseSurface = c.fg,
        inverseOnSurface = c.bg, error = c.danger, onError = c.bg, errorContainer = c.bgInset, onErrorContainer = c.danger,
        outline = c.lineStrong, outlineVariant = c.line, scrim = Color.Black, surfaceBright = c.bgRaised,
        surfaceContainer = c.bgRaised, surfaceContainerHigh = c.bgRaised, surfaceContainerHighest = c.bgInset,
        surfaceContainerLow = c.bgRaised, surfaceContainerLowest = c.bg, surfaceDim = c.bg,
        primaryFixed = c.signal, primaryFixedDim = c.signal, onPrimaryFixed = c.onSignal, onPrimaryFixedVariant = c.onSignal,
        secondaryFixed = c.bgInset, secondaryFixedDim = c.bgInset, onSecondaryFixed = c.fg, onSecondaryFixedVariant = c.fgMuted,
        tertiaryFixed = c.signal, tertiaryFixedDim = c.signal, onTertiaryFixed = c.onSignal, onTertiaryFixedVariant = c.onSignal,
    )
}
