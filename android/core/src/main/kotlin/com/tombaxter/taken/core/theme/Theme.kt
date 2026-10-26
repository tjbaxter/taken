package com.tombaxter.taken.core.theme

import kotlin.math.pow

/**
 * The four looks, chosen in Profile > Look. The raw value is what taken.json stores (`StackSettings.theme`), so a case is
 * never renamed. A look is named for its colour, never for who might pick it. Ported from Shared/Theme.swift.
 */
enum class ThemeID(val raw: String) {
    SIGNAL("signal"),
    BLUSH("blush"),
    PHOSPHOR("phosphor"),
    ICE("ice");

    /** "BLUSH", the mono label. */
    val label: String get() = raw.uppercase()

    /** "Blush", for TalkBack. */
    val title: String get() = raw.replaceFirstChar { it.uppercase() }

    val theme: ThemeTokens get() = Looks.look(this).tokens

    companion object {
        /** A stored or typed name. Anything unknown (a look from a later version, a typo) is Signal. */
        fun stored(value: String?): ThemeID =
            value?.lowercase()?.let { v -> entries.firstOrNull { it.raw == v } } ?: SIGNAL
    }
}

/**
 * A look as numbers: sRGB hex values, and opacities over a base colour for the lines and the signal's edge and wash.
 * Tests check every text pair against WCAG AA from these.
 */
data class ThemeTokens(
    /** The canvas. */
    val bg: Long,
    /** Panels, cards, toasts. */
    val bgRaised: Long,
    /** Code tags, unlit segments, a pressed row. */
    val bgInset: Long,
    val fg: Long,
    val fgMuted: Long,
    /** Labels and secondary readouts. AA on the canvas, like every text colour. */
    val fgSubtle: Long,
    /** Index marks, dashed rings, the footer: decoration more than text. */
    val fgFaint: Long,
    /** Hairlines are this colour at `line` and `lineStrong` opacity. */
    val lineBase: Long,
    val line: Double,
    val lineStrong: Double,
    /** Dashed rules and ruler ticks are this colour at `lineDash` and `tick` opacity. */
    val dashBase: Long,
    val lineDash: Double,
    val tick: Double,
    val bracket: Long,
    /** Lit = taken: discs, segments, lamps, the glyph's lit half. */
    val signal: Long,
    /** The signal as text and thin marks, AA on the canvas, raised surfaces and the wash. */
    val signalInk: Long,
    val signalEdge: Double,
    val signalWash: Double,
    /** Marks drawn on a signal fill: the check on a lit disc. */
    val onSignal: Long,
    val button: Long,
    val buttonText: Long,
    val buttonLamp: Long,
    /** Destructive confirms only. */
    val danger: Long,
)

/** Corner radii, from the HUD frames down to the lamps. */
data class ThemeRadius(
    val frame: Float,
    val panel: Float,
    val control: Float,
    val mark: Float,
    val segment: Float,
    /** Lamps and small lit squares: 0 is square, 1 is round. */
    val lampRoundness: Float,
    /** The app's calm surfaces: the list cards, buttons, toasts; the history's day cells halve it. */
    val card: Float,
) {
    companion object {
        /** Signal, Phosphor and Ice. */
        val HUD = ThemeRadius(frame = 0f, panel = 4f, control = 3f, mark = 2f, segment = 0f, lampRoundness = 0f, card = 14f)
        /** Blush: softer corners everywhere, round lamps. */
        val SOFT = ThemeRadius(frame = 14f, panel = 12f, control = 8f, mark = 4f, segment = 3f, lampRoundness = 1f, card = 16f)
    }
}

/** Everything a view draws with: the colours, the radius scale and the glow. */
data class Look(
    val id: ThemeID,
    /** Blush is light; Signal, Phosphor and Ice are dark. */
    val isLight: Boolean,
    val tokens: ThemeTokens,
    val radius: ThemeRadius,
    /** The signal glow on lit elements: 1 is Signal's phosphor bloom, lower is softer. */
    val glowStrength: Double,
) {
    val label: String get() = id.label
}

object Looks {
    /** Amber phosphor on black: Taken's look since 1.0. The default. */
    val SIGNAL = Look(
        id = ThemeID.SIGNAL, isLight = false,
        tokens = ThemeTokens(
            bg = 0x08090A, bgRaised = 0x0F1012, bgInset = 0x16171A,
            fg = 0xF4F4F5, fgMuted = 0xA1A1AA, fgSubtle = 0x7C7C85, fgFaint = 0x52525B,
            lineBase = 0xFFFFFF, line = 0.10, lineStrong = 0.18,
            dashBase = 0xA1A1AA, lineDash = 0.20, tick = 0.34,
            bracket = 0x7C7C85,
            signal = 0xFFB000, signalInk = 0xFFB000, signalEdge = 0.45, signalWash = 0.10, onSignal = 0x08090A,
            button = 0xE4E4E7, buttonText = 0x111113, buttonLamp = 0xFFB000, danger = 0xFF5F57,
        ),
        radius = ThemeRadius.HUD, glowStrength = 1.0,
    )

