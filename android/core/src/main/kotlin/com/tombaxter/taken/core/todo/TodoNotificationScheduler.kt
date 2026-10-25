package com.tombaxter.taken.core.todo

/**
 * Rebuilds the due-time notifications one run at a time, the newest tasks winning: two changes a moment apart never
 * interleave, so a finished to-do's notification is never left scheduled (Taken/Todo/TodoModel.swift
 * `TodoNotificationScheduler`, an actor there). Every rebuild comes through here: a change to the list, Taken coming to
 * the front, and notifications being allowed.
 *
 * The seam for SPEC-ANDROID 10.4's to-do due times: the To-do tab calls [reschedule] after every write that changed a task
 * and on every return to the front. `apply` is where Android's delivery plugs in (the "To-do due times" channel and one
 * inexact alarm for the soonest of [TodoNotifications.plan]); until that step it does nothing.
 */
class TodoNotificationScheduler(private val apply: suspend (List<TodoTask>) -> Unit) {
    private val lock = Any()
    private var latest: List<TodoTask>? = null
    private var running = false

    /** Asks for a rebuild with these tasks. While one runs, a newer request replaces any waiting one and runs next. */
    suspend fun reschedule(tasks: List<TodoTask>) {
        val starts = synchronized(lock) {
            latest = tasks
            if (running) false else true.also { running = true }
        }
        if (!starts) return
        while (true) {
            val next = synchronized(lock) {
                val waiting = latest
                latest = null
                if (waiting == null) running = false
                waiting
            } ?: return
            apply(next)
        }
    }

    companion object {
        /** No delivery yet: the rebuilds run and post nothing. */
        val none: TodoNotificationScheduler = TodoNotificationScheduler { }
    }
}
