import SwiftUI

/// Tap a task: change its words or when it is due, or delete it.
struct TodoEditSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let task: TodoTask
    let clock: DayClock
    let onSave: (String, Date?, Bool) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var hasDue: Bool
    @State private var hasTime: Bool
    @State private var due: Date

    init(task: TodoTask, clock: DayClock, onSave: @escaping (String, Date?, Bool) -> Void,
         onDelete: @escaping () -> Void) {
        self.task = task
        self.clock = clock
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: task.title)
        _hasDue = State(initialValue: task.dueDate != nil)
        _hasTime = State(initialValue: task.hasTime)
        _due = State(initialValue: task.dueDate ?? TodoEditSheet.suggestedDue(clock: clock))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("To-do", text: $title, axis: .vertical)
                        .font(.sans(17, .sans, relativeTo: .body))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1...4)
                        .submitLabel(.done)
                }
                .listRowBackground(theme.bgRaised)
                Section {
                    Toggle("Due", isOn: $hasDue.animation(.snappy(duration: 0.22)))
                    if hasDue {
                        Toggle("Time", isOn: $hasTime.animation(.snappy(duration: 0.22)))
                        DatePicker("When", selection: $due,
                                   displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                            .environment(\.locale, Locale(identifier: "en_GB"))
                    }
                }
                .font(.sans(16, .sans, relativeTo: .body))
                .foregroundStyle(theme.fg)
                .tint(theme.signal)
                .listRowBackground(theme.bgRaised)
                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Text("Delete to-do")
                            .font(.sans(16, .sansMedium, relativeTo: .body))
                            .foregroundStyle(theme.danger)
                    }
                }
                .listRowBackground(theme.bgRaised)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Edit to-do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.fgMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, hasDue ? due : nil, hasDue && hasTime)
                        dismiss()
                    }
                    .font(.sans(16, .sansSemibold, relativeTo: .body))
                    .foregroundStyle(theme.signalInk)
                    .disabled(TodoText.clean(title) == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .preferredColorScheme(theme.scheme)
        .tint(theme.signalInk)
    }

    /// A new due date starts tomorrow at 09:00.
    static func suggestedDue(clock: DayClock, now: Date = Date()) -> Date {
        let calendar = clock.calendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

/// Typing instead of talking (no microphone, or no on-device speech): the same sorting into tasks.
struct TodoTypeSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Call the dentist tomorrow at 9, buy milk, email Sam the deck")
                            .font(.sans(17, .sans, relativeTo: .body))
                            .foregroundStyle(theme.fgFaint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.sans(17, .sans, relativeTo: .body))
                        .foregroundStyle(theme.fg)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                }
                .frame(minHeight: 140)
                .padding(10)
                .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.panel))
                .overlay(RoundedRectangle(cornerRadius: theme.radius.panel).strokeBorder(theme.line, lineWidth: 1))
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Type your to-dos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.fgMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSubmit(text)
                        dismiss()
                    }
                    .font(.sans(16, .sansSemibold, relativeTo: .body))
                    .foregroundStyle(theme.signalInk)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .preferredColorScheme(theme.scheme)
        .tint(theme.signalInk)
    }
}
