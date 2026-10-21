import Foundation

/// To-dos for the `-demo` screenshots (`-screen todo`, `todo-recording`, `todo-cap`), at the demo's moment (21:41), in a
/// temporary file, never the real one: one list, as before 1.1's Personal and Work, with a time tonight, a day this week
/// and tomorrow at 09:00 open, and two done today under "Done today".
enum TodoDemo {
    static let transcript = "Tomorrow by nine I need to call the dentist, pick up the dry cleaning and email Sam the deck. Oh and book flights for March"

    /// The ring around the stop button on the demo's listening screens: a voice mid-sentence.
    static let level = 0.55

    static func state(now: Date, recording: Bool, timeZone: TimeZone = .current) -> TodoState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func at(dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let start = calendar.startOfDay(for: now)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func day(_ dayOffset: Int) -> DayKey {
            DayKey(calendarDateOf: at(dayOffset: dayOffset, 12), in: timeZone)
        }
        let morning = UUID()
        let lunch = UUID()
        let evening = UUID()
        var tasks: [TodoTask] = [
            TodoTask(title: "Take the bins out", due: .time(at(dayOffset: 0, 22, 30)),
                     createdAt: at(dayOffset: 0, 18, 5), noteId: evening, order: 0),
            TodoTask(title: "Renew the car insurance", due: .day(day(3)),
                     createdAt: at(dayOffset: 0, 12, 40), noteId: lunch, order: 0),
            TodoTask(title: "Send Mum the photos", createdAt: at(dayOffset: 0, 12, 40), noteId: lunch, order: 1),
            TodoTask(title: "Buy milk", createdAt: at(dayOffset: 0, 8, 12), completedAt: at(dayOffset: 0, 18, 12),
                     noteId: morning, order: 0),
            TodoTask(title: "Pay the window cleaner", createdAt: at(dayOffset: 0, 8, 12),
                     completedAt: at(dayOffset: 0, 16, 40), noteId: morning, order: 1),
        ]
        if !recording {
            // What the recording screenshot's ramble becomes.
            let note = UUID()
            tasks += [
                TodoTask(title: "Call the dentist", due: .time(at(dayOffset: 1, 9)),
                         createdAt: at(dayOffset: 0, 21, 30), noteId: note, order: 0),
                TodoTask(title: "Pick up the dry cleaning", due: .time(at(dayOffset: 1, 9)),
                         createdAt: at(dayOffset: 0, 21, 30), noteId: note, order: 1),
                TodoTask(title: "Email Sam the deck", due: .time(at(dayOffset: 1, 9)),
                         createdAt: at(dayOffset: 0, 21, 30), noteId: note, order: 2),
                TodoTask(title: "Book flights for March", createdAt: at(dayOffset: 0, 21, 30), noteId: note, order: 3),
            ]
        }
        return TodoState(tasks: tasks, firstNoteAt: at(dayOffset: -6, 9))
    }
}
