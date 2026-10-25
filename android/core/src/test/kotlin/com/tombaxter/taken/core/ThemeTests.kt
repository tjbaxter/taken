package com.tombaxter.taken.core

import com.tombaxter.taken.core.demo.DemoData
import com.tombaxter.taken.core.model.StackCodec
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.stack.eraseAll
import com.tombaxter.taken.core.theme.Contrast
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.core.theme.ThemeRadius
import com.tombaxter.taken.core.theme.Looks
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/ThemeTests.swift: the look persists with the stack, a file from before looks existed (or with a
 * look this version does not know) reads as Signal, Signal is 1.0's look exactly, and every look's text passes WCAG AA.
 * The icon cases are left out (one launcher icon on Android, SPEC-ANDROID 18); the store round trip runs in :app.
 */
class ThemeTests {

    // MARK: Persistence

    @Test
    fun testAFileFromBeforeLooksReadsAsSignal() {
        val json = """{"items":[],"doses":[],"settings":{"dayStartHour":3,"reminderEnabled":true,"reminderMinutes":1230,"hapticsEnabled":false}}"""
        val state = StackCodec.decode(json)
        assertEquals(ThemeID.SIGNAL, state.settings.theme)
        assertEquals(3, state.settings.dayStartHour, "the other settings are untouched")
        assertEquals(1230, state.settings.reminderMinutes)
        assertFalse(state.settings.hapticsEnabled)
        assertEquals(ThemeID.SIGNAL, StackSettings().theme, "new installs start on Signal")
    }

    @Test
    fun testAnUnknownLookReadsAsSignalAndKeepsTheRest() {
        val later = StackCodec.decode("""{"settings":{"dayStartHour":5,"theme":"aurora","reminderEnabled":true}}""")
        assertEquals(ThemeID.SIGNAL, later.settings.theme, "a look from a later version")
        assertEquals(5, later.settings.dayStartHour)
        assertTrue(later.settings.reminderEnabled)

        val other = StackCodec.decode("""{"settings":{"dayStartHour":6,"theme":7}}""")
        assertEquals(ThemeID.SIGNAL, other.settings.theme, "not even a string")
        assertEquals(6, other.settings.dayStartHour)

        assertEquals(ThemeID.BLUSH, StackCodec.decode("""{"settings":{"theme":"BLUSH"}}""").settings.theme)
    }

    @Test
    fun testTheLookRoundTripsThroughTheFile() {
        for (look in ThemeID.entries) {
            val state = StackState(settings = StackSettings(theme = look))
            assertEquals(look, StackCodec.decode(StackCodec.encode(state)).settings.theme)
        }
        val text = StackCodec.encode(StackState(settings = StackSettings(theme = ThemeID.PHOSPHOR)))
        assertTrue(text.contains("\"theme\":\"phosphor\""), text)
    }

    @Test
    fun testEraseAllKeepsTheLook() {
        val state = StackState(
            items = listOf(makeItem("Zinc", "ZNC", created = at(2026, 10, 1, 8))),
            settings = StackSettings.fromDayStartHour(2, reminderEnabled = true, theme = ThemeID.ICE),
        )
        state.eraseAll()
        assertTrue(state.items.isEmpty())
        assertEquals(StackSettings.DEFAULT_WAKE_MINUTES, state.settings.wakeMinutes, "settings reset")
        assertEquals(StackSettings().dayStartHour, state.settings.dayStartHour)
        assertFalse(state.settings.reminderEnabled)
        assertEquals(ThemeID.ICE, state.settings.theme, "the look is how the phone shows Taken, not data")
    }

    @Test
    fun testWidgetsReadTheLookFromTheStore() {
        val state = DemoData.state(at(2026, 10, 12, 21, 41), allTaken = false, zone = london)
        state.settings.theme = ThemeID.BLUSH
        val snapshot = WidgetSnapshot(state, at(2026, 10, 12, 21, 41), london)
        assertEquals(ThemeID.BLUSH, snapshot.theme)
        assertEquals(Looks.BLUSH, Looks.look(snapshot.theme))
        assertEquals(
            ThemeID.ICE, WidgetSnapshot.demo(at(2026, 10, 12, 21, 41), ThemeID.ICE, london).theme,
            "the widget gallery preview follows the look too",
        )
        assertEquals(ThemeID.SIGNAL, WidgetSnapshot(StackState(), at(2026, 10, 12, 9)).theme)
    }

    // MARK: Names

