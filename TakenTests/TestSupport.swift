import Foundation
@testable import Taken

/// Fixed zone so day math is deterministic on any CI machine.
let london = TimeZone(identifier: "Europe/London")!

func londonClock(_ dayStartHour: Int = 4, _ timeZone: TimeZone = london) -> DayClock {
    DayClock(dayStartHour: dayStartHour, timeZone: timeZone)
}

/// A wall-clock moment in London.
func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ timeZone: TimeZone = london) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func makeItem(_ name: String, _ code: String, _ frequency: Frequency = .daily(times: 1),
              created: Date, sortIndex: Int = 0) -> Item {
    Item(name: name, code: code, frequency: frequency, createdAt: created, sortIndex: sortIndex)
}

func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("taken-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("taken.json")
}
