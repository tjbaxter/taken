package com.tombaxter.taken.core.stack

import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.FrequencyEra
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.ItemDraft
import com.tombaxter.taken.core.model.Pause
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

// The mutations of Shared/StackLogic.swift's `extension StackState`, pure. Each changes the state it is called on;
// AppModel runs them on a clone and persists the result.

/** The user's order: `sortIndex`, then `createdAt`. */
val StackState.orderedItems: List<Item>
    get() = items.sortedWith(compareBy<Item> { it.sortIndex }.thenBy { it.createdAt })

fun StackState.item(id: UUID): Item? = items.firstOrNull { it.id == id }

private fun StackState.replaceItem(index: Int, transform: (Item) -> Item) {
    items = items.toMutableList().also { it[index] = transform(it[index]) }
}

/**
 * Add drafts to the stack. `itemId` gives each draft's id by its index (Android: AppModel makes the ids before the write,
 * so a write replayed onto a file that moved on stores the ids the screen holds; a fresh id each by default).
 */
fun StackState.addItems(
    drafts: List<ItemDraft>,
    now: Instant,
    itemId: (Int) -> UUID = { UUID.randomUUID() },
): List<Item> {
    var next = (items.maxOfOrNull { it.sortIndex } ?: -1) + 1
    val added = ArrayList<Item>()
    for ((index, draft) in drafts.withIndex()) {
        val name = draft.name.trim()
        if (name.isEmpty()) continue
        val code = Catalog.sanitizeCode(draft.code ?: "")
        val item = Item(
            id = itemId(index), name = name, code = code.ifEmpty { Catalog.code(name) }, frequency = draft.frequency,
            createdAt = now, sortIndex = next,
        )
        next += 1
        added.add(item)
    }
    items = items + added
    return added
}

/**
 * Replace name, code and frequency of an item. A new frequency applies from the day of `now` on; earlier days keep the
 * frequency they had.
 */
fun StackState.updateItem(id: UUID, name: String, code: String, frequency: Frequency, now: Instant) {
    val index = items.indexOfFirst { it.id == id }
    if (index < 0) return
    replaceItem(index) { current ->
        val trimmed = name.trim()
        val newName = trimmed.ifEmpty { current.name }
        val cleanCode = Catalog.sanitizeCode(code)
        var item = current.copy(name = newName, code = cleanCode.ifEmpty { Catalog.code(newName) })
        if (item.frequency != frequency) {
            val era = FrequencyEra(until = now, frequency = item.frequency)
            item = item.copy(pastFrequencies = (item.pastFrequencies ?: emptyList()) + era, frequency = frequency)
        }
        item
    }
}

fun StackState.setArchived(id: UUID, archived: Boolean, now: Instant) {
    val index = items.indexOfFirst { it.id == id }
    if (index < 0) return
    if (items[index].archived == archived) return
    if (archived) {
        replaceItem(index) { it.copy(archived = true, archivedAt = now) }
        return
    }
    // The archived stretch stays out of history, so unarchiving never turns it into missed days.
    val nextIndex = (items.maxOfOrNull { it.sortIndex } ?: 0) + 1
    replaceItem(index) { item ->
        val from = item.archivedAt
        val pauses = if (from != null) (item.pauses ?: emptyList()) + Pause(from = from, until = maxOf(from, now)) else item.pauses
        item.copy(archived = false, archivedAt = null, pauses = pauses, sortIndex = nextIndex)
    }
}

/** Delete an item and its log entries, so they never count in stats again. */
fun StackState.deleteItem(id: UUID) {
    items = items.filter { it.id != id }
    doses = doses.filter { it.itemId != id }
}

/** Reorder the active (not archived) items the way SwiftUI's onMove describes it. */
fun StackState.moveActiveItems(fromOffsets: Set<Int>, toOffset: Int) {
    val active = orderedItems.filter { !it.archived }
    val moving = fromOffsets.sorted().mapNotNull { if (it < active.size) active[it] else null }
    val remaining = active.filterIndexed { index, _ -> index !in fromOffsets }.toMutableList()
    val shift = fromOffsets.count { it < toOffset }
    val insertAt = (toOffset - shift).coerceIn(0, remaining.size)
    remaining.addAll(insertAt, moving)
    val archivedItems = orderedItems.filter { it.archived }
    val order = (remaining + archivedItems).mapIndexed { position, item -> item.id to position }.toMap()
    items = items.map { item -> order[item.id]?.let { item.copy(sortIndex = it) } ?: item }
}

/** Log one dose. `zone` is where it was taken, so the dose keeps its day after the phone changes zone. */
fun StackState.logDose(itemId: UUID, at: Instant, zone: ZoneId = ZoneId.systemDefault()): Dose? =
    insertDose(doseAt(itemId, at, zone))

/** A dose of `itemId` taken at `at` where `zone` says, with a fresh id (or the one given), not yet in any state. */
fun doseAt(itemId: UUID, at: Instant, zone: ZoneId, id: UUID = UUID.randomUUID()): Dose =
    Dose(id = id, itemId = itemId, takenAt = at, utcOffset = DayClock.offset(zone, at))