    @Test
    fun testNames() {
        assertEquals(listOf(ThemeID.SIGNAL, ThemeID.BLUSH, ThemeID.PHOSPHOR, ThemeID.ICE), ThemeID.entries.toList(), "the order in Profile")
        assertEquals(listOf("SIGNAL", "BLUSH", "PHOSPHOR", "ICE"), ThemeID.entries.map { it.label })
        assertEquals(listOf("signal", "blush", "phosphor", "ice"), ThemeID.entries.map { it.raw }, "stored in taken.json: never renamed")
        assertEquals(listOf("Signal", "Blush", "Phosphor", "Ice"), ThemeID.entries.map { it.title })
        assertEquals(ThemeID.PHOSPHOR, ThemeID.stored("Phosphor"))
        assertEquals(ThemeID.ICE, ThemeID.stored("ice"))
        assertEquals(ThemeID.SIGNAL, ThemeID.stored(""))
        assertEquals(ThemeID.SIGNAL, ThemeID.stored(null))
        assertEquals(ThemeID.entries.toList(), Looks.ALL.map { it.id })
        for (id in ThemeID.entries) assertEquals(id, Looks.look(id).id)
    }

    // MARK: Tokens

    @Test
    fun testSignalIsTheOriginalLookExactly() {
        val t = Looks.SIGNAL.tokens
        assertEquals(listOf(0x08090AL, 0x0F1012L, 0x16171AL), listOf(t.bg, t.bgRaised, t.bgInset))
        assertEquals(listOf(0xF4F4F5L, 0xA1A1AAL, 0x7C7C85L, 0x52525BL), listOf(t.fg, t.fgMuted, t.fgSubtle, t.fgFaint))
        assertEquals(0xFFFFFFL, t.lineBase)
        assertEquals(listOf(0.10, 0.18), listOf(t.line, t.lineStrong))
        assertEquals(0xA1A1AAL, t.dashBase)
        assertEquals(listOf(0.20, 0.34), listOf(t.lineDash, t.tick))
        assertEquals(listOf(0xFFB000L, 0xFFB000L, 0x08090AL, 0x7C7C85L), listOf(t.signal, t.signalInk, t.onSignal, t.bracket))
        assertEquals(listOf(0.45, 0.10), listOf(t.signalEdge, t.signalWash))
        assertEquals(listOf(0xE4E4E7L, 0x111113L, 0xFFB000L, 0xFF5F57L), listOf(t.button, t.buttonText, t.buttonLamp, t.danger))
        assertEquals(ThemeRadius.HUD, Looks.SIGNAL.radius)
        assertEquals(0f, Looks.SIGNAL.radius.frame, "square HUD frames")
        assertEquals(4f, Looks.SIGNAL.radius.panel)
        assertEquals(0f, Looks.SIGNAL.radius.lampRoundness, "square lamps")
        assertEquals(1.0, Looks.SIGNAL.glowStrength)
        assertFalse(Looks.SIGNAL.isLight)
    }

    @Test
    fun testBlushIsLightAndSofter() {
        val blush = Looks.BLUSH
        assertTrue(blush.isLight)
        assertTrue(Contrast.luminance(blush.tokens.bg) > 0.85, "a light canvas")
        assertTrue(Contrast.luminance(blush.tokens.fg) < 0.05, "ink type")
        assertTrue(blush.radius.panel > Looks.SIGNAL.radius.panel, "softer corners")
        assertTrue(blush.radius.frame > 0f)
        assertNotEquals(blush.tokens.signal, blush.tokens.signalInk, "a deeper rose wherever the rose is text")
        for (dark in listOf(Looks.SIGNAL, Looks.PHOSPHOR, Looks.ICE)) {
            assertFalse(dark.isLight)
            assertTrue(Contrast.luminance(dark.tokens.bg) < 0.01)
            assertEquals(ThemeRadius.HUD, dark.radius, "the Signal composition, recoloured")
        }
    }

    @Test
    fun testTextPassesAAInEveryLook() {
        for (look in Looks.ALL) {
            val t = look.tokens
            val name = look.label
            val wash = Contrast.over(t.signal, t.signalWash, t.bg)
            for ((label, ink) in listOf("fg" to t.fg, "fgMuted" to t.fgMuted, "fgSubtle" to t.fgSubtle, "signalInk" to t.signalInk, "danger" to t.danger)) {
                assertTrue(Contrast.ratio(ink, t.bg) >= 4.5, "$name $label on the canvas")
                assertTrue(Contrast.ratio(ink, t.bgRaised) >= 4.5, "$name $label on a panel")
            }
            assertTrue(Contrast.ratio(t.fg, wash) >= 4.5, "$name fg on the signal wash")
            assertTrue(Contrast.ratio(t.fgMuted, wash) >= 4.5, "$name muted text on the wash")
            assertTrue(Contrast.ratio(t.signalInk, wash) >= 4.5, "$name lit text on a lit chip, and a fully taken day's number")
            assertTrue(Contrast.ratio(t.buttonText, t.button) >= 4.5, "$name the primary button")
            assertTrue(Contrast.ratio(t.buttonText, t.signalInk) >= 4.5, "$name the paywall button once Pro is on")
            assertTrue(Contrast.ratio(t.onSignal, t.signal) >= 3.0, "$name the check on a lit disc")
            assertTrue(Contrast.ratio(t.signal, t.bg) >= 3.0, "$name a lit segment against the canvas")
            assertTrue(Contrast.ratio(t.fgFaint, t.bg) > 2.0, "$name dashed rings and index marks still show")
        }
    }
}
