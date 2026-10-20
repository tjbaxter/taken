import SwiftUI

/// The To-do tab (REDESIGN.md, voice to-dos): a big mic, the words as they are said, and the tasks the on-device model
/// makes of them. Tap a circle to finish a task, swipe left to delete, swipe right to move it to the other list, tap
/// the words to edit. Personal and Work show one at a time, never mixed, and a note lands in the list in view. Every
/// colour comes from the look (`Theme`), so it reads the same in Signal, Blush, Phosphor and Ice.
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
            .onDisappear {
                // Leaving the tab takes Keep as one away: it only makes sense with the note's tasks in view.
                todo.dismissKeepOffer()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: todo.refresh()
                case .background:
                    todo.dismissKeepOffer()
                    todo.stopIfListening()
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
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            // The list in view. Fixed while a note is heard or sorted: it goes where the live card says.
            TodoListSwitch(selected: todo.area, openCounts: openCounts, enabled: todo.phase == .idle) { area in
                todo.select(area)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
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

    /// Each list's open tasks, for the count on the switch.
    private var openCounts: [TodoArea: Int] {
        Dictionary(uniqueKeysWithValues: TodoArea.allCases.map { ($0, todo.openTasks(in: $0).count) })
    }

    /// "3 open, 2 done today", for the list in view.
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
                    // Two lines at most, so the list stays a list and never a page of paragraphs. The whole title is
                    // in the edit sheet and in what VoiceOver reads.
                    Text(task.title)
                        .font(.sans(17, .sans, relativeTo: .body))
                        .foregroundStyle(done ? theme.fgSubtle : theme.fg)
                        .strikethrough(done || filling, color: theme.fgSubtle)
                        .lineLimit(2)
                        .truncationMode(.tail)
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // Named for where it goes. No full swipe, so a long swipe never moves a task by accident.
            Button {
                todo.move(task, to: task.area.other)
            } label: {
                Label(task.area.other.title, systemImage: task.area.other.symbol)
            }
            .tint(theme.fgSubtle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(todo.spoken(task))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(done ? "Double tap to mark not done." : "Double tap to mark done.")
        .accessibilityAction { todo.toggle(task) }
        .accessibilityAction(named: "Edit") { app.sheet = .todoEdit(task.id) }
        .accessibilityAction(named: "Delete") { todo.delete(task) }
        .accessibilityAction(named: TodoCopy.moveAction(to: task.area.other)) { todo.move(task, to: task.area.other) }
        .accessibilityActions {
            // Keep as one is on the line under the list for a few seconds; VoiceOver and Switch Control users get it
            // on each of the note's tasks for as long as it is offered.
            if todo.keepOffer?.ids.contains(task.id) == true {
                Button(TodoCopy.keepAsOne) { todo.keepAsOne() }
            }
        }
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
        Text(TodoCopy.emptyLine(for: todo.area))
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
                TodoListeningCard(todo: todo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let blocker = todo.blocker {
                blockerCard(blocker)
                    .transition(.opacity)
            } else if let offer = todo.keepOffer {
                keepLine(offer)
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
        .animation(.snappy(duration: 0.22), value: todo.keepOffer)
        .animation(.snappy(duration: 0.22), value: todo.deleted?.id)
    }

    /// "3 to-dos from your note   Keep as one": one quiet tap puts a split note back together.
    private func keepLine(_ offer: TodoModel.KeepOffer) -> some View {
        HStack(spacing: 4) {
            Text(TodoCopy.fromYourNote(offer.ids.count))
                .font(.sans(14, .sans, relativeTo: .footnote))
                .foregroundStyle(theme.fgMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Button {
                todo.keepAsOne()
            } label: {
                Text(TodoCopy.keepAsOne)
                    .font(.sans(14, .sansSemibold, relativeTo: .footnote))
                    .foregroundStyle(theme.signalInk)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
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

/// Personal | Work (REDESIGN.md): one list in view at a time, never mixed. A capsule track on the look's raised
/// surface; the selected pill in the signal's wash and edge slides between the two. The list not in view shows how many
/// are open on it, in Geist Mono, so nothing waiting there is forgotten. 44 pt tall, each half a 44 pt target.
struct TodoListSwitch: View {
    @Environment(\.theme) private var theme
    @Namespace private var pill
    let selected: TodoArea
    let openCounts: [TodoArea: Int]
    let enabled: Bool
    let onSelect: (TodoArea) -> Void

    init(selected: TodoArea, openCounts: [TodoArea: Int], enabled: Bool, onSelect: @escaping (TodoArea) -> Void) {
        self.selected = selected
        self.openCounts = openCounts
        self.enabled = enabled
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TodoArea.allCases) { area in
                segment(area)
            }
        }
        .background(theme.bgRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func segment(_ area: TodoArea) -> some View {
        let isSelected = area == selected
        let count = isSelected ? 0 : openCounts[area] ?? 0
        return Button {
            onSelect(area)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(area.title)
                    .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                    .foregroundStyle(isSelected ? theme.fg : theme.fgMuted)
                if count > 0 {
                    Text("\(count)")
                        .font(.mono(13, .monoMedium, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                if isSelected {
                    Capsule()
                        .fill(theme.signalWash)
                        .overlay(Capsule().strokeBorder(theme.signalEdge, lineWidth: 1))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            // The inset is part of the target, so each half takes taps across the whole 44 pt track.
            .padding(3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(count > 0 ? "\(area.title), \(count) open" : area.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
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
