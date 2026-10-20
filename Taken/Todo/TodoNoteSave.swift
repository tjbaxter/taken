import Foundation

// Saving a voice note (SPEC 3.10): the words are saved the moment they are known, as said (one line per sentence,
// TodoValidation.lines), under one new note, out of sight while the model sorts them; the sorted tasks then replace
// those lines. If iOS ends Taken while the model is still sorting, every word is already on the list.

extension TodoState {
    /// Replaces a note saved as said (`saved`, its lines as they were written) with the tasks sorted from it, on the
    /// note's list, said when the note was said. Only while every line is still there, open, with no due and its saved
    /// title: a line someone edited, finished or moved meanwhile (a Shortcut, another build) leaves the note as it is.
    /// Returns the note's tasks as they now stand: the sorted ones; the lines when the drafts are just those lines;
    /// what is there when it was changed; nothing when the note was deleted or erased.
    @discardableResult
    mutating func replaceNote(noteId: UUID, saved: [TodoTask], with drafts: [TodoDraft], at now: Date) -> [TodoTask] {
        let current = tasks.filter { $0.noteId == noteId }.sorted { $0.order < $1.order }
        guard !current.isEmpty else { return [] }
        let untouched = current.count == saved.count && saved.allSatisfy { line in
            guard let task = task(line.id) else { return false }
            return !task.isDone && task.due == nil && task.title == line.title && task.area == line.area
        }
        guard untouched, !drafts.isEmpty else { return current }
        if drafts == saved.map({ TodoDraft(title: $0.title, due: $0.due) }) { return current }
        let first = current[0]
        let ids = Set(current.map(\.id))
        tasks.removeAll { ids.contains($0.id) }
        let added = drafts.enumerated().map { offset, draft in
            TodoTask(title: draft.title, due: draft.due, createdAt: first.createdAt, noteId: noteId, order: offset,
                     area: first.area)
        }
        tasks.append(contentsOf: added)
        prune(now: now)
        return added
    }
}
