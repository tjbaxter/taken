import SwiftUI

/// The To-do tab (REDESIGN.md, voice to-dos): a big mic, the words as they are said, and the tasks the on-device model
/// makes of them. Tap a circle to finish a task, swipe to delete, tap the words to edit. Every colour comes from the
/// look (`Theme`), so it reads the same in Signal, Blush, Phosphor and Ice.
///
/// It is the To-do tab of RootView's tab bar, which follows every voice to-do request (`.opensTodoTab`): Siri, the
/// control, the Lock Screen, links, notifications and the quick action land here. Its sheets (edit, type) are the
/// root's, so a capture closes whatever is open before the mic starts.
struct TodoRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var todo = TodoModel.shared
    @State private var route = TodoCaptureRoute.shared

    init() {}

    var body: some View {
        list
            .safeAreaInset(edge: .bottom, spacing: 0) { dock }
            .background(theme.bg.ignoresSafeArea())
            .overlay {
                if todo.isEmpty && todo.phase == .idle && todo.blocker == nil {
                    emptyState
                }
            }
            .onAppear {
                todo.attach(app)
                consumeRequest()
            }
            .onChange(of: route.pendingRecording) { _, pending in
                if pending != nil { consumeRequest() }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: todo.refresh()
                case .background: todo.stopIfListening()
                default: break
                }
            }
            .task {
                // Due labels and Done today follow the clock while the tab is open.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    todo.refresh()
                }
            }
    }

    /// A recording asked for by Siri, the control, the Lock Screen or the quick action starts once the To-do tab is in
    /// front with nothing over it, so Listening and the stop button are on screen when the mic opens.
    private func consumeRequest() {
        guard route.takePendingRecording() else { return }
        app.openTodoTab()
        Task {
            // Let a closing sheet finish, the tab settle and Siri hand back the microphone first.
            try? await Task.sleep(for: .milliseconds(450))
            var waited = 0
            while !app.showsTodoTabUncovered && waited < 12 {
                try? await Task.sleep(for: .milliseconds(150))
                waited += 1
            }
            guard app.showsTodoTabUncovered else { return }
            todo.startFromRequest(app)
        }
    }

    // MARK: List

    private var list: some View {
        List {
            header
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 14, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(todo.openTasks) { task in
                row(task)
            }
            if !todo.doneToday.isEmpty {
                Text(TodoCopy.doneToday)
                    .font(.sans(13, .sansMedium, relativeTo: .footnote))
                    .foregroundStyle(theme.fgSubtle)
                    .accessibilityAddTraits(.isHeader)
                    .listRowInsets(EdgeInsets(top: 26, leading: 20, bottom: 6, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                ForEach(todo.doneToday) { task in
                    row(task)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 44)
    }

    private var header: some View {
        TabHeader(title: "To-do", subtitle: todo.isEmpty ? nil : summary)
    }

    /// "3 open, 2 done today"
    private var summary: String {
        let open = todo.openTasks.count
        let done = todo.doneToday.count
        var parts = ["\(open) open"]
        if done > 0 { parts.append("\(done) done today") }
        return parts.joined(separator: ", ")
    }

    private func row(_ task: TodoTask) -> some View {
        let done = task.isDone
        let filling = todo.completing.contains(task.id)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                todo.toggle(task)
            } label: {
                TodoCheck(done: done || filling)
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[VerticalAlignment.center] + 6 }
            Button {
                app.sheet = .todoEdit(task.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(task.title)
                        .font(.sans(17, .sans, relativeTo: .body))
                        .foregroundStyle(done ? theme.fgSubtle : theme.fg)
                        .strikethrough(done || filling, color: theme.fgSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    if let parts = trailingParts(task) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if let day = parts.day {
                                Text(day).font(.sans(14, .sans, relativeTo: .footnote))
                            }
                            if let time = parts.time {
                                Text(time).font(.mono(13, .monoMedium, relativeTo: .footnote))
                            }
                        }
                        .foregroundStyle(todo.isOverdue(task) ? theme.signalInk : theme.fgSubtle)
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 20))
        .listRowSeparatorTint(theme.line)
        .listRowBackground(todo.arrived.contains(task.id) ? theme.signalWash : Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                todo.delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(todo.spoken(task))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(done ? "Double tap to mark not done." : "Double tap to mark done.")
        .accessibilityAction { todo.toggle(task) }
        .accessibilityAction(named: "Edit") { app.sheet = .todoEdit(task.id) }
        .accessibilityAction(named: "Delete") { todo.delete(task) }
    }

    /// "Tomorrow 09:00": the day in Geist, the time in Geist Mono. A done task shows when it was done.
    private func trailingParts(_ task: TodoTask) -> (day: String?, time: String?)? {
        if task.isDone {
            guard let time = todo.doneLabel(task) else { return nil }
            return (day: nil, time: time)
        }
        return todo.dueParts(task)
    }

    private var emptyState: some View {
        Text(TodoCopy.empty)
            .font(.sans(17, .sans, relativeTo: .body))
            .foregroundStyle(theme.fgMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .allowsHitTesting(false)
    }

    // MARK: Dock

    private var dock: some View {
        VStack(spacing: 14) {
            if let deleted = todo.deleted {
                undoBar(deleted)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if todo.phase == .listening || todo.phase == .sorting {
                TodoLiveCard(phase: todo.phase, transcript: todo.transcript, levels: todo.levels)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let blocker = todo.blocker {
                blockerCard(blocker)
                    .transition(.opacity)
            } else if let notice = todo.notice {
                Text(notice)
                    .font(.sans(14, .sans, relativeTo: .footnote))
                    .foregroundStyle(theme.fgMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            TodoMicButton(phase: todo.phase, level: todo.levels.last ?? 0) {
                todo.micTapped(app)
            }
            if todo.phase == .listening {
                Text(TodoCopy.tapToFinish)
                    .font(.sans(13, .sans, relativeTo: .footnote))
                    .foregroundStyle(theme.fgSubtle)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(theme.bg)
        .animation(.snappy(duration: 0.28), value: todo.phase)
        .animation(.snappy(duration: 0.22), value: todo.notice)
        .animation(.snappy(duration: 0.22), value: todo.deleted?.id)
    }

    private func undoBar(_ task: TodoTask) -> some View {
        HStack(spacing: 12) {
            Text("Deleted: \(task.title)")
                .font(.sans(14, .sans, relativeTo: .footnote))
                .foregroundStyle(theme.fgMuted)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo") { todo.undoDelete() }
                .font(.sans(14, .sansSemibold, relativeTo: .footnote))
                .foregroundStyle(theme.signalInk)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }

    private func blockerCard(_ blocker: TodoModel.Blocker) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message(for: blocker))
                .font(.sans(15, .sans, relativeTo: .subheadline))
                .foregroundStyle(theme.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                if blocker != .unavailable {
                    TodoPillButton(title: TodoCopy.openSettings, filled: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                TodoPillButton(title: TodoCopy.typeInstead, filled: blocker == .unavailable) {
                    app.sheet = .todoType
                }
            }
        }
        .padding(16)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }

    private func message(for blocker: TodoModel.Blocker) -> String {
        switch blocker {
        case .microphone: return TodoCopy.microphoneOff
        case .speech: return TodoCopy.speechOff
        case .unavailable: return TodoCopy.unavailable
        }
    }
}

// MARK: - Pieces

/// The circle: an empty ring, or the look's signal with a check.
struct TodoCheck: View {
    @Environment(\.theme) private var theme
    let done: Bool

    init(done: Bool) {
        self.done = done
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? theme.signal : theme.lineStrong, lineWidth: 1.5)
            if done {
                Circle().fill(theme.signal)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.onSignal)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.62), value: done)
    }
}

/// The big round mic. Listening, it becomes a stop square with a ring that breathes with the voice.
struct TodoMicButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let phase: TodoModel.Phase
    let level: Double
    let action: () -> Void

    init(phase: TodoModel.Phase, level: Double, action: @escaping () -> Void) {
        self.phase = phase
        self.level = level
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if phase == .listening {
                    // The ring breathes with the voice; with Reduce Motion it stays still.
                    Circle()
                        .stroke(theme.signalEdge, lineWidth: 2)
                        .scaleEffect(reduceMotion ? 1.12 : 1.08 + 0.3 * level)
                        .opacity(reduceMotion ? 0.8 : 0.4 + 0.6 * level)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
                }
                Circle()
                    .fill(theme.signal)
                    .shadow(color: theme.signal.opacity(0.28), radius: phase == .listening ? 18 : 10)
                switch phase {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(theme.onSignal)
                case .listening:
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme.onSignal)
                        .frame(width: 24, height: 24)
                case .starting, .sorting:
                    ProgressView()
                        .tint(theme.onSignal)
                        .controlSize(.regular)
                }
            }
            .frame(width: 76, height: 76)
            .contentShape(Circle())
        }
        .buttonStyle(TodoMicPressStyle())
        .disabled(phase == .starting || phase == .sorting)
        .accessibilityLabel(phase == .listening ? "Stop and sort" : "New voice to-do")
        .accessibilityHint(phase == .listening ? "Turns what you said into to-dos." : "Starts listening.")
    }
}

private struct TodoMicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// What is being heard: a live line, a small waveform, and the words so far (the newest stay in view).
struct TodoLiveCard: View {
    @Environment(\.theme) private var theme
    let phase: TodoModel.Phase
    let transcript: String
    let levels: [Double]

    init(phase: TodoModel.Phase, transcript: String, levels: [Double]) {
        self.phase = phase
        self.transcript = transcript
        self.levels = levels
    }

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
        .accessibilityLabel(phase == .sorting ? TodoCopy.sorting : (transcript.isEmpty ? TodoCopy.listening : transcript))
    }
}

/// Bars from the recent input levels.
struct TodoWaveform: View {
    @Environment(\.theme) private var theme
    let levels: [Double]

    init(levels: [Double]) {
        self.levels = levels
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 2
            let width = max(1.5, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(theme.signal.opacity(0.35 + 0.65 * level))
                        .frame(width: width, height: max(3, geo.size.height * level))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

/// A small rounded button in the dock's cards.
struct TodoPillButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let filled: Bool
    let action: () -> Void

    init(title: String, filled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sans(14, .sansSemibold, relativeTo: .footnote))
                .foregroundStyle(filled ? theme.buttonText : theme.fg)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(filled ? theme.button : Color.clear, in: RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous)
                    .strokeBorder(filled ? Color.clear : theme.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