    /** Light: a warm off-white canvas, ink type, a muted rose for what is taken (deeper wherever it is text). */
    val BLUSH = Look(
        id = ThemeID.BLUSH, isLight = true,
        tokens = ThemeTokens(
            bg = 0xFBF6F3, bgRaised = 0xFFFDFB, bgInset = 0xF3EBE7,
            fg = 0x2A2224, fgMuted = 0x5F5357, fgSubtle = 0x776A6E, fgFaint = 0xA5979B,
            lineBase = 0x2A2224, line = 0.10, lineStrong = 0.18,
            dashBase = 0x776A6E, lineDash = 0.30, tick = 0.42,
            bracket = 0xAEA1A5,
            signal = 0xD9667F, signalInk = 0xA8425C, signalEdge = 0.50, signalWash = 0.10, onSignal = 0xFFFFFF,
            button = 0x2A2224, buttonText = 0xFBF6F3, buttonLamp = 0xD9667F, danger = 0xC0392B,
        ),
        radius = ThemeRadius.SOFT, glowStrength = 0.35,
    )

    /** Green phosphor on a green-black canvas. */
    val PHOSPHOR = Look(
        id = ThemeID.PHOSPHOR, isLight = false,
        tokens = ThemeTokens(
            bg = 0x060908, bgRaised = 0x0C110E, bgInset = 0x131915,
            fg = 0xEFF5F1, fgMuted = 0x9EAAA3, fgSubtle = 0x78847D, fgFaint = 0x4E5852,
            lineBase = 0xFFFFFF, line = 0.10, lineStrong = 0.18,
            dashBase = 0x9EAAA3, lineDash = 0.20, tick = 0.34,
            bracket = 0x78847D,
            signal = 0x3DFF8A, signalInk = 0x3DFF8A, signalEdge = 0.45, signalWash = 0.10, onSignal = 0x060908,
            button = 0xE2EBE5, buttonText = 0x0C110E, buttonLamp = 0x12B55A, danger = 0xFF5F57,
        ),
        radius = ThemeRadius.HUD, glowStrength = 0.85,
    )

    /** LUPO's cyan on a blue-black canvas. */
    val ICE = Look(
        id = ThemeID.ICE, isLight = false,
        tokens = ThemeTokens(
            bg = 0x07090C, bgRaised = 0x0D1015, bgInset = 0x14181E,
            fg = 0xF0F3F7, fgMuted = 0xA0A9B4, fgSubtle = 0x7A838E, fgFaint = 0x4F5661,
            lineBase = 0xFFFFFF, line = 0.10, lineStrong = 0.18,
            dashBase = 0xA0A9B4, lineDash = 0.20, tick = 0.34,
            bracket = 0x7A838E,
            signal = 0x8FD3E8, signalInk = 0x8FD3E8, signalEdge = 0.45, signalWash = 0.10, onSignal = 0x07090C,
            button = 0xE3E9F0, buttonText = 0x0D1015, buttonLamp = 0x2F9DC4, danger = 0xFF5F57,
        ),
        radius = ThemeRadius.HUD, glowStrength = 1.0,
    )

    /** Profile order. */
    val ALL: List<Look> get() = ThemeID.entries.map { look(it) }

    fun look(id: ThemeID): Look = when (id) {
        ThemeID.SIGNAL -> SIGNAL
        ThemeID.BLUSH -> BLUSH
        ThemeID.PHOSPHOR -> PHOSPHOR
        ThemeID.ICE -> ICE
    }

    /** The launch canvas a light look fades in from (Signal's bg). */
    const val LAUNCH_CANVAS: Long = 0x08090A
}

/**
 * A launch (SPEC-ANDROID 6.1). Every launch starts on the launch canvas, Signal's: the iPhone's launch screen
 * (LaunchBackground in the asset catalog), Android's splash screen. A light look then fades in from it over 0.4 s, easing
 * out, instead of cutting to white (the iPhone's RootView veil, Taken/Views/TodayView.swift and Taken/TakenApp.swift); a
 * dark look's canvas is next to the launch canvas already, so it starts with no veil.
 */
object Launch {
    const val CANVAS: Long = Looks.LAUNCH_CANVAS

    /** SwiftUI's `.easeOut(duration: 0.4)`. */
    const val VEIL_MILLIS: Int = 400

    /** Whether this look starts under the launch canvas's veil. */
    fun veiled(look: Look): Boolean = look.isLight
}

/** WCAG 2 contrast maths, as ThemeTests computes it. */
object Contrast {
    fun luminance(hex: Long): Double {
        fun channel(value: Long): Double {
            val c = value.toDouble() / 255
            return if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * channel((hex shr 16) and 0xFF) + 0.7152 * channel((hex shr 8) and 0xFF) +
            0.0722 * channel(hex and 0xFF)
    }

    fun ratio(a: Long, b: Long): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (maxOf(la, lb) + 0.05) / (minOf(la, lb) + 0.05)
    }

    /** `top` at `alpha` over `base`, as the screen shows it. */
    fun over(top: Long, alpha: Double, base: Long): Long {
        fun mix(shift: Int): Long {
            val a = ((top shr shift) and 0xFF).toDouble()
            val b = ((base shr shift) and 0xFF).toDouble()
            return Math.round(a * alpha + b * (1 - alpha)) shl shift
        }
        return mix(16) or mix(8) or mix(0)
    }
}
