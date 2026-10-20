import SwiftUI
import UIKit

/// The one list (SPEC 3.10): Personal and Work as headed sections of one scrolling list, in the order the person drags
/// them into. Built on the model's own state, writes and announcements; the rows themselves are pure (`TodoSections`).
extension TodoModel {
    /// The rows of the list, without the note still being sorted. Empty when neither list has anything open or done
    /// today.
    var sectionRows: [TodoSectionRow] {
        TodoSections.rows(state: state, day: clock.day(for: now), clock: clock, hiding: hiddenTaskIDs)
    }

    /// "4 open, 2 done today" across both lists, or nil when nothing is open or done today in either. It never drops
    /// out while any task is listed, so nothing under the title jumps when a list is empty.
    var listSummary: String? { TodoSections.summary(sectionRows) }

    /// Something open or done today on either list: the list shows, not the line that teaches it.
    var hasListedTasks: Bool { !sectionRows.isEmpty }

    /// One list's open tasks, without the note still being sorted.
    func openCount(in area: TodoArea) -> Int { openTasks(in: area).count }

    /// The list at the top of the tab.
    func isOnTop(_ area: TodoArea) -> Bool { state.topArea == area }

    /// A heading dropped on the other list: the two swap. Returns whether the order changed, so a drop on its own list
    /// reports failure and the heading goes back where it came from.
    @discardableResult
    func dropSection(_ dragged: TodoArea, on target: TodoArea) -> Bool {
        reorderSections(TodoSections.order(state.areaOrder, dropping: dragged, on: target), moved: dragged)
    }

    /// The heading's menu and VoiceOver action: one list to the top or the bottom.
    @discardableResult
    func moveSection(_ area: TodoArea, toTop: Bool) -> Bool {
        reorderSections(TodoSections.order(state.areaOrder, moving: area, toTop: toTop), moved: area)
    }

    /// Writes a new order to todos.json, so the widget and Shortcuts follow it. The rows slide into place with
    /// `.snappy(0.3)` (none with Reduce Motion), with the soft haptic, and VoiceOver hears where the list went, except
    /// while a note is heard, when the microphone would hear it too. Changing the order changes no task.
    @discardableResult
    func reorderSections(_ order: [TodoArea], moved area: TodoArea) -> Bool {
        let order = TodoState.normalized(order)
        guard order != state.areaOrder else { return false }
        let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : .snappy(duration: 0.3)
        guard withAnimation(animation, { write { $0.setAreaOrder(order) } }) != nil else { return false }
        TodoHaptics.soft(hapticsOn)
        if phase != .starting && phase != .listening {
            announce(order.first == area ? TodoListCopy.movedToTop(area) : TodoListCopy.movedToBottom(area))
        }
        return true
    }
}
