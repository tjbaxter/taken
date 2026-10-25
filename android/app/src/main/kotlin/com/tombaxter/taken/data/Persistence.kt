package com.tombaxter.taken.data

import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.profile.Profile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/**
 * Where AppModel's writes go. The screen updates at once from the new state; the file follows, transactionally. If the
 * file moved on meanwhile (a widget, later), the mutation runs again on what is there, so nothing written elsewhere is
 * lost.
 */
interface Persistence {
    /** Persist `next`, made from `base` by `replay`; on a file that is no longer `base`, `replay` runs on the file. */
    fun saveStack(base: StackState, next: StackState, replay: (StackState) -> Unit, onFailure: () -> Unit)

    /** pro.json's small writes: the first dose, the paywall's bookkeeping. */
    fun updateLedger(transform: (ProLedger?) -> ProLedger?)

    fun saveProfile(profile: Profile)

    /** The profile photo as JPEG bytes, or null to remove it. */
    fun savePhoto(jpeg: ByteArray?)

    /** Erase all data's files beyond the stack: the profile, the photo and every set-aside unreadable copy. */
    fun eraseExtras()

    /** A write is still on its way to disk: a file emission now is older than the screen. */
    val busy: Boolean
}

/** The app's persistence: [TakenStores] through DataStore. */
class DataStorePersistence(private val stores: TakenStores, private val scope: CoroutineScope) : Persistence {
    private val inFlight = AtomicInteger(0)

    override val busy: Boolean get() = inFlight.get() > 0

    override fun saveStack(base: StackState, next: StackState, replay: (StackState) -> Unit, onFailure: () -> Unit) {
        inFlight.incrementAndGet()
        scope.launch {
            try {
                stores.stack.updateData { latest -> if (latest == base) next else latest.clone().also(replay) }
            } catch (e: IOException) {
                onFailure()
            } finally {
                inFlight.decrementAndGet()
            }
        }
    }

    override fun updateLedger(transform: (ProLedger?) -> ProLedger?) {
        scope.launch {
            runCatching { stores.ledger.updateData { file -> LedgerFile(transform(file.ledger)) } }
        }
    }

    override fun saveProfile(profile: Profile) {
        scope.launch { runCatching { stores.profile.updateData { profile } } }
    }

    override fun savePhoto(jpeg: ByteArray?) {
        scope.launch {
            withContext(Dispatchers.IO) {
                runCatching {
                    if (jpeg == null) stores.photoFile.delete() else stores.photoFile.writeBytes(jpeg)
                }
            }
        }
    }

    override fun eraseExtras() {
        saveProfile(Profile())
        savePhoto(null)
        scope.launch { withContext(Dispatchers.IO) { stores.removeSetAsideCopies() } }
    }
}

/** For tests and demo captures: everything in memory, written at once. */
class MemoryPersistence(
    var stack: StackState = StackState(),
    var ledger: ProLedger? = null,
    var profile: Profile = Profile(),
    var photo: ByteArray? = null,
) : Persistence {
    var stackWrites = 0
        private set
    var extrasErased = false
        private set

    override val busy: Boolean get() = false

    override fun saveStack(base: StackState, next: StackState, replay: (StackState) -> Unit, onFailure: () -> Unit) {
        stack = if (stack == base) next else stack.clone().also(replay)
        stackWrites += 1
    }

    override fun updateLedger(transform: (ProLedger?) -> ProLedger?) {
        ledger = transform(ledger)
    }

    override fun saveProfile(profile: Profile) {
        this.profile = profile
    }

    override fun savePhoto(jpeg: ByteArray?) {
        photo = jpeg
    }

    override fun eraseExtras() {
        profile = Profile()
        photo = null
        extrasErased = true
    }
}
