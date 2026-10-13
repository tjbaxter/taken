import AppIntents
import SwiftUI
import WidgetKit

// Quick capture from the Lock Screen and Control Center (REDESIGN.md, voice to-dos): the mic opens Taken already
// listening; the list shows what is still open. Both read todos.json in the App Group.

struct TodoEntry: TimelineEntry {
    let date: Date
    /// Open tasks, due first (the To-do tab's order), at most three.
    let open: [String]
    let openCount: Int
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: Date(), open: ["Call the dentist", "Email Sam the deck"], openCount: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodoEntry) -> Void) {
        let entry = Self.entry(at: Date())
        if context.isPreview && entry.openCount == 0 {
            completion(placeholder(in: context))
        } else {
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodoEntry>) -> Void) {
        let now = Date()
        // The app reloads this whenever the tasks change; the hourly refresh keeps the order honest as times pass.
        completion(Timeline(entries: [Self.entry(at: now)], policy: .after(now.addingTimeInterval(3600))))
    }

    static func entry(at date: Date) -> TodoEntry {
        let dayStartHour = TakenStore.shared.load().settings.dayStartHour
        let open = TodoStore.shared.load().openTasks(clock: DayClock(dayStartHour: dayStartHour))
        return TodoEntry(date: date, open: open.prefix(3).map(\.title), openCount: open.count)
    }
}

/// The Lock Screen: a round mic that opens Taken listening, a list of what is open, and an inline count.
struct TodoCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoCaptureRoute.widgetKind, provider: TodoProvider()) { entry in
            TodoCaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Voice to-do")
        .description("Tap the mic and say what you need to do.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodoCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoEntry

    init(entry: TodoEntry) {
        self.entry = entry
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(TodoCaptureRoute.listURL)
        case .accessoryInline:
            Label(entry.openCount == 1 ? "1 to-do" : "\(entry.openCount) to-dos", systemImage: "mic.fill")
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(TodoCaptureRoute.recordURL)
        default:
            circular
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(TodoCaptureRoute.recordURL)
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityLabel("New voice to-do")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .bold))
                    .widgetAccentable()
                Text(entry.openCount == 0 ? "To-do" : "To-do \u{00B7} \(entry.openCount)")
                    .font(.sans(13, .sansSemibold))
                    .widgetAccentable()
            }
            if entry.open.isEmpty {
                Text("Tap to see your list")
                    .font(.sans(13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.open.prefix(2).enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(.sans(13))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Control Center and the Action button: opens Taken listening. An `OpenIntent` in both targets, as a control that
/// opens its app must be.
@available(iOS 18.0, *)
struct VoiceTodoControl: ControlWidget {
    static let kind = "com.tombaxter.taken.control.voice-todo"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: VoiceTodoControlLook()) { look in
            ControlWidgetButton(action: NewVoiceTodoIntent(target: .recording)) {
                Label("New voice to-do", systemImage: "mic.fill")
            }
            .tint(look.theme.signal)
        }
        .displayName("New voice to-do")
        .description("Opens Taken listening.")
    }
}

/// The control's tint: the signal colour of the look chosen in the app.
@available(iOS 18.0, *)
struct VoiceTodoControlLook: ControlValueProvider {
    var previewValue: ThemeID { TakenStore.shared.load().settings.theme }

    func currentValue() async throws -> ThemeID {
        TakenStore.shared.load().settings.theme
    }
}
