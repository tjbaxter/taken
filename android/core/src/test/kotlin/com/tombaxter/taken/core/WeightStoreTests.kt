package com.tombaxter.taken.core

import com.tombaxter.taken.core.model.JsonShapeException
import com.tombaxter.taken.core.weight.WeightCodec
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightState
import com.tombaxter.taken.core.weight.WeightUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/WeightStoreTests.swift, the codec cases: weights.json round trips in the iPhone's shape, and
 * files from earlier and later builds read. The file on disk (a missing file, the set-aside copy, one writer at a time)
 * and the model over it are :app's WeightStoreTests, on DataStore.
 */
class WeightStoreTests {

    @Test
    fun testRoundTrip() {
        assertEquals(WeightState(), WeightCodec.decode(WeightCodec.encode(WeightState())), "an empty file round trips")
        assertNull(WeightCodec.decode("{}").showsTab, "no choice made: the tab is off")

        val state = WeightState(showsTab = true, unit = WeightUnit.LB, range = WeightRange.QUARTER, offerAnswered = true)
        val first = state.log(88.35, at(2026, 10, 21, 7, 42), london)
        state.log(88.6, at(2026, 10, 20, 7, 5), london)
        val read = WeightCodec.decode(WeightCodec.encode(state))
        assertEquals(state, read)
        assertEquals(3600, read.weighIn(first.id)?.utcOffset, "where it was logged, like a dose")
        assertEquals(88.35, read.last?.kg)
        assertEquals(listOf(88.35, 88.6), read.newestFirst.map { it.kg })

        val text = WeightCodec.encode(state)
        for (key in listOf(""""showsTab":true""", """"unit":"lb"""", """"range":"90d"""", """"offerAnswered":true""", """"kg":88.35""", """"firstWeighInAt":""")) {
            assertTrue(text.contains(key), "$key in $text")
        }
        assertEquals("weights.json", WeightCodec.FILE_NAME)
        assertEquals(
            text.indexOf("\"firstWeighInAt\"") < text.indexOf("\"offerAnswered\"") && text.indexOf("\"offerAnswered\"") < text.indexOf("\"weighIns\""),
            true, "keys written sorted, as the iPhone's encoder writes them",
        )
    }

    /**
     * Missing fields (an earlier build), unknown ones and an unknown unit (a later one) never cost the file; one
     * unreadable weigh-in never costs the others.
     */
    @Test
    fun testDecodesOlderAndNewerFiles() {
        val json = """
            {"weighIns":[
              {"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","kg":88.35,"weighedAt":1792000000,"utcOffset":3600},
              {"kg":88.6,"weighedAt":1791900000},
              {"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","weighedAt":1791800000},
              {"kg":"heavy","weighedAt":1791700000},
              {"kg":-3,"weighedAt":1791600000}
            ],"unit":"st","range":"decade","showsTab":false,"futureKey":[1,2,3]}
        """.trimIndent()
        val state = WeightCodec.decode(json)
        assertEquals(listOf(88.35, 88.6), state.weighIns.map { it.kg })
        assertEquals(3600, state.weighIns.first().utcOffset)
        assertNull(state.weighIns.last().utcOffset)
        assertNull(state.unit, "stones are not a unit this build knows: the locale's")
        assertNull(state.range, "an unknown range reads as All")
        assertEquals(false, state.showsTab, "an explicit choice is kept")
        assertFalse(state.offerAnswered)
        assertNull(state.firstWeighInAt)
        assertEquals(1, state.schemaVersion)
        assertEquals(WeightState(), WeightCodec.decode("{}"))
        assertFailsWith<JsonShapeException>("not JSON at all: the store sets it aside") { WeightCodec.decode("not json") }
        assertFailsWith<JsonShapeException>("not an object") { WeightCodec.decode("[]") }
    }
}
