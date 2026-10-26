package com.tombaxter.taken.core.todo

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.TakenJson
import com.tombaxter.taken.core.model.asArray
import com.tombaxter.taken.core.model.asBool
import com.tombaxter.taken.core.model.asInstant
import com.tombaxter.taken.core.model.asInt
import com.tombaxter.taken.core.model.asObject
import com.tombaxter.taken.core.model.asString
import com.tombaxter.taken.core.model.asUuid
import com.tombaxter.taken.core.model.opt
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.time.ZoneId
import java.util.UUID

/**
 * todos.json in the iPhone's shape (Shared/TodoData.swift's Codable, Shared/TodoStore.swift's encoder): keys sorted,
 * dates as seconds since 1970, a timed due as `dueAt`, a day as `dueDay` "YYYY-MM-DD". Decoding is as lenient as the
 * iPhone's: every field but the title has a default; a task with an empty title is dropped; one unreadable task never
 * costs the others; a file that is not a JSON object is unreadable ([com.tombaxter.taken.core.model.JsonShapeException]).
 * The 1.1 internal builds' `area`, `lastArea` and `areaOrder` are read past and not written (SPEC-ANDROID 5.2).
 */
object TodoCodec {
    const val FILE_NAME = "todos.json"

    fun encode(state: TodoState): String = encodeState(state).toString()

    fun decode(text: String, zone: ZoneId = ZoneId.systemDefault()): TodoState = decodeState(TakenJson.parse(text), zone)

    fun encodeState(state: TodoState): JsonObject = TakenJson.obj(
        "schemaVersion" to TakenJson.int(state.schemaVersion),
        "tasks" to JsonArray(state.tasks.map(::encodeTask)),
        "firstNoteAt" to state.firstNoteAt?.let(TakenJson::instant),
    )

    fun encodeTask(task: TodoTask): JsonObject = TakenJson.obj(
        "id" to TakenJson.uuid(task.id),
        "title" to TakenJson.string(task.title),
        "dueAt" to (task.due as? TodoDue.Time)?.let { TakenJson.instant(it.at) },
        "dueDay" to (task.due as? TodoDue.Day)?.let { TakenJson.string(it.day.iso) },
        "createdAt" to TakenJson.instant(task.createdAt),
        "completedAt" to task.completedAt?.let(TakenJson::instant),
        "noteId" to TakenJson.uuid(task.noteId),
        "order" to TakenJson.int(task.order),
    )

    fun decodeState(element: JsonElement, zone: ZoneId = ZoneId.systemDefault()): TodoState {
        val c = element.asObject()
        val tasks = TakenJson.lenient { c.opt("tasks")?.asArray() }
            ?.mapNotNull { TakenJson.lenient { decodeTask(it, zone) } }
            ?.filter { it.title.isNotEmpty() }
            ?: emptyList()
        return TodoState(
            tasks = tasks,
            firstNoteAt = TakenJson.lenient { c.opt("firstNoteAt")?.asInstant() },
            schemaVersion = TakenJson.lenient { c.opt("schemaVersion")?.asInt() } ?: 1,
        )
    }

    /** One task: a wrong id throws (the task is skipped, as Swift's lossy array skips it); anything else defaults. */
    fun decodeTask(element: JsonElement, zone: ZoneId = ZoneId.systemDefault()): TodoTask {
        val c = element.asObject()
        val id = c.opt("id")?.asUuid() ?: UUID.randomUUID()
        val title = c.opt("title")?.asString() ?: ""
        val day = TakenJson.lenient { c.opt("dueDay")?.asString() }?.let { DayKey.fromIso(it) }
        val due: TodoDue? = when {
            day != null -> TodoDue.Day(day)
            else -> TakenJson.lenient { c.opt("dueAt")?.asInstant() }?.let { TodoDue.Time(it) }
                ?: TakenJson.lenient { c.opt("dueDate")?.asInstant() }?.let { legacy ->
                    // Builds before 1.1 shipped stored every due date as a moment, a day alone at noon.
                    val timed = TakenJson.lenient { c.opt("hasTime")?.asBool() } ?: false
                    if (timed) TodoDue.Time(legacy) else TodoDue.Day(DayKey.calendarDateOf(legacy, zone))
                }
        }
        return TodoTask(
            id = id,
            title = title,
            due = due,
            createdAt = TakenJson.lenient { c.opt("createdAt")?.asInstant() } ?: TodoState.DISTANT_PAST,
            completedAt = TakenJson.lenient { c.opt("completedAt")?.asInstant() },
            noteId = TakenJson.lenient { c.opt("noteId")?.asUuid() } ?: id,
            order = TakenJson.lenient { c.opt("order")?.asInt() } ?: 0,
        )
    }
}
