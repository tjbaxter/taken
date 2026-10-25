package com.tombaxter.taken.data

import androidx.core.util.AtomicFile
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.profile.Profile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/**
 * Where AppModel's writes go. The screen updates at once from the new state; the file follows, transactionally. If the
 * file moved on meanwhile (a widget, later), the mutation runs again on what is there, so nothing written elsewhere is
 * lost. Once the last write on its way is done, the screen is handed what the file holds, so it never keeps showing
 * something that was not saved (the iPhone applies a write only after it is saved, Taken/AppModel.swift `write`).
 */
interface Persistence {
    /**
     * Persist `next`, made from `base` by `replay`; on a file that is no longer `base`, `replay` runs on the file.
     * `settled` gets what the file holds once no write of the app's is still on its way, after a save or a failed one.
     * `onFailure` runs when this write could not be saved.
     */
    fun saveStack(
        base: StackState,
        next: StackState,
        replay: (StackState) -> Unit,
        settled: (StackState) -> Unit = {},
        onFailure: () -> Unit,
    )

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

    /** The photo's writes one at a time, in the order they were asked for, so a quick set then remove cannot race. */
    private val photoLock = Mutex()

    override fun saveStack(
        base: StackState,
        next: StackState,
        replay: (StackState) -> Unit,
        settled: (StackState) -> Unit,
        onFailure: () -> Unit,
    ) {
        inFlight.incrementAndGet()
        scope.launch {
            val onDisk = try {
                stores.stack.updateData { latest -> if (latest == base) next else latest.clone().also(replay) }
            } catch (e: IOException) {
                onFailure()
                // Nothing was written: the file still holds what it held before, and the screen goes back to it.
                try {
                    stores.stack.data.first()
                } catch (unreadable: IOException) {
                    null
                }
            } finally {
                inFlight.decrementAndGet()
            }
            if (onDisk != null && inFlight.get() == 0) settled(onDisk)
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
            photoLock.withLock {
                withContext(Dispatchers.IO) { PhotoFile.write(stores.photoFile, jpeg) }
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

    override fun saveStack(
        base: StackState,
        next: StackState,
        replay: (StackState) -> Unit,
        settled: (StackState) -> Unit,
        onFailure: () -> Unit,
    ) {
        stack = if (stack == base) next else stack.clone().also(replay)
        stackWrites += 1
        settled(stack)
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

/**
 * The profile photo on disk through [AtomicFile], Android's documented way to replace a file whole: the new bytes go to a
 * side file that is renamed over the old one only once written, so a kill or a full disk mid-write leaves the last photo
 * intact (https://developer.android.com/reference/androidx/core/util/AtomicFile). The JSON files get the same from
 * DataStore.
 */
object PhotoFile {
    /** Writes the photo, or removes it when `jpeg` is null. False when it could not be written; the old photo stays. */
    fun write(file: File, jpeg: ByteArray?): Boolean {
        val atomic = AtomicFile(file)
        if (jpeg == null) {
            atomic.delete()
            return true
        }
        var out: FileOutputStream? = null
        return try {
            out = atomic.startWrite()
            out.write(jpeg)
            atomic.finishWrite(out)
            true
        } catch (e: IOException) {
            if (out != null) atomic.failWrite(out)
            false
        }
    }

    /** The photo as last written whole, or null when there is none or it cannot be read. */
    fun read(file: File): ByteArray? = try {
        AtomicFile(file).readFully()
    } catch (e: IOException) {
        null
    }
}
