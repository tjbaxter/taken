package com.tombaxter.taken.core

import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.FrequencyEra
import com.tombaxter.taken.core.model.ItemDraft
import com.tombaxter.taken.core.model.JsonShapeException
import com.tombaxter.taken.core.model.Pause
import com.tombaxter.taken.core.model.StackCodec
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.model.TakenJson
import com.tombaxter.taken.core.stack.CsvExport
import com.tombaxter.taken.core.stack.addItems
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.stack.setArchived
import com.tombaxter.taken.core.stack.updateItem
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/StoreTests.swift, the codec and CSV cases: taken.json round trips in the iPhone's shape, older
 * files with missing keys decode, a corrupt file is refused (the store then sets it aside: :app's StoreTests), and the
 * CSV export. The single-writer and set-aside cases run on DataStore in :app.
 */
class StoreTests {

    @Test
    fun testRoundTrip() {
        assertEquals(StackState(), StackCodec.decode(StackCodec.encode(StackState())), "an empty stack round trips")

        val created = at(2026, 10, 1, 8)
        val state = StackState(
            items = listOf(
                makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0),
                makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = created, sortIndex = 1),
                makeItem("Zinc", "ZNC", Frequency.AlternateDays, created = created, sortIndex = 2),
                makeItem("Minoxidil", "MIN", Frequency.Weekdays(setOf(2, 4, 6)), created = created, sortIndex = 3),
            ),
        )
        state.logDose(state.items[0].id, Instant.ofEpochSecond(1_791_000_000L, 123_000_000L), london)
        state.updateItem(state.items[2].id, name = "Zinc", code = "ZNC", frequency = Frequency.onceDaily, now = at(2026, 10, 5, 9))
        state.setArchived(state.items[3].id, archived = true, now = at(2026, 10, 6, 9))
        state.setArchived(state.items[3].id, archived = false, now = at(2026, 10, 9, 9))
        state.settings = StackSettings.fromDayStartHour(3, reminderEnabled = true, reminderMinutes = 20 * 60 + 30, hapticsEnabled = false)
        assertEquals(3600, state.doses.firstOrNull()?.utcOffset, "BST")
        assertEquals(listOf(FrequencyEra(until = at(2026, 10, 5, 9), frequency = Frequency.AlternateDays)), state.items[2].pastFrequencies)
        assertEquals(listOf(Pause(from = at(2026, 10, 6, 9), until = at(2026, 10, 9, 9))), state.items[3].pauses)

        val text = StackCodec.encode(state)
        assertEquals(state, StackCodec.decode(text))
        assertTrue(text.contains("\"takenAt\":1791000000.123"), "seconds since 1970 as a plain number: $text")
        assertTrue(text.contains(state.items[0].id.toString().uppercase()), "UUIDs uppercase, as the iPhone writes them")
        assertTrue(text.contains("\"createdAt\":${created.epochSecond},"), "a whole second has no fraction")
    }

    @Test
    fun testUpdateReturnsValueAndPersists() {
        val state = StackState()
        val added = state.addItems(listOf(ItemDraft("Creatine")), at(2026, 10, 12, 9))
        assertEquals("CRE", added.firstOrNull()?.code)
        assertEquals(1, StackCodec.decode(StackCodec.encode(state)).items.size)
    }

    @Test
    fun testDecodesOlderFilesWithMissingKeys() {
        val json = """{"items":[{"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","name":"Zinc","code":"ZNC","frequency":{"kind":"alt"},"createdAt":1791000000,"archived":false,"sortIndex":0}],"doses":[{"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","itemId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","takenAt":1791000000}]}"""
        val state = StackCodec.decode(json)
        assertEquals(Frequency.AlternateDays, state.items.firstOrNull()?.frequency)
        assertEquals(StackSettings(), state.settings, "missing settings fall back to defaults")
        assertNull(state.items.firstOrNull()?.archivedAt)
        assertNull(state.items.firstOrNull()?.pastFrequencies, "files from before frequency history still load")
        assertNull(state.items.firstOrNull()?.pauses)
        assertEquals(1, state.doses.size)
        assertNull(state.doses.firstOrNull()?.utcOffset, "doses from before offsets were recorded still load")
        assertEquals(UUID.fromString("6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F"), state.items.first().id, "lowercase or uppercase")
    }

    /** What the store sets aside: a file that is not JSON, or an item missing a required field, is refused whole. */
    @Test
    fun testACorruptFileIsRefusedWhole() {
        assertFailsWith<JsonShapeException> { StackCodec.decode("not json") }
        assertFailsWith<JsonShapeException> { StackCodec.decode("[1,2]") }
        assertFailsWith<JsonShapeException> {
            StackCodec.decode("""{"items":[{"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","name":"Zinc"}]}""")
        }
        assertFailsWith<JsonShapeException> {
            StackCodec.decode("""{"doses":[{"id":"nope","itemId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","takenAt":1}]}""")
        }
        // A bad optional setting is its default and never costs the file.
        val lenient = StackCodec.decode("""{"settings":{"wakeMinutes":"seven","reminderMinutes":"x","widgetInviteDay":true}}""")
        assertEquals(StackSettings(), lenient.settings)
    }

    @Test
    fun testDatesKeepTheirMicroseconds() {
        val fraction = Instant.ofEpochSecond(1_760_510_520L, 250_000_000L)
        assertEquals("1760510520.25", TakenJson.instant(fraction).content)
        assertEquals("1760510520", TakenJson.instant(Instant.ofEpochSecond(1_760_510_520L)).content)
        // The iPhone writes a double: its nearest decimal reads back to the same microsecond.
        val dose = StackCodec.decodeDose(TakenJson.parse("""{"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","itemId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","takenAt":1791000000.1229999}"""))
        assertEquals(Instant.ofEpochSecond(1_791_000_000L, 123_000_000L), dose.takenAt)
        assertEquals(Dose(dose.id, dose.itemId, dose.takenAt), StackCodec.decodeDose(StackCodec.encodeDose(dose)))
    }

    @Test
    fun testCSVExport() {
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val odd = makeItem("Fish Oil, \"Triple\"", "FSH", created = created, sortIndex = 1)
        val state = StackState(items = listOf(vd3, odd))
        state.logDose(odd.id, at(2026, 10, 12, 19, 5), london)
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        state.doses = state.doses + Dose(itemId = UUID.randomUUID(), takenAt = at(2026, 10, 12, 8))

        val csv = CsvExport.make(state, london)
        val lines = csv.split("\n").filter { it.isNotEmpty() }
        assertEquals(
            listOf("date,time,item,code", "2026-10-12,07:42,Vitamin D3,VD3", "2026-10-12,19:05,\"Fish Oil, \"\"Triple\"\"\",FSH"),
            lines,
        )
        assertTrue(csv.endsWith("\n"), "a trailing newline")
        assertEquals("taken-log.csv", CsvExport.FILE_NAME)
    }
}
