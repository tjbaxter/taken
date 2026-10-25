package com.tombaxter.taken.data

import android.content.Context
import androidx.datastore.core.CorruptionException
import androidx.datastore.core.DataStore
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.Serializer
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import com.tombaxter.taken.core.model.JsonShapeException
import com.tombaxter.taken.core.model.StackCodec
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProLedgerCodec
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.profile.ProfileCodec
import com.tombaxter.taken.core.weight.WeightCodec
import com.tombaxter.taken.core.weight.WeightState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.io.File
import java.io.InputStream
import java.io.OutputStream

/**
 * One of Taken's JSON files through DataStore (SPEC-ANDROID 5.1): the iPhone's shapes, written whole and transactionally
 * (`updateData` is DataStore's read-modify-write, as NSFileCoordinator is the iPhone's). A file the codec cannot read
 * throws [CorruptionException], which the store's handler answers.
 */
class JsonFileSerializer<T>(
    override val defaultValue: T,
    private val decode: (String) -> T,
    private val encode: (T) -> String,
) : Serializer<T> {
    override suspend fun readFrom(input: InputStream): T {
        val bytes = input.readBytes()
        if (bytes.isEmpty()) return defaultValue
        return try {
            decode(bytes.decodeToString())
        } catch (e: JsonShapeException) {
            throw CorruptionException("unreadable JSON", e)
        }
    }

    override suspend fun writeTo(t: T, output: OutputStream) {
        output.write(encode(t).encodeToByteArray())
    }
}

/** pro.json may not exist yet: the ledger the app has not written reads as null. */
data class LedgerFile(val ledger: ProLedger?)

/**
 * Taken's files, one DataStore each, created once per process in [com.tombaxter.taken.TakenApp] (DataStore's rule: never
 * more than one instance per file in a process). Files live in `files/datastore/<name>`, the photo in `files/`.
 */
class TakenStores(
    context: Context,
    scope: CoroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob()),
    /** `files/datastore`, as `Context.dataStoreFile` places DataStore's files; tests give their own folder. */
    folder: File? = null,
) {
    private val app = context.applicationContext
    val directory: File = folder ?: File(app.filesDir, "datastore")
    val photoFile: File = File(folder ?: app.filesDir, PHOTO_FILE)

    private fun file(name: String): File = File(directory, name)

    val stack: DataStore<StackState> = DataStoreFactory.create(
        serializer = JsonFileSerializer(StackState(), StackCodec::decode, StackCodec::encode),
        // An unreadable taken.json is kept aside, never overwritten silently, and the stack starts fresh (the iPhone's
        // TakenStore.readForWrite).
        corruptionHandler = ReplaceFileCorruptionHandler { setAside(STACK_FILE, "taken-unreadable-"); StackState() },
        scope = scope,
        produceFile = { file(STACK_FILE) },
    )

    val ledger: DataStore<LedgerFile> = DataStoreFactory.create(
        serializer = JsonFileSerializer(
            LedgerFile(null),
            { LedgerFile(ProLedgerCodec.decode(it)) },
            { file -> file.ledger?.let(ProLedgerCodec::encode) ?: "" },
        ),
        // Everything in pro.json can be worked out again: an unreadable one reads as none, as on the iPhone.
        corruptionHandler = ReplaceFileCorruptionHandler { LedgerFile(null) },
        scope = scope,
        produceFile = { file(LEDGER_FILE) },
    )

    /**
     * weights.json, the Weight tab's file (SPEC-ANDROID 5.1 and 12). An unreadable file is kept aside as
     * `weights-unreadable-<unix>.json` and the tab starts empty, as the iPhone's WeightStore.readForWrite does.
     */
    val weights: DataStore<WeightState> = DataStoreFactory.create(
        serializer = JsonFileSerializer(WeightState(), WeightCodec::decode, WeightCodec::encode),
        corruptionHandler = ReplaceFileCorruptionHandler { setAside(WEIGHTS_FILE, "weights-unreadable-"); WeightState() },
        scope = scope,
        produceFile = { file(WEIGHTS_FILE) },
    )

    val profile: DataStore<Profile> = DataStoreFactory.create(
        serializer = JsonFileSerializer(Profile(), ProfileCodec::decode, ProfileCodec::encode),
        corruptionHandler = ReplaceFileCorruptionHandler { Profile() },
        scope = scope,
        produceFile = { file(PROFILE_FILE) },
    )

    /** Copies an unreadable file next to itself as `<prefix><unix seconds>.json` before it is replaced. */
    private fun setAside(name: String, prefix: String) {
        val file = file(name)
        if (!file.exists()) return
        val stamp = System.currentTimeMillis() / 1000
        runCatching { file.copyTo(File(file.parentFile, "$prefix$stamp.json"), overwrite = true) }
    }

    /** Erase all data: the copies a write set aside go too (`taken-unreadable-*`, and the to-do and weight ones). */
    fun removeSetAsideCopies() {
        val names = directory.list() ?: return
        for (name in names) {
            val setAside = SET_ASIDE_PREFIXES.any { name.startsWith(it) } && name.endsWith(".json")
            if (setAside) File(directory, name).delete()
        }
    }

    companion object {
        const val STACK_FILE = "taken.json"
        const val LEDGER_FILE = "pro.json"
        const val PROFILE_FILE = "profile.json"
        const val WEIGHTS_FILE = WeightCodec.FILE_NAME
        const val PHOTO_FILE = "profile-photo.jpg"
        val SET_ASIDE_PREFIXES = listOf("taken-unreadable-", "todos-unreadable-", "weights-unreadable-")
    }
}
