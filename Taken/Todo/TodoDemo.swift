import Foundation

/// To-dos for the `-demo` screenshots, at the demo's moment (21:41), in a temporary file, never the real one:
/// - `todo` and `todo-recording`: Personal on top with its open tasks and two done today, Work under it with three
///   from the morning stand-up, so both headings show.
/// - `todo-work`: the same with Work on top, where notes go.
/// - `todo-work-empty`: the case Tom hit, three open on Personal and nothing on Work, so the Work heading reads
///   "Nothing open" and the line under the title stays "3 open".
enum TodoDemo {
    static let transcript = "Tomorrow by nine I need to call the dentist, pick up the dry cleaning and email Sam the deck. Oh and book flights for March"

    /// The seed for a `-screen` state (`TodoModel.fromLaunchArguments` passes its own).
    static func state(now: Date, recording: Bool, timeZone: TimeZone = .current, screen: String?) -> TodoState {
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
        let standup = UUID()
        let personal: [TodoTask] = [
            TodoTask(title: "Take the bins out", due: .time(at(dayOffset: 0, 22, 30)),
                     createdAt: at(dayOffset: 0, 18, 5), noteId: evening, order: 0),
            TodoTask(title: "Renew the car insurance", due: .day(day(3)),
                     createdAt: at(dayOffset: 0, 12, 40), noteId: lunch, order: 0),
            TodoTask(title: "Send Mum the photos", createdAt: at(dayOffset: 0, 12, 40), noteId: lunch, order: 1),
        ]
        if screen == "todo-work-empty" {
            // Three open on Personal, nothing on Work, nothing done: exactly what Tom had when the "3 open" bounced.
            return TodoState(tasks: personal, firstNoteAt: at(dayOffset: -6, 9), lastArea: .personal)
        }
        var tasks: [TodoTask] = personal + [
            TodoTask(title: "Buy milk", createdAt: at(dayOffset: 0, 8, 12), completedAt: at(dayOffset: 0, 18, 12),
                     noteId: morning, order: 0),
            TodoTask(title: "Pay the window cleaner", createdAt: at(dayOffset: 0, 8, 12),
                     completedAt: at(dayOffset: 0, 16, 40), noteId: morning, order: 1),
            // Work: one note from the morning stand-up.
            TodoTask(title: "Send Priya the Q3 numbers", due: .time(at(dayOffset: 1, 10)),
                     createdAt: at(dayOffset: 0, 9, 20), noteId: standup, order: 0, area: .work),
            TodoTask(title: "Book a room for the review", due: .day(day(2)),
                     createdAt: at(dayOffset: 0, 9, 20), noteId: standup, order: 1, area: .work),
            TodoTask(title: "Reply to Dan about the contract", createdAt: at(dayOffset: 0, 9, 20),
                     noteId: standup, order: 2, area: .work),
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
        // `todo-work` puts Work on top, so its notes go there; `lastArea` follows for builds that still read it.
        let workOnTop = screen == "todo-work"
        return TodoState(tasks: tasks, firstNoteAt: at(dayOffset: -6, 9), lastArea: workOnTop ? .work : .personal,
                         areaOrder: workOnTop ? [.work, .personal] : TodoState.defaultAreaOrder)
    }

    /// A waveform mid-sentence.
    static func levels(count: Int) -> [Double] {
        (0..<count).map { index in
            let x = Double(index)
            let wave = 0.5 + 0.32 * sin(x * 0.55) + 0.18 * sin(x * 1.7 + 0.8)
            return max(0.08, min(1, wave * (index < 4 ? Double(index + 1) / 5 : 1)))
        }
    }
}
