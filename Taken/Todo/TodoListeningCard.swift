import SwiftUI

/// What is being heard: a live line naming the list it goes to ("Listening · Work"), a small waveform, and the words so
/// far (the newest stay in view). The dock shows it while a note is heard or sorted. It reads the note from the model
/// itself, so what changes where the note goes can sit on the card.
struct TodoListeningCard: View {
    @Environment(\.theme) private var theme
    let todo: TodoModel

    init(todo: TodoModel) {
        self.todo = todo
    }

    private var phase: TodoModel.Phase { todo.phase }
    private var transcript: String { todo.transcript }
    private var levels: [Double] { todo.levels }
    private var area: TodoArea { todo.captureArea }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.signal)
                    .frame(width: 7, height: 7)
                    .opacity(phase == .listening ? 1 : 0.4)
                Text(phase == .sorting ? TodoCopy.sorting : TodoCopy.listeningLine(into: area))
                    .font(.sans(13, .sansMedium, relativeTo: .footnote))
                    .foregroundStyle(theme.fgMuted)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if phase == .listening {
                    TodoWaveform(levels: levels)
                        .frame(width: 104, height: 22)
                }
            }
            Text(transcript.isEmpty ? "Say what you need to do" : transcript)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(phase == .sorting
                            ? TodoCopy.sorting
                            : (transcript.isEmpty ? "\(TodoCopy.listening), \(area.title)" : transcript))
    }
}
