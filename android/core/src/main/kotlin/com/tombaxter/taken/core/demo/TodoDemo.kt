package com.tombaxter.taken.core.demo

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoTask
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * To-dos for the demo screenshots (`todo`, `todo-recording`, `todo-cap`), ported from Taken/Todo/TodoDemo.swift: at the
 * demo's moment (21:41), one list with a time tonight, a day this week and tomorrow at 09:00 open, and two done today
 * under "Done today". Ids come from a seeded generator so every capture is the same.
 */
object TodoDemo {
    const val TRANSCRIPT =
        "Tomorrow by nine I need to call the dentist, pick up the dry cleaning and email Sam the deck. Oh and book flights for March"

    /** The ring around the stop button on the demo's listening screens: a voice mid-sentence. */
    const val LEVEL = 0.55

    fun state(now: Instant, recording: Boolean, zone: ZoneId = ZoneId.systemDefault()): TodoState {
        var counter = 0L
        fun id(): UUID {
            counter += 1
            return UUID(0x7A4E_0000_0000_4000L, -0x6000_0000_0000_0000L + counter)
        }
        val start = now.atZone(zone).toLocalDate()
        fun at(dayOffset: Int, hour: Int, minute: Int = 0): Instant =
            start.plusDays(dayOffset.toLong()).atTime(hour, minute).atZone(zone).toInstant()
        fun day(dayOffset: Int): DayKey = DayKey.calendarDateOf(at(dayOffset, 12), zone)
        val morning = id()
        val lunch = id()
        val evening = id()
        val tasks = mutableListOf(
            TodoTask(id(), "Take the bins out", TodoDue.Time(at(0, 22, 30)), at(0, 18, 5), null, evening, 0),
            TodoTask(id(), "Renew the car insurance", TodoDue.Day(day(3)), at(0, 12, 40), null, lunch, 0),
            TodoTask(id(), "Send Mum the photos", null, at(0, 12, 40), null, lunch, 1),
            TodoTask(id(), "Buy milk", null, at(0, 8, 12), at(0, 18, 12), morning, 0),
            TodoTask(id(), "Pay the window cleaner", null, at(0, 8, 12), at(0, 16, 40), morning, 1),
        )
        if (!recording) {
            // What the recording screenshot's ramble becomes.
            val note = id()
            tasks += listOf(
                TodoTask(id(), "Call the dentist", TodoDue.Time(at(1, 9)), at(0, 21, 30), null, note, 0),
                TodoTask(id(), "Pick up the dry cleaning", TodoDue.Time(at(1, 9)), at(0, 21, 30), null, note, 1),
                TodoTask(id(), "Email Sam the deck", TodoDue.Time(at(1, 9)), at(0, 21, 30), null, note, 2),
                TodoTask(id(), "Book flights for March", null, at(0, 21, 30), null, note, 3),
            )
        }
        return TodoState(tasks = tasks, firstNoteAt = at(-6, 9))
    }
}
