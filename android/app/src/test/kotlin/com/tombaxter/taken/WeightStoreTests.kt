package com.tombaxter.taken

import androidx.test.core.app.ApplicationProvider
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightState
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.data.DataStoreWeightPersistence
import com.tombaxter.taken.data.MemoryWeightPersistence
import com.tombaxter.taken.data.TakenStores
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/WeightStoreTests.swift, the file cases, on DataStore (SPEC-ANDROID 5): weights.json round trips
 * in the iPhone's shape, a missing file is no weigh-ins and the tab off, an unreadable file is set aside and Erase all
 * data removes the copy, one writer at a time never loses a weigh-in, and the model persists every choice. The codec's
 * older and newer files are :core's WeightStoreTests.
 */
@RunWith(RobolectricTestRunner::class)
class WeightStoreTests {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val folder = File(context.cacheDir, "weights-${java.util.UUID.randomUUID()}")
    private val london = ZoneId.of("Europe/London")

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0): Instant =
        ZonedDateTime.of(year, month, day, hour, minute, 0, 0, london).toInstant()

    @After
    fun tearDown() {
        scope.cancel()
        folder.deleteRecursively()
    }

    @Test
    fun testRoundTrip() = runBlocking {
        val stores = TakenStores(context, scope, folder)
        assertEquals(WeightState(), stores.weights.data.first(), "a missing file is no weigh-ins and the tab off")
        val state = WeightState(showsTab = true, unit = WeightUnit.LB, range = WeightRange.QUARTER, offerAnswered = true)
        val first = state.log(88.35, at(2026, 10, 21, 7, 42), london)
        state.log(88.6, at(2026, 10, 20, 7, 5), london)
        stores.weights.updateData { state }
        val read = stores.weights.data.first()
        assertEquals(state, read)
        assertEquals(3600, read.weighIn(first.id)?.utcOffset, "where it was logged, like a dose")
        val text = File(folder, "weights.json").readText()
        for (key in listOf("\"showsTab\":true", "\"unit\":\"lb\"", "\"range\":\"90d\"", "\"offerAnswered\":true", "\"kg\":88.35", "\"firstWeighInAt\":")) {
            assertTrue(text.contains(key), "$key in $text")
        }
    }

    @Test
    fun testAnUnreadableFileIsKeptAsideNotOverwritten() = runBlocking {
        folder.mkdirs()
        File(folder, "weights.json").writeText("not json")
        val stores = TakenStores(context, scope, folder)
        assertEquals(WeightState(), stores.weights.data.first())
        stores.weights.updateData { it.clone().also { s -> s.log(88.0, Instant.now(), london) } }
        val siblings = folder.list()!!.toList()
        assertTrue(siblings.any { it.startsWith("weights-unreadable-") && it.endsWith(".json") }, "$siblings")
        assertEquals(1, stores.weights.data.first().weighIns.size)

        // Erase all data takes the set-aside copy and leaves every other file.
        File(folder, "taken.json").writeText("x")
        stores.removeSetAsideCopies()
        val left = folder.list()!!.toSet()
        assertFalse(left.any { it.contains("-unreadable-") }, "$left")
        assertTrue(left.containsAll(listOf("taken.json", "weights.json")), "$left")
    }

    /** DataStore's `updateData` is one transaction at a time: no weigh-in is lost (the iPhone's several writers case). */
    @Test
    fun testConcurrentWritersNeverLoseAWeighIn() = runBlocking {
        val stores = TakenStores(context, scope, folder)
        stores.weights.updateData { WeightState(showsTab = true) }
        val writers = (0 until 6).flatMap { writer ->
            (0 until 20).map { index ->
                scope.async {
                    val whenAt = Instant.ofEpochSecond(1_792_000_000L + (writer * 1_000 + index) * 60L)
                    stores.weights.updateData { latest -> latest.clone().also { it.log(80 + index / 10.0, whenAt, london) } }
                }
            }
        }
        writers.forEach { it.await() }
        val state = stores.weights.data.first()
        assertEquals(120, state.weighIns.size)
        assertEquals(120, state.weighIns.map { it.id }.toSet().size)
        assertEquals(true, state.showsTab, "a write never drops the settings")
    }

    /** The model reads and writes through the store: the tab, the unit, the range and the offer's answer persist. */
    @Test
    fun testTheModelPersistsEveryChoice() = runBlocking {
        val stores = TakenStores(context, scope, folder)
        val now = at(2026, 10, 22, 9)
        val model = WeightModel(DataStoreWeightPersistence(stores, scope), stores.weights.data.first(), clockNow = { now })
        assertFalse(model.showsTab, "off by default")
        assertFalse(model.showsDataRows, "nothing in Profile's Data until the tab is on")
        model.setShowsTab(true)
        model.setUnit(WeightUnit.KG)
        model.setRange(WeightRange.WEEK)
        val saved = model.log(88.35, london)
        assertEquals(now, saved.weighedAt)
        withTimeout(5_000) { while (stores.weights.data.first().weighIns.isEmpty() || model.persistence.busy) delay(10) }
        val reread = WeightModel(MemoryWeightPersistence(), stores.weights.data.first(), clockNow = { now })
        assertTrue(reread.showsTab)
        assertEquals(WeightUnit.KG, reread.unit)
        assertEquals(WeightRange.WEEK, reread.range)
        assertEquals(listOf(saved), reread.state.weighIns)
        assertTrue(reread.showsDataRows)

        val memory = WeightModel(MemoryWeightPersistence(reread.state), reread.state, clockNow = { now })
        val before = assertNotNull(memory.update(saved.id, 88.4, at(2026, 10, 21, 7), london))
        assertEquals(saved, before, "Undo puts this back")
        assertEquals(88.4, memory.state.weighIn(saved.id)?.kg)
        memory.restore(before)
        assertEquals(listOf(saved), memory.state.weighIns)
        assertEquals(saved, memory.delete(saved.id))
        assertTrue(memory.isEmpty)

        assertEquals(
            "Added 2 weigh-ins, read in kg.",
            memory.importCsv("date,kg\n2026-10-20,88.6\n2026-10-21,88.35\n", Locale.UK, london),
        )
        assertEquals("Nothing new: that weigh-in is already in Taken.", memory.importCsv("date,kg\n2026-10-20,88.6\n", Locale.UK, london))
        assertEquals(WeightCopy.NOT_FOUND, memory.importCsv("no weights here", Locale.UK, london))
        assertEquals("date,time,kg", memory.csv(london).lines().first())
    }

    /** A save that fails (a full disk) puts the screen back and says so, as AppModel's writes do. */
    @Test
    fun testAFailedSavePutsTheScreenBack() {
        val persistence = MemoryWeightPersistence()
        val model = WeightModel(persistence, clockNow = { at(2026, 10, 22, 9) })
        var told = false
        model.onWriteFailed = { told = true }
        persistence.failNext = true
        model.log(88.0, london)
        assertTrue(told)
        assertTrue(model.isEmpty, "a weigh-in that was not saved never shows")
    }
}
