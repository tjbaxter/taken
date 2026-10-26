package com.tombaxter.taken

import androidx.test.core.app.ApplicationProvider
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.data.DataStorePersistence
import com.tombaxter.taken.data.LedgerFile
import com.tombaxter.taken.data.TakenStores
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
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
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/StoreTests.swift, the file cases, on DataStore (SPEC-ANDROID 5): taken.json round trips; writes
 * from one process are serialised by DataStore's single writer (the iPhone's NSFileCoordinator case); an unreadable file
 * is set aside as taken-unreadable-<unix>.json, never overwritten silently; Erase all data removes the set-aside copies
 * and leaves pro.json.
 */
@RunWith(RobolectricTestRunner::class)
class StoreTests {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    /** Each test its own folder: DataStore allows one active store per file in a process. */
    private val folder = File(context.cacheDir, "stores-${java.util.UUID.randomUUID()}")

    @After
    fun tearDown() {
        scope.cancel()
        folder.deleteRecursively()
    }

    private fun item(name: String, code: String) =
        Item(name = name, code = code, frequency = Frequency.Daily(1), createdAt = Instant.ofEpochSecond(1_790_838_000L), sortIndex = 0)

    @Test
    fun testRoundTripAndUpdates() = runBlocking {
        val stores = TakenStores(context, scope, folder)
        assertEquals(StackState(), stores.stack.data.first(), "a missing file reads as an empty stack")
        val vd3 = item("Vitamin D3", "VD3")
        val state = StackState(items = listOf(vd3))
        state.logDose(vd3.id, Instant.ofEpochSecond(1_791_000_000L, 123_000_000L), ZoneId.of("Europe/London"))
        state.settings.theme = ThemeID.BLUSH
        stores.stack.updateData { state }
        assertEquals(state, stores.stack.data.first())
        val text = File(folder, "taken.json").readText()
        assertTrue(text.contains("\"theme\":\"blush\""), text)
        assertTrue(text.contains("\"takenAt\":1791000000.123"), "the iPhone's shape on disk: $text")
    }

    @Test
    fun testWritesInOneProcessNeverLoseADose() = runBlocking {
        val stores = TakenStores(context, scope, folder)
        val vd3 = item("Vitamin D3", "VD3")
        stores.stack.updateData { StackState(items = listOf(vd3)) }
        val writers = (0 until 60).map { index ->
            scope.async {
                stores.stack.updateData { latest ->
                    latest.clone().also { it.logDose(vd3.id, Instant.ofEpochSecond(1_791_000_000L + index), ZoneId.of("UTC")) }
                }
            }
        }
        writers.forEach { it.await() }
        assertEquals(60, stores.stack.data.first().doses.size, "DataStore's updateData is one transaction at a time")
    }

    @Test
    fun testAnUnreadableFileIsSetAsideNotOverwrittenSilently() = runBlocking {
        folder.mkdirs()
        File(folder, "taken.json").writeText("not json")
        val stores = TakenStores(context, scope, folder)
        assertEquals(StackState(), stores.stack.data.first(), "the stack starts fresh")
        val siblings = folder.list()!!.toList()
        assertTrue(siblings.any { it.startsWith("taken-unreadable-") && it.endsWith(".json") }, "$siblings")
        val setAside = folder.listFiles()!!.first { it.name.startsWith("taken-unreadable-") }
        assertEquals("not json", setAside.readText(), "the raw bytes are kept")

        File(folder, "pro.json").writeText("""{"firstSeenAt":1791000000,"legacyLog":false,"prices":{}}""")
        File(folder, "todos-unreadable-2.json").writeText("x")
        stores.removeSetAsideCopies()
        val left = folder.list()!!.toSet()
        assertFalse(left.any { it.contains("-unreadable-") }, "Erase all data removes the set-aside copies: $left")
        assertTrue(left.contains("pro.json"), "the Taken Pro file stays")
    }

    /**
     * Erase all data removes the CSV copies Export wrote (whole copies of the log and the weigh-ins), and Taken's start
     * removes any older than a day.
     */
    @Test
    fun testEraseAllDataRemovesTheExportedCopies() = runBlocking {
        val stores = TakenStores(context, scope, folder)
        val exports = stores.exportsDir.apply { mkdirs() }
        File(exports, "taken-log.csv").writeText("date,time,item\n")
        File(exports, "taken-weight.csv").writeText("date,time,kg\n")
        DataStorePersistence(stores, scope).eraseExtras()
        withTimeout(5_000) {
            while (stores.exportsDir.exists()) kotlinx.coroutines.delay(10)
        }
        assertFalse(stores.exportsDir.exists(), "no copy of the log outlives Erase all data")

        val fresh = File(stores.exportsDir.apply { mkdirs() }, "taken-log.csv").apply { writeText("x") }
        val old = File(stores.exportsDir, "taken-weight.csv").apply { writeText("x") }
        val now = System.currentTimeMillis()
        fresh.setLastModified(now - 60_000)
        old.setLastModified(now - TakenStores.STALE_EXPORT_MS - 60_000)
        stores.removeStaleExports(now)
        assertTrue(fresh.exists(), "a share from a minute ago may still be read by the app it went to")
        assertFalse(old.exists(), "one from yesterday goes")
    }

    @Test
    fun testTheLedgerAndTheProfileRoundTrip() = runBlocking {
        val stores = TakenStores(context, scope, folder)
        assertEquals(LedgerFile(null), stores.ledger.data.first(), "missing until the app first runs")
        val ledger = ProLedger(firstSeenAt = Instant.ofEpochSecond(1_791_000_000L), firstDoseAt = Instant.ofEpochSecond(1_791_000_100L))
        stores.ledger.updateData { LedgerFile(ledger) }
        assertEquals(ledger, stores.ledger.data.first().ledger)
        stores.profile.updateData { Profile("Thomas Baxter") }
        assertEquals(Profile("Thomas Baxter"), stores.profile.data.first())
    }

    @Test
    fun testThePersistenceReplaysOntoAFileThatMovedOn() = runBlocking {
        val stores = TakenStores(context, scope, folder)
        val persistence = DataStorePersistence(stores, scope)
        val vd3 = item("Vitamin D3", "VD3")
        val zinc = item("Zinc", "ZNC")
        val base = StackState(items = listOf(vd3))
        stores.stack.updateData { base }
        // Meanwhile another surface added Zinc: the screen's write is replayed onto the file, so nothing is lost.
        stores.stack.updateData { it.clone().also { s -> s.items = s.items + zinc } }
        val next = base.clone().also { it.logDose(vd3.id, Instant.ofEpochSecond(1_791_000_000L), ZoneId.of("UTC")) }
        persistence.saveStack(base, next, { it.logDose(vd3.id, Instant.ofEpochSecond(1_791_000_000L), ZoneId.of("UTC")) }) {}
        withTimeout(5_000) {
            while (stores.stack.data.first().doses.isEmpty()) kotlinx.coroutines.delay(10)
        }
        val saved = stores.stack.data.first()
        assertEquals(listOf("Vitamin D3", "Zinc"), saved.items.map { it.name })
        assertEquals(1, saved.doses.size)
    }
}
