package com.tombaxter.taken.data

import com.tombaxter.taken.core.todo.TodoState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/**
 * Where the To-do tab's writes go (todos.json), as [Persistence] is for taken.json: the screen updates at once, the file
 * follows through DataStore's transactional `updateData`; a file that moved on meanwhile gets the change replayed onto
 * it; once no write is on its way the screen is handed what the file holds, so a task that was not saved never shows.
 */
interface TodoPersistence {
    fun save(base: TodoState, next: TodoState, replay: (TodoState) -> Unit, settled: (TodoState) -> Unit, onFailure: () -> Unit)

    /** A write is still on its way to disk: a file emission now is older than the screen. */
    val busy: Boolean
}

/** todos.json through DataStore ([TakenStores.todos]). */
class DataStoreTodoPersistence(private val stores: TakenStores, private val scope: CoroutineScope) : TodoPersistence {
    private val inFlight = AtomicInteger(0)

    override val busy: Boolean get() = inFlight.get() > 0

    override fun save(base: TodoState, next: TodoState, replay: (TodoState) -> Unit, settled: (TodoState) -> Unit, onFailure: () -> Unit) {
        inFlight.incrementAndGet()
        scope.launch {
            val onDisk = try {
                stores.todos.updateData { latest -> if (latest == base) next else latest.clone().also(replay) }
            } catch (e: IOException) {
                onFailure()
                try {
                    stores.todos.data.first()
                } catch (unreadable: IOException) {
                    null
                }
            } finally {
                inFlight.decrementAndGet()
            }
            if (onDisk != null && inFlight.get() == 0) settled(onDisk)
        }
    }
}

/** For tests and demo captures: in memory, written at once. */
class MemoryTodoPersistence(var state: TodoState = TodoState()) : TodoPersistence {
    var writes = 0
        private set

    /** Tests: the next write fails, as a full disk would. */
    var failNext = false

    override val busy: Boolean get() = false

    override fun save(base: TodoState, next: TodoState, replay: (TodoState) -> Unit, settled: (TodoState) -> Unit, onFailure: () -> Unit) {
        if (failNext) {
            failNext = false
            onFailure()
            settled(state)
            return
        }
        state = if (state == base) next else state.clone().also(replay)
        writes += 1
        settled(state)
    }
}
