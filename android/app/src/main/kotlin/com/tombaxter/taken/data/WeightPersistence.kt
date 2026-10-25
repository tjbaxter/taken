package com.tombaxter.taken.data

import com.tombaxter.taken.core.weight.WeightState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/**
 * Where the Weight tab's writes go (weights.json), as [Persistence] is for taken.json: the screen updates at once, the
 * file follows through DataStore's transactional `updateData`; a file that moved on meanwhile gets the change replayed
 * onto it; once no write is on its way the screen is handed what the file holds, so a weigh-in that was not saved never
 * shows (the iPhone's WeightModel applies a write only once the coordinated write succeeded).
 */
interface WeightPersistence {
    fun save(base: WeightState, next: WeightState, replay: (WeightState) -> Unit, settled: (WeightState) -> Unit, onFailure: () -> Unit)

    /** A write is still on its way to disk: a file emission now is older than the screen. */
    val busy: Boolean
}

/** weights.json through DataStore ([TakenStores.weights]). */
class DataStoreWeightPersistence(private val stores: TakenStores, private val scope: CoroutineScope) : WeightPersistence {
    private val inFlight = AtomicInteger(0)

    override val busy: Boolean get() = inFlight.get() > 0

    override fun save(base: WeightState, next: WeightState, replay: (WeightState) -> Unit, settled: (WeightState) -> Unit, onFailure: () -> Unit) {
        inFlight.incrementAndGet()
        scope.launch {
            val onDisk = try {
                stores.weights.updateData { latest -> if (latest == base) next else latest.clone().also(replay) }
            } catch (e: IOException) {
                onFailure()
                try {
                    stores.weights.data.first()
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
class MemoryWeightPersistence(var state: WeightState = WeightState()) : WeightPersistence {
    var writes = 0
        private set

    /** Tests: the next write fails, as a full disk would. */
    var failNext = false

    override val busy: Boolean get() = false

    override fun save(base: WeightState, next: WeightState, replay: (WeightState) -> Unit, settled: (WeightState) -> Unit, onFailure: () -> Unit) {
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
