import SwiftUI

/// What is being heard: the original card (Tom 2026-10-21: "I prefer the original UI design where it was just like the
/// text box and I could speak"). The signal dot, "Listening" or "Sorting into to-dos", and the newest words. No
/// waveform, no time and no list: from 4:00 of a 5-minute note only, a quiet "1 minute left" fades in where the
/// waveform was, once, and never counts down (Tom: "don't count them down"). After the stop it reads "Sorting into
/// to-dos", with the part for a long note.
struct TodoListeningCard: View {
    @Environment(\.theme) private var theme
    let todo: TodoModel

    init(todo: TodoModel) {
        self.todo = todo
    }

    /// The card shows only the end of a long note, so a 5-minute monologue never lays out a page of text on every
    /// word.
    nonisolated static let shownCharacters = 240

    private var phase: TodoModel.Phase { todo.phase }
    private var transcript: String { todo.transcript }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.signal)
                    .frame(width: 7, height: 7)
                    .opacity(phase == .listening ? 1 : 0.4)
                Text(phase == .sorting ? TodoCopy.sorting : TodoCopy.listening)
                    .font(.sans(13, .sansMedium, relativeTo: .footnote))
                    .foregroundStyle(theme.fgMuted)
                    .lineLimit(1)
                if phase == .sorting, let progress = todo.sortingProgress {
                    Text(TodoCopy.part(progress.part, of: progress.of))
                        .font(.sans(13, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if phase == .listening && todo.inLastMinute {
                    Text(TodoCopy.oneMinuteLeft)
                        .font(.sans(13, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            Text(transcript.isEmpty ? TodoCopy.sayIt : Self.tail(transcript))
                .font(.sans(19, .sans, relativeTo: .title3))
                .foregroundStyle(transcript.isEmpty ? theme.fgFaint : theme.fg)
                .lineLimit(4)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: transcript)
        }
        .padding(16)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(spokenValue)
    }

    /// "Listening" before a word, then the words; "Sorting into to-dos" after the stop.
    private var spokenLabel: String {
        if phase == .sorting { return TodoCopy.sorting }
        return transcript.isEmpty ? TodoCopy.listening : transcript
    }

    /// The part being sorted, or from 4:00 "1 minute left".
    private var spokenValue: String {
        if phase == .sorting { return todo.sortingProgress.map { TodoCopy.part($0.part, of: $0.of) } ?? "" }
        return todo.inLastMinute ? TodoCopy.oneMinuteLeft : ""
    }

    /// The end of the words: at most `shownCharacters`, from a word start, after an ellipsis when cut.
    nonisolated static func tail(_ text: String, limit: Int = shownCharacters) -> String {
        guard text.count > limit else { return text }
        let end = text.suffix(limit)
        guard let space = end.firstIndex(where: { $0.isWhitespace }) else { return "\u{2026}" + end }
        return "\u{2026} " + end[end.index(after: space)...]
    }
}
