import Foundation

/// To-dos for the `-demo` screenshots (`-screen todo`, `-screen todo-recording`), at the demo's moment (21:41). Kept in
/// a temporary file, never the real one.
enum TodoDemo {
    static let transcript = "Tomorrow by nine I need to call the dentist, pick up the dry cleaning and email Sam the deck. Oh and book flights for March"

    static func state(now: Date, recording: Bool, timeZone: TimeZone = .current) -> TodoState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func at(dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let start = calendar.startOfDay(for: now)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let morning = UUID()
        let lunch = UUID()
        let evening = UUID()
        var tasks: [TodoTask] = [
            TodoTask(title: "Take the bins out", dueDate: at(dayOffset: 0, 22, 30), hasTime: true,
                     createdAt: at(dayOffset: 0, 18, 5), noteId: evening, order: 0),
            TodoTask(title: "Renew the car insurance", dueDate: at(dayOffset: 3, 12), hasTime: false,
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
                TodoTask(title: "Call the dentist", dueDate: at(dayOffset: 1, 9), hasTime: true,
                         createdAt: at(dayOffset: 0, 21, 30), noteId: note, order: 0),
                TodoTask(title: "Pick up the dry cleaning", dueDate: at(dayOffset: 1, 9), hasTime: true,
                         createdAt: at(dayOffset: 0, 21, 30), noteId: note, order: 1),
                TodoTask(title: "Email Sam the deck", dueDate: at(dayOffset: 1, 9), hasTime: true,
                         createdAt: at(dayOffset: 0, 21, 30), noteId: note, order: 2),
                TodoTask(title: "Book flights for March", createdAt: at(dayOffset: 0, 21, 30), noteId: note, order: 3),
            ]
        }
        return TodoState(tasks: tasks, firstNoteAt: at(dayOffset: -6, 9))
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
