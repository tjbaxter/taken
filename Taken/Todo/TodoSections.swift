import Foundation

// One list (REDESIGN.md, SPEC 3.10; Tom 2026-10-20: "I wanted it all under one tab ... a subheading personal than all
// the things under that, than a subheading work"). The To-do tab is one scrolling list with a heading for each list, in
// the order the person chose, as Apple Reminders, Things and Todoist show groups. The rows and the rules are pure, so
// the tests read them without a view.

/// A row of the To-do tab's list, for `ForEach` identity and `ScrollViewReader`.
enum TodoRowID: Hashable, Sendable {
    case header(TodoArea)
    case task(UUID)
    /// The space under the last list, where a dragged heading can land too.
    case end
}

/// One row: a list's heading, or one of its tasks.
struct TodoSectionRow: Identifiable, Hashable, Sendable {
    let id: TodoRowID
    let area: TodoArea
    /// The task on a task row; nil on a heading.
    let task: TodoTask?
    /// How many of the list's tasks are open (the count beside its heading).
    let openCount: Int
    /// Nothing open and nothing done today: the heading says "Nothing open" under it.
    let isEmpty: Bool

    var isHeader: Bool { task == nil }
}

/// What a dragged heading carries: which list it is. A Codable value, as Apple's DTS sample for moving List sections
/// drags (https://developer.apple.com/forums/thread/780117); a String dragged within the same List is reported not to
/// arrive while a Codable item does (https://developer.apple.com/forums/thread/730367). Transferable in TodoRootView.
struct TodoSectionDrag: Codable, Hashable, Sendable {
    let area: TodoArea
}

enum TodoSections {
    /// The list: for each list in `areaOrder`, its heading, its open tasks in the order of the open list (due first,
    /// `TodoOrdering`), then its tasks done today, newest first. Tasks in `hiding` (a note still being sorted) are left
    /// out. Nothing at all, not even the headings, when neither list has a task open or done today: the tab shows the
    /// one line that teaches it instead.
    static func rows(state: TodoState, day: DayKey, clock: DayClock, hiding: Set<UUID> = []) -> [TodoSectionRow] {
        var rows: [TodoSectionRow] = []
        var listed = false
        for area in state.areaOrder {
            let open = state.openTasks(in: area, clock: clock).filter { !hiding.contains($0.id) }
            let done = state.doneTasks(on: day, in: area, clock: clock).filter { !hiding.contains($0.id) }
            let empty = open.isEmpty && done.isEmpty
            if !empty { listed = true }
            rows.append(TodoSectionRow(id: .header(area), area: area, task: nil, openCount: open.count, isEmpty: empty))
            for task in open + done {
                rows.append(TodoSectionRow(id: .task(task.id), area: area, task: task, openCount: open.count,
                                           isEmpty: false))
            }
        }
        return listed ? rows : []
    }

    /// Open and done today across both lists, for the line under the title.
    static func counts(_ rows: [TodoSectionRow]) -> (open: Int, doneToday: Int) {
        let open = rows.filter(\.isHeader).reduce(0) { $0 + $1.openCount }
        let done = rows.filter { $0.task?.isDone == true }.count
        return (open, done)
    }

    /// "4 open, 2 done today" across both lists, or nil when nothing is open or done today in either.
    static func summary(_ rows: [TodoSectionRow]) -> String? {
        let counts = counts(rows)
        return TodoListCopy.summary(open: counts.open, doneToday: counts.doneToday)
    }

    /// A heading dropped on a list (its heading or any of its rows) takes that list's place, and the lists between move
    /// along one. With two lists a drop is a swap, or nothing when it lands on its own list.
    static func order(_ order: [TodoArea], dropping dragged: TodoArea, on target: TodoArea) -> [TodoArea] {
        let whole = TodoState.normalized(order)
        guard dragged != target, let place = whole.firstIndex(of: target) else { return whole }
        var moved = whole.filter { $0 != dragged }
        moved.insert(dragged, at: min(place, moved.count))
        return moved
    }

    /// The menu and VoiceOver's way to do the same: one list to the top or the bottom.
    static func order(_ order: [TodoArea], moving area: TodoArea, toTop: Bool) -> [TodoArea] {
        let rest = TodoState.normalized(order).filter { $0 != area }
        return toTop ? [area] + rest : rest + [area]
    }
}

/// The copy of the one list, in one place (no dashes, never "free", no exclamation marks).
enum TodoListCopy {
    /// Under a list's heading when it has nothing open and nothing done today.
    static let nothingOpen = "Nothing open"
    static let headerHint = "Touch and hold, then drag to move this list."

    /// "Work, 2 open", "Work, nothing open": what VoiceOver reads for a heading.
    static func headerLabel(_ area: TodoArea, open: Int) -> String {
        open > 0 ? "\(area.title), \(open) open" : "\(area.title), nothing open"
    }

    /// "Move Work to top": the heading's menu item and VoiceOver action.
    static func moveToTop(_ area: TodoArea) -> String { "Move \(area.title) to top" }
    static func moveToBottom(_ area: TodoArea) -> String { "Move \(area.title) to bottom" }

    /// "Work moved to the top.": what VoiceOver says once a list has moved.
    static func movedToTop(_ area: TodoArea) -> String { "\(area.title) moved to the top." }
    static func movedToBottom(_ area: TodoArea) -> String { "\(area.title) moved to the bottom." }

    /// "4 open, 2 done today", "4 open", "Nothing open, 2 done today"; nil with nothing open or done today.
    static func summary(open: Int, doneToday: Int) -> String? {
        switch (open, doneToday) {
        case (0, 0): return nil
        case (0, _): return "Nothing open, \(doneToday) done today"
        case (_, 0): return "\(open) open"
        default: return "\(open) open, \(doneToday) done today"
        }
    }

    static let all: [String] = [nothingOpen, headerHint]
        + TodoArea.allCases.flatMap { area in
            [headerLabel(area, open: 0), headerLabel(area, open: 2), moveToTop(area), moveToBottom(area),
             movedToTop(area), movedToBottom(area)]
        }
        + [summary(open: 4, doneToday: 2), summary(open: 4, doneToday: 0), summary(open: 0, doneToday: 2)].compactMap { $0 }
}