/**
 * Log a dose made before the write (Android): its id is fixed outside the mutation, so a write replayed onto a file that
 * moved on stores the same id the screen and its Undo hold. Null when the item is gone; a dose already there is kept as is.
 */
fun StackState.insertDose(dose: Dose): Dose? {
    if (items.none { it.id == dose.itemId }) return null
    if (doses.none { it.id == dose.id }) doses = doses + dose
    return dose
}

/** Log one dose, but never to an archived item, which the app no longer shows. */
fun StackState.logActiveDose(itemId: UUID, at: Instant, zone: ZoneId = ZoneId.systemDefault()): Dose? {
    val item = item(itemId) ?: return null
    if (item.archived) return null
    return logDose(itemId, at, zone)
}

/**
 * Widget row tap: log only while a dose is still pending today and the item was not logged in the last hour, so a stale
 * widget or a second tap never double logs.
 */
fun StackState.logNextDoseIfPending(itemId: UUID, now: Instant, clock: DayClock, id: UUID = UUID.randomUUID()): Dose? {
    val item = item(itemId) ?: return null
    if (item.archived) return null
    val engine = StackEngine(this, clock)
    val today = engine.itemDay(item, clock.day(now))
    if (!engine.canQuickLog(today, now)) return null
    // The id is made by the caller (Android): a write replayed onto a file that moved on stores the same dose.
    return insertDose(doseAt(itemId, now, clock.zone, id))
}

/**
 * TAKE ALL: one dose for every item that still has a pending due dose today, skipping any item logged in the last hour,
 * so a repeated tap never logs a 2x item's next dose. Nothing else is touched.
 */
fun StackState.takeAllPending(
    now: Instant,
    clock: DayClock,
    /** Each logged dose's id, by its item (Android: the same id again when the write is replayed). */
    doseId: (UUID) -> UUID = { UUID.randomUUID() },
): List<Dose> {
    val engine = StackEngine(this, clock)
    val logged = ArrayList<Dose>()
    for (row in engine.quickLogRows(engine.todaySummary(now), now)) {
        insertDose(doseAt(row.item.id, now, clock.zone, doseId(row.item.id)))?.let { logged.add(it) }
    }
    return logged
}

fun StackState.removeDoses(ids: Set<UUID>) {
    doses = doses.filter { it.id !in ids }
}

/** Remove the latest dose of an item on a given logical day. */
fun StackState.undoLastDose(itemId: UUID, day: DayKey, clock: DayClock): Dose? {
    val candidates = doses.filter { it.itemId == itemId && clock.day(it) == day }
    val last = candidates.maxByOrNull { it.takenAt } ?: return null
    doses = doses.filter { it.id != last.id }
    return last
}

fun StackState.setDoseTime(doseId: UUID, to: Instant, zone: ZoneId = ZoneId.systemDefault()) {
    val index = doses.indexOfFirst { it.id == doseId }
    if (index < 0) return
    doses = doses.toMutableList().also { it[index] = it[index].copy(takenAt = to, utcOffset = DayClock.offset(zone, to)) }
}

/** Undo: put a dose back exactly as it was, whether it was removed or had its time changed. */
fun StackState.restore(dose: Dose) {
    if (items.none { it.id == dose.itemId }) return
    val index = doses.indexOfFirst { it.id == dose.id }
    doses = if (index >= 0) doses.toMutableList().also { it[index] = dose } else doses + dose
}

/**
 * Removes the stack, every dose and the settings. The look stays: it is how the phone shows Taken, not data. So do
 * whether Today's one-time offers were answered (the nudge offer, the widget invite). The day the widget invite first
 * showed is a date from the log, so it goes: an invite already shown counts as answered.
 */
fun StackState.eraseAll() {
    val kept = settings
    items = emptyList()
    doses = emptyList()
    schemaVersion = 1
    settings = StackSettings(
        theme = kept.theme,
        nudgeOfferDone = kept.nudgeOfferDone,
        widgetInviteDone = kept.widgetInviteDone || kept.widgetInviteDay != null,
    )
}

/** Profile > Data > Export CSV: taken-log.csv. Ported from Shared/StackLogic.swift `CSVExport`. */
object CsvExport {
    const val HEADER = "date,time,item,code"
    const val FILE_NAME = "taken-log.csv"

    /** One row per dose, oldest first, in local wall-clock time. */
    fun make(state: StackState, zone: ZoneId = ZoneId.systemDefault()): String {
        val items = HashMap<UUID, Item>()
        for (item in state.items) items.putIfAbsent(item.id, item)
        val lines = mutableListOf(HEADER)
        for (dose in state.doses.sortedBy { it.takenAt }) {
            val item = items[dose.itemId] ?: continue
            val c = dose.takenAt.atZone(zone)
            val date = String.format(Locale.ROOT, "%04d-%02d-%02d", c.year, c.monthValue, c.dayOfMonth)
            val time = String.format(Locale.ROOT, "%02d:%02d", c.hour, c.minute)
            lines.add(listOf(date, time, escape(item.name), escape(item.code)).joinToString(","))
        }
        return lines.joinToString("\n") + "\n"
    }

    fun escape(field: String): String {
        if (field.none { it == ',' || it == '"' || it == '\n' || it == '\r' }) return field
        return "\"" + field.replace("\"", "\"\"") + "\""
    }
}
