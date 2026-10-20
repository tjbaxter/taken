import SwiftUI

/// What is being heard: "Listening", the time (counting down from 4:00 to the 5-minute stop), a small waveform, the
/// newest words, and a chip naming the list the note goes to, which sends this note to the other list. The dock shows
/// it while a note is heard or sorted; after the stop it reads "Sorting into to-dos", with the part for a long note.
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
    private var area: TodoArea { todo.captureArea }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.signal)
                    .frame(width: 7, height: 7)
                    .opacity(phase == .listening ? 1 : 0.4)
                Text(phase == .sorting ? TodoCopy.sorting : TodoCopy.listening)
                    .font(.sans(13, .sansMedium, relativeTo: .footnote))
                    .foregroundStyle(theme.fgMuted)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if phase == .listening {
                    time
                    TodoWaveform(levels: todo.levels)
                        .frame(width: 104, height: 22)
                } else if let progress = todo.sortingProgress {
                    Text(TodoCopy.part(progress.part, of: progress.of))
                        .font(.mono(13, .monoMedium, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(phase == .sorting ? TodoCopy.sorting : TodoCopy.listening)
            .accessibilityValue(spokenStatus)
            Text(transcript.isEmpty ? TodoCopy.sayIt : Self.tail(transcript))
                .font(.sans(19, .sans, relativeTo: .title3))
                .foregroundStyle(transcript.isEmpty ? theme.fgFaint : theme.fg)
                .lineLimit(4)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: transcript)
                .padding(.top, 12)
                .accessibilityLabel(transcript.isEmpty ? TodoCopy.sayIt : transcript)
            chip
                .padding(.top, 3)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        // The chip's 44 pt target carries its own slack, so the card's bottom reads as 16.
        .padding(.bottom, 7)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    /// "0:12", or from 4:00 "0:40 left" in the signal's ink. A fixed time in the demo, so screenshots are stable.
    @ViewBuilder
    private var time: some View {
        if let fixed = todo.demoElapsed {
            timeLabel(fixed)
        } else if let since = todo.listeningSince {
            TimelineView(.periodic(from: since, by: 1)) { context in
                timeLabel(context.date.timeIntervalSince(since))
            }
        }
    }

    private func timeLabel(_ elapsed: TimeInterval) -> some View {
        let shown = TodoCopy.noteTime(elapsed: elapsed)
        return Text(shown.text)
            .font(.mono(13, .monoMedium, relativeTo: .footnote))
            .foregroundStyle(shown.countdown ? theme.signalInk : theme.fgSubtle)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    /// What VoiceOver reads beside "Listening": "2 minutes 10 seconds", "45 seconds left", or the part being sorted.
    private var spokenStatus: String {
        if phase == .sorting { return todo.sortingProgress.map { TodoCopy.part($0.part, of: $0.of) } ?? "" }
        let elapsed = todo.demoElapsed ?? todo.listeningSince.map { Date().timeIntervalSince($0) } ?? 0
        return TodoCopy.noteTime(elapsed: elapsed).spoken
    }

    /// "Into Personal": where this note goes. A tap sends it to the other list, for this note only; fixed once it is
    /// being sorted. A 44 pt target on a small capsule in the signal's wash.
    private var chip: some View {
        Button {
            todo.setDestination(area.other)
        } label: {
            TodoDestinationChip(area: area)
        }
        .buttonStyle(.plain)
        .disabled(phase == .sorting)
        .opacity(phase == .sorting ? 0.5 : 1)
        .accessibilityLabel(TodoCopy.goesTo(area))
        .accessibilityHint(phase == .sorting ? "" : TodoCopy.sendTo(area.other))
    }

    /// The end of the words: at most `shownCharacters`, from a word start, after an ellipsis when cut.
    nonisolated static func tail(_ text: String, limit: Int = shownCharacters) -> String {
        guard text.count > limit else { return text }
        let end = text.suffix(limit)
        guard let space = end.firstIndex(where: { $0.isWhitespace }) else { return "\u{2026}" + end }
        return "\u{2026} " + end[end.index(after: space)...]
    }
}

/// The destination chip's look, on the Listening card and the type sheet: the list's symbol, "Into Personal", and the
/// up and down chevrons that say it changes.
struct TodoDestinationChip: View {
    @Environment(\.theme) private var theme
    let area: TodoArea

    init(area: TodoArea) {
        self.area = area
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: area.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(TodoCopy.into(area))
                .font(.sans(13, .sansSemibold, relativeTo: .footnote))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(theme.signalInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(theme.signalWash))
        .overlay(Capsule().strokeBorder(theme.signalEdge, lineWidth: 1))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.2), value: area)
    }
}
