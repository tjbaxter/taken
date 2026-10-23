import SwiftUI
import Observation
import AppIntents
import WidgetKit

/// The tab bar's three tabs (REDESIGN.md), and the optional fourth, Weight, last (SPEC 3.12; off until the person turns
/// it on).
enum AppTab: String, Hashable, Sendable {
    case today
    case todo
    case history
    case weight
}

/// Every sheet, presented above the tab bar, so one place can close it (a voice to-do request, the paywall).
enum SheetRoute: Identifiable, Hashable {
    case add
    /// Profile, with every setting (the avatar on each tab).
    case settings
    case day(DayKey)
    case setTime(UUID)
    /// The item sheet: tap an item's name on Today.
    case editItem(UUID)
    /// A to-do's words and due time.
    case todoEdit(UUID)
    /// Typing to-dos instead of saying them.
    case todoType
    /// How to add the Lock Screen widget, from Today's one-time invite.
    case widgetHelp
    /// All weigh-ins: edit one, or swipe it away.
    case weighIns
    /// Set Goal or Change Goal, from the Weight tab's More menu.
    case weightGoal

    var id: String {
        switch self {
        case .add: return "add"
        case .settings: return "settings"
        case .day(let day): return "day-\(day.ordinal)"
        case .setTime(let id): return "time-\(id.uuidString)"
        case .editItem(let id): return "edit-\(id.uuidString)"
        case .todoEdit(let id): return "todo-\(id.uuidString)"
        case .todoType: return "todo-type"
        case .widgetHelp: return "widget-help"
        case .weighIns: return "weigh-ins"
        case .weightGoal: return "weight-goal"
        }
    }
}

/// What UNDO on a toast puts back.
enum UndoStep: Equatable, Sendable {
    /// Remove doses that were just logged.
    case remove(Set<UUID>)
    /// Put doses back exactly as they were: a removed dose, or a dose before its time was changed.
    case restore([Dose])
    /// Remove a weigh-in that was just saved.
    case removeWeighIn(UUID)
    /// Put a weigh-in back as it was: deleted, or before an edit.
    case restoreWeighIn(WeighIn)
    /// Bring the Weight tab back after Hide Weight Tab.
    case showWeightTab
    /// Put the goal back after Clear Goal, start included.
    case restoreWeightGoal(WeightGoal)
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    /// A time after the message, set in Geist Mono: "Vitamin D3 taken at" "07:42".
    var time: String? = nil
    var undo: UndoStep? = nil
}

/// The app's single source of UI state. Reads and writes go through TakenStore.
@MainActor
@Observable
final class AppModel {
    let store: TakenStore
    let pro: ProStore
    let isDemo: Bool
    let launchScreen: String?
    private let clockNow: @Sendable () -> Date

    private(set) var state: StackState
    /// The look (Settings > LOOK): set at launch and whenever the stored one changes, so views that only need the
    /// look redraw only when it does.
    private(set) var theme: Theme
    private(set) var now: Date
    private(set) var engine: StackEngine
    private(set) var today: DaySummary
    private(set) var history: [[HistoryCell]] = []
    private(set) var streak: Int = 0
    private(set) var adherence = Adherence(taken: 0, due: 0)

    /// The tab in front.
    var tab: AppTab
    var sheet: SheetRoute?
    var toast: Toast?
    var expandedItemID: UUID?
    /// The Taken Pro sheet, and which presentation level shows it.
    var paywall: PaywallRequest?
    /// The one notification ask after a trial starts (`TrialAsk`): the presentation level it is on, once nothing else
    /// holds the screen (`presentTrialAskIfClear`).
    var trialAsk: PaywallAnchor?
    /// How iOS's notification permission is read (`Reminders.permission`); tests and `-demo` give their own answer.
    @ObservationIgnored var notificationPermission: @MainActor () async -> NotificationPermission = {
        await Reminders.permission()
    }
    /// A voice note is starting, being heard or being sorted: the trial ask waits for it (`TodoModel.phase`). Tests
    /// give their own answer.
    @ObservationIgnored var captureBusy: @MainActor () -> Bool = { TodoModel.shared.phase != .idle }
    /// Chips pre-selected in the Add sheet for the `-demo -screen add` screenshot, and how often each is taken.
    let demoPreselect: [String]
    let demoChoices: [String: FrequencyChoice]
    /// `-demo -screen add-search`: the Add sheet in type mode with "tum" typed, Turmeric suggested ("mag" for the
    /// neutral store set, `DemoStack.typedQuery`).
    let demoQuery: String
    /// `-demo-stack us|neutral`: which App Store set a `-demo` launch shows (`DemoStack`); `standard` otherwise.
    let demoStack: DemoStack
    /// Profile: a name and a photo, both optional, on this iPhone.
    let profileStore: ProfileStore
    private(set) var profile: Profile
    private(set) var profilePhoto: UIImage?
    /// Increments each time a tap finishes the day (All taken), to run its check animation once.
    private(set) var lockInCount = 0
    private(set) var notificationsDenied = false
    /// iOS allows Taken's notifications, as last read (on every return to the foreground). Nil until read. While it is
    /// false, Today carries the trial reminder's words itself (`TrialReminder.notice`).
    private(set) var notificationsAllowed: Bool?
    /// Yesterday, while Today offers to fill it in (`TodayPrompts.repairDay`); worked out with the stats.
    private(set) var repairDay: DayKey?
    /// `-demo` shows a one-time row only when its `-screen` asks: today-nudge-offer, today-repair, today-widget-invite.
    private(set) var demoPrompt: TodayPrompt?
    /// Whether the Taken widget is on the Lock Screen already, as WidgetKit last said; nil until it has answered, and the
    /// widget invite waits for that answer.
    private(set) var lockScreenWidget: Bool?
    /// The Weight tab (SPEC 3.12): weights.json, or a temporary file under `-demo` (Debug only).
    @ObservationIgnored var weight: WeightModel

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var darwinObserver: DarwinObserver?
    @ObservationIgnored private var introTask: Task<Void, Never>?
    @ObservationIgnored private var introWaitsForSheet = false
    @ObservationIgnored private var iconTask: Task<Void, Never>?
    /// A new look's icon waits for Settings to close, so trying the looks brings up iOS's icon alert once.
    @ObservationIgnored private var iconWaitsForSettings = false
    /// What the paywall was opened for, run once Pro is on and the sheet has closed.
    @ObservationIgnored private var afterPaywall: (@MainActor () -> Void)?
    /// A trial started in the paywall: the notification ask follows once the sheet has gone.
    @ObservationIgnored private var trialAskAfterPaywall = false
    /// The ask is due and waits until nothing else holds the screen: no paywall, no iOS prompt, no voice note, no
    /// sheet opened since the paywall (`trialAskLevel`). Nothing is used up until it is on screen (`trialAskDidAppear`).
    @ObservationIgnored private var trialAskDue = false
    /// The sheet the paywall was over when the trial started: the ask may show over it while it is still up.
    @ObservationIgnored private var trialAskSheet: SheetRoute?
    /// Continue was tapped. The ask has no other way out (Apple's HIG), so closing without it means something else
    /// closed it (a voice to-do request), and it comes back once nothing else holds the screen.
    @ObservationIgnored private var trialAskAnswered = false
    /// How many sheets are on screen at each level above TODAY (`PaywallHost`): a sheet still closing counts until
    /// it has gone.
    @ObservationIgnored private var levelsOnScreen: [PaywallAnchor: Int] = [:]
    @ObservationIgnored private var trialAskRetry: Task<Void, Never>?
    /// A voice to-do request holds the ask back this long, so the recording it asked for starts first (it starts about
    /// half a second after the To-do tab comes to the front, `TodoRootView.consumeRequest`). Tests shorten it.
    @ObservationIgnored var trialAskVoiceHold: TimeInterval = 3
    @ObservationIgnored private var trialAskHeldUntil: Date?
    /// iOS's notification prompt is up (the nudge's Turn on or toggle): the trial ask then stays away.
    @ObservationIgnored private var askingPermission = false

    init(store: TakenStore, pro: ProStore? = nil, profileStore: ProfileStore = .shared, isDemo: Bool,
         launchScreen: String?, demoStack: DemoStack = .standard, clockNow: @escaping @Sendable () -> Date) {
        self.store = store
        self.isDemo = isDemo
        self.launchScreen = launchScreen
        self.clockNow = clockNow
        #if DEBUG
        self.weight = isDemo ? WeightModel.demo(screen: launchScreen, now: clockNow())
                             : WeightModel(store: .shared, isDemo: false, clockNow: clockNow)
        #else
        self.weight = WeightModel(store: .shared, isDemo: false, clockNow: clockNow)
        #endif
        self.tab = Self.tab(forScreen: launchScreen)
        let addScreen = isDemo && launchScreen == "add"
        self.demoPreselect = addScreen ? ["Vitamin D3", "Fish Oil", "Finasteride"] : []
        self.demoChoices = addScreen ? ["Finasteride": .alternate] : [:]
        self.demoQuery = isDemo && launchScreen == "add-search" ? demoStack.typedQuery : ""
        self.demoStack = isDemo ? demoStack : .standard
        self.profileStore = profileStore
        self.profile = profileStore.load()
        self.profilePhoto = profileStore.loadPhoto().flatMap { UIImage(data: $0) }
        let state = store.load()
        let now = clockNow()
        let engine = StackEngine(state: state, clock: DayClock(dayStartHour: state.settings.dayStartHour))
        self.demoPrompt = isDemo ? Self.demoRow(forScreen: launchScreen, settings: state.settings,
                                                today: engine.today(now: now)) : nil
        self.pro = pro ?? ProStore(ledger: .shared, hasLogged: !state.doses.isEmpty)
        self.state = state
        self.theme = Theme.look(state.settings.theme)
        self.now = now
        self.engine = engine
        self.today = engine.todaySummary(now: now)
        recomputeStats()
        if !state.doses.isEmpty { self.pro.noteLogged() }
        if !isDemo {
            startTicker()
            darwinObserver = DarwinObserver { [weak self] in
                guard let model = self else { return }
                Task { @MainActor in model.reload() }
            }
            NudgeRoute.shared.attach { [weak self] day in
                self?.openDay(fromNudge: day)
            }
            self.pro.onChange = { [weak self] in self?.proDidChange() }
            self.pro.start()
            // Siri and the nudge run in this process: before refusing a log on a renewing plan's lapsed cache, they
            // ask the App Store again through this store.
            ProRecheck.handler = { [weak self] in _ = await self?.pro.refresh() }
        } else {
            notificationPermission = { .notDetermined }
        }
    }

    /// The app as launched. `-demo` (with `-screen`, `-theme` and `-demo-stack`) is CI's screenshot mode
    /// (scripts/screenshots.sh, on the Debug simulator build) and is read only in Debug builds: a Release build, and so
    /// every App Store build, always opens the real store and never reads an argument (Guideline 2.5.19).
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        #if DEBUG
        var screen: String?
        if let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count {
            screen = arguments[index + 1]
        }
        guard arguments.contains("-demo") else {
            return AppModel(store: .shared, profileStore: .shared, isDemo: false, launchScreen: nil, clockNow: { Date() })
        }
        // `-theme blush` (signal, blush, phosphor, ice): the screenshots of every look.
        var look = ThemeID.signal
        if let index = arguments.firstIndex(of: "-theme"), index + 1 < arguments.count {
            look = ThemeID(stored: arguments[index + 1])
        }
        // `-demo-stack us|neutral`: the App Store sets, each on a Thursday with its weekly row (DemoStack).
        let stack = DemoStack(arguments: arguments)
        let demoNow = DemoData.referenceNow(stack: stack)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("taken-demo-\(UUID().uuidString).json")
        let store = TakenStore(fileURL: url, postsChangeNotifications: false)
        var allTaken = screen == "today-done" || screen == "today-widget-invite"
        if WeightDemo.allTaken(screen) { allTaken = true }
        var seeded = screen == "add" || screen == "add-search" || screen == "empty"
            ? StackState(settings: StackSettings(reminderEnabled: true))
            : DemoData.state(now: demoNow, allTaken: allTaken, yesterdayPartial: screen == "today-repair",
                             stack: stack)
        // The Weight screens' chart gets its weekly dose ticks, and the offer its weekly shot.
        if WeightDemo.addsWeeklyShot(screen) { seeded = DemoData.withWeeklyShot(seeded, now: demoNow) }
        seeded.settings.theme = look
        try? store.replace(with: seeded)
        // Store screenshots show Taken with Pro; -screen paywall, locked and settings-locked show it without, and
        // paywall-no-yearly shows the paywall when the App Store returned every plan but yearly.
        let lockedScreens: Set<String> = ["paywall", "locked", "settings-locked", "paywall-no-yearly", "weight-locked"]
        var offers = DemoOffers.all
        if screen == "paywall-no-yearly" { offers[.yearly] = nil }
        let demoLocked = screen.map { lockedScreens.contains($0) } ?? false
        let pro = ProStore(demoLocked: demoLocked, now: demoNow, offers: offers)
        // A demo profile with a name (its initials on every tab), in a temporary folder; first run has none.
        let profileFolder = FileManager.default.temporaryDirectory.appendingPathComponent("taken-demo-profile-\(UUID().uuidString)")
        let profiles = ProfileStore(directory: profileFolder)
        if screen != "empty" { try? profiles.save(Profile(name: "Alex Morgan")) }
        return AppModel(store: store, pro: pro, profileStore: profiles, isDemo: true, launchScreen: screen,
                        demoStack: stack, clockNow: { demoNow })
        #else
        return AppModel(store: .shared, profileStore: .shared, isDemo: false, launchScreen: nil, clockNow: { Date() })
        #endif
    }

    /// The tab a `-screen` opens on: the To-do screens on To-do, the log and the day sheet on History, the Weight screens
    /// on Weight.
    static func tab(forScreen screen: String?) -> AppTab {
        if TodoModel.opensOnTodo(screen) { return .todo }
        #if DEBUG
        if WeightDemo.opensOnWeight(screen) { return .weight }
        #endif
        switch screen {
        case "log", "history", "day": return .history
        default: return .today
        }
    }

    // MARK: Derived

    var clock: DayClock { engine.clock }
    var settings: StackSettings { state.settings }
    var hapticsOn: Bool { state.settings.hapticsEnabled }
    var activeItems: [Item] { engine.orderedItems.filter { !$0.archived } }
    var archivedItems: [Item] { engine.orderedItems.filter { $0.archived } }
    var hasStack: Bool { !activeItems.isEmpty }

    /// Items TAKE ALL logs right now: pending, and not logged in the last hour (StackEngine.repeatGuard).
    var takeAllCount: Int { engine.quickLogRows(today, now: now).count }

    /// Whether a dose may be logged right now (PRO.md). The first session ends with the first dose ever, which the
    /// ledger keeps, so erasing the log or deleting items never reopens it.
    var access: ProAccess {
        ProGate.access(status: pro.status, settled: pro.settled, legacyLog: pro.legacyLog,
                       hasLogged: !state.doses.isEmpty || pro.hasLoggedBefore, now: now)
    }

    /// Locked mode: the log stays readable, logging opens the paywall.
    var isLocked: Bool { access == .locked }

    /// "START 7 DAYS ON US" or "PRO ENDED · TAP TO CONTINUE".
    var lockedBarText: String {
        ProCopy.lockedBar(eligible: pro.introEligible, intro: pro.offers[.yearly]?.intro)
    }

    // MARK: One-time rows (the 1.1 retention build, SPEC 3.1)

    /// The one quiet row under Today's progress line, if any. Never in `-demo` unless its `-screen` asks for it.
    var todayPrompt: TodayPrompt? {
        if isDemo { return demoPrompt }
        // The Weight tab's one-time offer comes last, after every other row (SPEC 3.12).
        return TodayPrompts.pick(settings: settings, hasStack: hasStack, today: today, repairDay: repairDay,
                                 locked: isLocked, lockScreenWidget: lockScreenWidget ?? true, trialNotice: trialNotice,
                                 weightOffer: WeightOffer.shows(weight: weight.state, state: state, today: today,
                                                                clock: clock))
    }

    /// The trial reminder's words for Today while notifications cannot carry them (`TrialReminder.notice`).
    var trialNotice: String? {
        guard notificationsAllowed == false else { return nil }
        return TrialReminder.notice(status: pro.status, price: pro.renewalPrice, state: state, now: now)
    }

    static func demoRow(forScreen screen: String?, settings: StackSettings, today: DayKey) -> TodayPrompt? {
        switch screen {
        case "today-nudge-offer": return .nudgeOffer(minutes: settings.reminderMinutes)
        case "today-repair": return .repair(today.adding(-1))
        case "today-widget-invite": return .widgetInvite
        #if DEBUG
        case "today-weight-offer": return .weightOffer
        #endif
        default: return nil
        }
    }

    /// Add tab or Not now on Today's weight offer (SPEC 3.12). Either answer is final, and Add tab turns the tab on
    /// without switching to it.
    func answerWeightOffer(addTab: Bool) {
        withAnimation(.snappy(duration: 0.22)) {
            if isDemo { demoPrompt = nil }
            weight.answerOffer(addTab: addTab)
        }
        if addTab { Haptics.selection(hapticsOn) }
        if addTab && !isDemo { UIAccessibility.post(notification: .announcement, argument: "Weight tab added.") }
    }

    /// Turn on or Not now on the evening nudge offer. Either answer is kept, so the row never comes back. Turn on is
    /// the only place, with Profile's toggle, where iOS asks for notification permission.
    func answerNudgeOffer(turnOn: Bool) {
        withAnimation(.snappy(duration: 0.22)) {
            if isDemo { demoPrompt = nil }
            _ = write { $0.settings.nudgeOfferDone = true }
        }
        guard turnOn else { return }
        requirePro { [weak self] in
            guard let self else { return }
            Task { await self.turnOnNudgeFromOffer() }
        }
    }

    private func turnOnNudgeFromOffer() async {
        await setReminderEnabled(true)
        if settings.reminderEnabled {
            show(Toast(message: RetentionCopy.nudgeOn, time: Fmt.minutes(settings.reminderMinutes)))
        } else if notificationsDenied {
            show(Toast(message: RetentionCopy.notificationsOff))
        }
    }

    /// The widget invite is on screen: the day it first showed is kept, so it shows on that day only.
    func noteWidgetInviteShown() {
        guard !isDemo, settings.widgetInviteDay == nil else { return }
        let day = today.day.ordinal
        write { $0.settings.widgetInviteDay = day }
    }

    /// A tap on the widget invite (it opens how to add the widget) or its close: either way it is gone for good.
    func closeWidgetInvite(openHelp: Bool) {
        withAnimation(.snappy(duration: 0.22)) {
            if isDemo {
                demoPrompt = nil
            } else {
                _ = write { $0.settings.widgetInviteDone = true }
            }
        }
        if openHelp { sheet = .widgetHelp }
    }

    /// Someone who already has the Taken widget on the Lock Screen never gets the invite: WidgetKit lists the widgets the
    /// person configured (https://developer.apple.com/documentation/widgetkit/widgetcenter/getcurrentconfigurations(_:)),
    /// and one in a Lock Screen family counts as the invite answered. Asked each time Taken comes to the front.
    private func checkLockScreenWidget() async {
        guard !isDemo else { return }
        guard !settings.widgetInviteDone else {
            lockScreenWidget = false
            return
        }
        let found = await Self.lockScreenWidgetConfigured()
        lockScreenWidget = found
        if found && !settings.widgetInviteDone { write { $0.settings.widgetInviteDone = true } }
    }

    private static func lockScreenWidgetConfigured() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            WidgetCenter.shared.getCurrentConfigurations { result in
                // An error reads as none, so the invite still shows once.
                let widgets = ((try? result.get()) ?? []).map { (kind: $0.kind, family: $0.family) }
                continuation.resume(returning: TodayPrompts.hasLockScreenWidget(widgets))
            }
        }
    }

    /// The repair line's close: hidden for the day it was about, so nobody who really missed a dose is pushed to record
    /// one. It never says the streak broke.
    func closeRepair(_ day: DayKey) {
        withAnimation(.snappy(duration: 0.22)) {
            if isDemo {
                demoPrompt = nil
            } else {
                _ = write { $0.settings.repairClosedDay = day.ordinal }
            }
        }
    }

    func nextLabel(for row: ItemDay) -> String {
        Fmt.next(engine.nextDueDay(for: row.item, after: today.day), today: today.day)
    }

    /// A row in Not today and the line under its name. A weekly item shows the week today is in (SPEC 3.3): its due day,
    /// open ("Weekly · Thu · Not logged") or logged ("Weekly · Next: Thursday"), or the next due day an early dose
    /// already counts for ("Weekly · Counts for Thursday"). In the 1 to 3 days before the next due day, with this week
    /// logged, it is today's quiet ring instead ("Weekly · Next: Thursday"), so an early dose is one tap, as before this
    /// build, and counts for the next due day (R1 b). Anything else is today's row, as before.
    func notTodayRow(_ row: ItemDay) -> (row: ItemDay, note: String) {
        if !engine.takesEarlyDose(row.item, today: today.day),
           let week = engine.weekRow(for: row.item, today: today.day) {
            return (week, Fmt.weekNote(week, today: today.day))
        }
        let note = row.doses.isEmpty ? Fmt.notDue(row.frequency, next: nextLabel(for: row)) : Fmt.frequency(row.frequency)
        return (row, note)
    }

    func sheetSummary(for day: DayKey) -> DaySummary { engine.sheetSummary(for: day, asOf: today.day) }

    /// The dose Set time corrects: the item's latest dose logged today, whichever day it counts for. Nil logs a new one.
    func setTimeDose(for item: Item) -> Dose? {
        state.doses.filter { $0.itemId == item.id && clock.day(of: $0) == today.day }.max(by: { $0.takenAt < $1.takenAt })
    }

    /// Set time belongs on a row whose last dose was logged today, or that has none and is today's. Otherwise (a weekly
    /// row whose dose was logged another day, or whose week is open) the row offers its day's sheet instead.
    func offersSetTime(_ row: ItemDay) -> Bool {
        guard let last = row.lastDose else { return row.day == today.day }
        return clock.day(of: last) == today.day
    }

    func csv() -> String { CSVExport.make(state: state) }

    // MARK: Lifecycle

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.tick()
            }
        }
    }

    private func tick() {
        let fresh = clockNow()
        let dayChanged = clock.day(for: fresh) != today.day
        now = fresh
        today = engine.todaySummary(now: fresh)
        if dayChanged { recomputeStats() }
        // Open across a plan's period end: the renewal is checked with the App Store then, not at the next launch.
        pro.checkRenewalIfDue(now: fresh)
    }

    func reload() {
        let fresh = store.load()
        if fresh != state {
            apply(fresh)
        } else {
            tick()
        }
    }

    func didBecomeActive() {
        // Always rebuild: the time zone or the day may have changed while the app was away.
        apply(store.load())
        weight.refresh()
        guard !isDemo else { return }
        let snapshot = state
        // A Taken widget added to the Lock Screen while Taken was away ends the widget invite before it shows. Its own
        // task, so a slow answer from WidgetKit never holds up the renewal check or the nudges below.
        Task { await checkLockScreenWidget() }
        Task {
            // Renewals, refunds and purchases made elsewhere land here (PRO.md: refresh on foreground).
            await pro.foreground()
            await Reminders.reschedule(state: snapshot, now: Date())
            // Due-time notifications too: tasks saved before notifications were allowed get theirs now.
            await TodoNotificationScheduler.shared.reschedule(TodoStore.shared.load().tasks)
            let permission = await self.notificationPermission()
            self.notificationsDenied = permission == .denied && snapshot.settings.reminderEnabled
            self.notificationsAllowed = permission == .allowed
        }
        consumePendingLog()
        // A first dose logged from a widget, or an app closed before the sheet came up, still gets its one paywall.
        if !state.doses.isEmpty && !pro.introShown { scheduleIntro() }
        // An icon change that could not finish (the app left the foreground first) is finished now.
        scheduleIconSync(after: .milliseconds(900))
    }

    func applyLaunchScreen() async {
        guard let launchScreen else { return }
        try? await Task.sleep(for: .milliseconds(450))
        switch launchScreen {
        case "add", "add-search": sheet = .add
        case "settings", "profile", "look", "settings-locked": sheet = .settings
        case "day": sheet = .day(DemoData.sheetDay(now: now))
        case "item":
            if let item = state.items.first(where: { $0.name == "Finasteride" }) { sheet = .editItem(item.id) }
        case "paywall", "paywall-no-yearly": presentPaywall(origin: .intro)
        case "widget-help": sheet = .widgetHelp
        case "trial-ask": trialAsk = .root
        #if DEBUG
        case "weight-list": sheet = .weighIns
        case "weight-settings", "weight-data": sheet = .settings
        case "weight-goal-sheet", "weight-goal-low": sheet = .weightGoal
        #endif
        default: break
        }
    }

    // MARK: Tabs

    /// A voice to-do request (Siri, the Action button, the control, the Lock Screen, a link, a notification, the quick
    /// action): the To-do tab comes to the front and any sheet over it closes, so Listening and the stop button show.
    func openTodoTab() {
        if sheet != nil { sheet = nil }
        // The trial ask steps aside for the recording, held back until it has started, and comes back once it is done.
        if trialAsk != nil {
            trialAsk = nil
            if !trialAskAnswered { trialAskDue = true }
        }
        if trialAskDue {
            trialAskHeldUntil = Date().addingTimeInterval(trialAskVoiceHold)
            retryTrialAsk()
        }
        tab = .todo
    }

    /// The To-do tab is in front with no sheet, paywall or trial ask over it: the mic may open.
    var showsTodoTabUncovered: Bool { tab == .todo && sheet == nil && paywall == nil && trialAsk == nil }

    func handle(url: URL) {
        guard url.scheme == "taken" else { return }
        reload()
        guard let route = ProRoute(url: url) else {
            // taken://today (a widget), taken://todo (the To-do tab follows on its own): whatever was open closes.
            sheet = nil
            if url.host == "today" { tab = .today }
            // taken://weight: the Weight tab, or Today while it is off.
            if url.host == "weight" { openWeightTab() }
            return
        }
        // taken://pro from a locked widget: the tap it was, run once Pro is on.
        let requestedAt = clockNow()
        var pending: (@MainActor () -> Void)?
        if let action = route.then {
            pending = { [weak self] in self?.applyPending(PendingLog(action: action, at: requestedAt)) }
        }
        Task { [weak self, pending] in
            guard let self else { return }
            // A renewal may have arrived since the widget last drew.
            await self.pro.refresh()
            if self.access.allowsLogging {
                pending?()
            } else {
                self.presentPaywall(origin: .link, pending: pending)
            }
        }
    }

    /// A tapped nudge opens on the day it was for: today's on Today, an earlier day's on its sheet over History.
    func openDay(fromNudge day: DayKey) {
        reload()
        tab = day == today.day ? .today : .history
        sheet = day == today.day ? nil : .day(day)
    }

    private func apply(_ fresh: StackState) {
        state = fresh
        if !fresh.doses.isEmpty { pro.noteLogged() }
        if fresh.settings.theme != theme.id {
            theme = Theme.look(fresh.settings.theme)
            scheduleIconSync()
        }
        now = clockNow()
        engine = StackEngine(state: fresh, clock: DayClock(dayStartHour: fresh.settings.dayStartHour))
        today = engine.todaySummary(now: now)
        recomputeStats()
    }

    private func recomputeStats() {
        history = engine.history(today: today.day)
        streak = engine.streak(today: today.day)
        adherence = engine.adherence(today: today.day)
        repairDay = TodayPrompts.repairDay(engine: engine, today: today.day)
    }

    /// Every write goes through here: coordinated store write, then widgets, controls, nudges.
    @discardableResult
    private func write<T>(_ body: (inout StackState) throws -> T) -> T? {
        do {
            let hadLogged = !state.doses.isEmpty
            let result = try store.update(body)
            apply(result.state)
            if !isDemo {
                let snapshot = result.state
                Task { await Sync.afterWrite(snapshot) }
            }
            // The first dose ever: the moment Taken makes sense. The paywall follows it once (PRO.md).
            if !hadLogged && !result.state.doses.isEmpty { scheduleIntro() }
            return result.value
        } catch {
            show(Toast(message: "Could not save. Try again."))
            return nil
        }
    }

    // MARK: Taken Pro

    /// Runs `action` while logging is open; otherwise opens the paywall and runs it once Pro is on.
    func requirePro(_ anchor: PaywallAnchor = .root, _ action: @escaping @MainActor () -> Void) {
        switch access {
        case .pro, .firstSession, .pending:
            action()
        case .locked:
            presentPaywall(anchor: anchor, origin: .action, pending: action)
        case .checking:
            Task { [weak self] in
                guard let self else { return }
                await self.pro.settle()
                self.requirePro(anchor, action)
            }
        }
    }

    func presentPaywall(anchor: PaywallAnchor = .root, origin: PaywallOrigin, pending: (@MainActor () -> Void)? = nil) {
        guard paywall == nil else { return }
        // Any paywall counts as the one after the first dose, so it never comes up on its own a second time. Plans
        // looked at from Settings before anything was logged do not: the first dose still brings it up once.
        if origin != .settings || !state.doses.isEmpty { pro.markIntroShown() }
        Task { await pro.loadOffers() }
        let request = PaywallRequest(anchor: anchor, origin: origin, pending: pending)
        if anchor == .root && sheet != nil {
            // A sheet is up on TODAY: it closes first, then the paywall slides up.
            sheet = nil
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard let self, self.paywall == nil else { return }
                self.paywall = request
            }
        } else {
            paywall = request
        }
    }

    func closePaywall() {
        paywall = nil
    }

    /// Pro just came on in the paywall: what opened it runs once the sheet has gone. A trial that started there gets the
    /// one notification ask after it (`TrialAsk`).
    func paywallUnlocked(trialStarted: Bool = false) {
        if let pending = paywall?.pending { afterPaywall = pending }
        if trialStarted, paywall != nil { trialAskAfterPaywall = true }
    }

    /// The paywall sheet finished closing.
    func paywallDidDismiss() {
        let action = afterPaywall
        afterPaywall = nil
        if trialAskAfterPaywall {
            trialAskAfterPaywall = false
            // The sheet the paywall was over, before the tap that opened it runs (it may close that sheet or open one).
            let over = sheet
            Task { [weak self] in await self?.offerTrialAsk(over: over) }
        } else if trialAskDue {
            retryTrialAsk()
        }
        guard let action, access.allowsLogging else { return }
        action()
    }

    // MARK: The trial promise (SPEC 3.9, 2026-10-21)

    /// Right after a trial starts: the one short sheet asking for notifications, for the evening nudge and the reminder
    /// before the trial ends, only while iOS has not asked yet and only once. When iOS already has an answer, the
    /// reminder follows it (scheduled only when allowed). The ask never takes the screen from the person: while the
    /// tap that opened the paywall has opened a sheet, started a voice note or brought up iOS's prompt, it waits, and
    /// it comes when nothing else holds the screen, on TODAY or over the sheet the paywall was over if that is still
    /// up. `over` is that sheet (nil on TODAY).
    func offerTrialAsk(over route: SheetRoute?) async {
        // The paywall has gone and the tap that opened it has run (it may be the nudge's own Turn on).
        try? await Task.sleep(for: .milliseconds(400))
        let permission = await notificationPermission()
        guard TrialAsk.shows(trialStarted: true, permission: permission, alreadyShown: pro.trialAskShown) else {
            await rescheduleReminders()
            return
        }
        trialAskDue = true
        trialAskSheet = route
        presentTrialAskIfClear()
    }

    /// Shows the waiting ask where the person is, once nothing else holds the screen (`trialAskLevel`). Returns the
    /// level it went to, or nil while it still waits.
    @discardableResult
    func presentTrialAskIfClear() -> PaywallAnchor? {
        guard trialAskDue, trialAsk == nil, let level = trialAskLevel() else { return nil }
        trialAskDue = false
        trialAskAnswered = false
        trialAsk = level
        return level
    }

    /// Where the ask may show right now, or nil while the person is busy: a paywall or iOS's prompt is up, a voice note
    /// is starting, being heard or sorted, a sheet inside a sheet is up, a sheet opened since the paywall (the Add sheet
    /// a locked "+" asked for) is up, or a sheet is still opening or closing. Over the sheet the paywall was over while
    /// it is still up; otherwise on TODAY.
    private func trialAskLevel() -> PaywallAnchor? {
        if let held = trialAskHeldUntil, Date() < held { return nil }
        guard paywall == nil, !askingPermission, !captureBusy(), (levelsOnScreen[.nested] ?? 0) == 0 else { return nil }
        let sheetOnScreen = (levelsOnScreen[.sheet] ?? 0) > 0
        if let sheet {
            return sheetOnScreen && sheet == trialAskSheet ? .sheet : nil
        }
        return sheetOnScreen ? nil : .root
    }

    /// Tries the waiting ask again after a moment, so a sheet that just closed has finished: iOS's prompt may have
    /// answered it meanwhile, and then it is dropped and the reminder follows that answer.
    func retryTrialAsk(after delay: Duration = .milliseconds(350)) {
        guard trialAskDue else { return }
        // Held back for a voice to-do request: not before the hold ends.
        let heldFor = max(trialAskHeldUntil?.timeIntervalSinceNow ?? 0, 0)
        let wait = heldFor > 0 ? max(delay, .milliseconds(Int(heldFor * 1000) + 200)) : delay
        trialAskRetry?.cancel()
        trialAskRetry = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, !Task.isCancelled, self.trialAskDue, self.trialAsk == nil else { return }
            guard await self.notificationPermission() == .notDetermined else {
                self.trialAskDue = false
                await self.rescheduleReminders()
                return
            }
            self.presentTrialAskIfClear()
        }
    }

    /// A sheet above TODAY came on screen (`PaywallHost`), at `.sheet` or `.nested`.
    func levelDidAppear(_ level: PaywallAnchor) {
        guard level != .root else { return }
        levelsOnScreen[level, default: 0] += 1
    }

    /// A sheet above TODAY has gone: the waiting ask may come now.
    func levelDidDisappear(_ level: PaywallAnchor) {
        guard level != .root else { return }
        levelsOnScreen[level] = max((levelsOnScreen[level] ?? 0) - 1, 0)
        // An ask over a sheet that something else closed went with it: it comes back on TODAY.
        if trialAsk == level, (levelsOnScreen[level] ?? 0) == 0 {
            trialAsk = nil
            if !trialAskAnswered { trialAskDue = true }
        }
        retryTrialAsk()
    }

    /// A voice note finished (the To-do tab's phase is back to idle): the waiting ask may come now.
    func captureDidSettle() {
        retryTrialAsk()
    }

    /// The ask is on screen: only now is the one ask used up (`ProLedger.trialAskAt`).
    func trialAskDidAppear() {
        pro.markTrialAskShown()
    }

    /// Continue, the ask's one button: iOS's prompt follows, and iOS's alert carries the no. Allowed: the evening nudge
    /// comes on at its time, which answers Today's nudge offer, and the trial reminder is scheduled with it. Either answer
    /// to iOS answers Today's nudge offer too, so there is never a second ask (own choice).
    func answerTrialAsk() async {
        trialAskAnswered = true
        await setReminderEnabled(true)
        if !settings.nudgeOfferDone { write { $0.settings.nudgeOfferDone = true } }
        trialAsk = nil
        if settings.reminderEnabled {
            show(Toast(message: RetentionCopy.nudgeOn, time: Fmt.minutes(settings.reminderMinutes)))
        } else if notificationsDenied {
            show(Toast(message: RetentionCopy.notificationsOff))
        }
    }

    /// The ask has gone. It cannot be swiped away, so without Continue something else closed it (a voice to-do
    /// request): it comes back once nothing else holds the screen.
    func trialAskDidDismiss() {
        trialAsk = nil
        guard !trialAskAnswered else { return }
        trialAskDue = true
        retryTrialAsk()
    }

    private func rescheduleReminders() async {
        guard !isDemo else { return }
        let snapshot = state
        await Reminders.reschedule(state: snapshot, now: Date())
    }

    /// About 1.5 s after the first dose the paywall slides up, once.
    private func scheduleIntro(after delay: Duration = .milliseconds(1500)) {
        guard !isDemo, !pro.introShown, introTask == nil else { return }
        introTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            await self.pro.settle()
            self.introTask = nil
            self.showIntroIfDue()
        }
    }

    private func showIntroIfDue() {
        guard !pro.introShown, paywall == nil, access == .locked else { return }
        guard sheet == nil else {
            // Never over a sheet in use: it waits for the sheet to close.
            introWaitsForSheet = true
            return
        }
        presentPaywall(origin: .intro)
    }

    /// A sheet on TODAY finished closing.
    func rootSheetDidDismiss() {
        if iconWaitsForSettings {
            iconWaitsForSettings = false
            scheduleIconSync(after: .milliseconds(350))
        }
        // The trial ask waiting for this sheet to close comes now (`presentTrialAskIfClear`).
        retryTrialAsk()
        guard introWaitsForSheet else { return }
        introWaitsForSheet = false
        scheduleIntro(after: .milliseconds(500))
    }

    /// A log a widget, the control, Siri or a nudge could not make while locked, offered now Taken is open.
    private func consumePendingLog() {
        guard let pending = pro.takePendingLog(maxAge: 10 * 60, now: clockNow()) else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.pro.refresh()
            self.requirePro { [weak self] in self?.applyPending(pending) }
        }
    }

    /// Logs what was asked for, at the time it was asked for.
    private func applyPending(_ pending: PendingLog) {
        switch pending.action {
        case .takeAll:
            takeAll(at: pending.at)
        case .log(let id):
            logIfPending(itemID: id, at: pending.at)
        }
    }

    private func proDidChange() {
        guard !isDemo else { return }
        let snapshot = state
        // Widgets, the control and the nudges follow Pro.
        Task { await Sync.afterWrite(snapshot) }
    }

    // MARK: Taking

    /// Tap on a row: pending logs a dose, taken shows the detail. Never un-takes. A weekly item's open week logs from
    /// its ring (it counts for the due day, at the real time); once the week is logged a tap only shows the detail, until
    /// the 1 to 3 days before the next due day, when the row is today's quiet ring and logs an early dose
    /// (`notTodayRow`).
    func tap(_ row: ItemDay) {
        if row.isPending || row.isOpen || (!row.isDue && row.doses.isEmpty) {
            let item = row.item
            requirePro { [weak self] in self?.log(item) }
        } else {
            Haptics.soft(hapticsOn)
            withAnimation(.snappy(duration: 0.22)) {
                expandedItemID = expandedItemID == row.id ? nil : row.id
            }
        }
    }

    func log(_ item: Item, at time: Date? = nil) {
        let at = time ?? clockNow()
        let wasLocked = today.allTaken
        let zone = clock.calendar.timeZone
        guard let dose = write({ $0.logDose(itemId: item.id, at: at, timeZone: zone) }) ?? nil else { return }
        afterTake(wasLocked: wasLocked)
        show(Toast(message: "\(item.name) taken at", time: Fmt.clock(at, clock), undo: .remove([dose.id])))
        announce("\(item.name) taken at \(Fmt.spoken(at)).")
    }

    /// A widget row asked for this item: logs only while a dose is still pending, never twice in the hour.
    private func logIfPending(itemID: UUID, at: Date) {
        let wasLocked = today.allTaken
        let clock = self.clock
        guard let dose = write({ $0.logNextDoseIfPending(itemId: itemID, now: at, clock: clock) }) ?? nil,
              let item = state.item(dose.itemId) else { return }
        afterTake(wasLocked: wasLocked)
        show(Toast(message: "\(item.name) taken at", time: Fmt.clock(at, clock), undo: .remove([dose.id])))
        announce("\(item.name) taken at \(Fmt.spoken(at)).")
    }

    func takeAll(at time: Date? = nil) {
        let at = time ?? clockNow()
        let wasLocked = today.allTaken
        let clock = self.clock
        guard let logged = write({ $0.takeAllPending(now: at, clock: clock) }), !logged.isEmpty else { return }
        afterTake(wasLocked: wasLocked)
        show(Toast(message: "\(logged.count) taken at", time: Fmt.clock(at, clock), undo: .remove(Set(logged.map(\.id)))))
        announce("\(logged.count) taken at \(Fmt.spoken(at)).")
    }

    private func afterTake(wasLocked: Bool) {
        if !wasLocked && today.allTaken {
            Haptics.success(hapticsOn)
            lockInCount += 1
        } else {
            Haptics.impact(hapticsOn)
        }
    }

    func undo(_ toast: Toast) {
        guard let step = toast.undo else { return }
        switch step {
        case .remove(let ids):
            write { $0.removeDoses(ids) }
        case .restore(let doses):
            write { state in
                for dose in doses { state.restore(dose) }
            }
        case .removeWeighIn, .restoreWeighIn, .showWeightTab, .restoreWeightGoal:
            undoWeight(step)
        }
        Haptics.soft(hapticsOn)
        dismissToast()
        announce("Undone.")
    }

    /// Removes the row's latest dose: today's on a Stack row, and on a weekly row the one that counts for its week,
    /// whatever day it was logged. The toast's UNDO puts it back with its original time.
    func undoLastDose(_ row: ItemDay) {
        guard let last = row.lastDose else { return }
        let item = row.item
        write { $0.removeDoses([last.id]) }
        Haptics.soft(hapticsOn)
        show(Toast(message: "\(item.name): last dose removed", undo: .restore([last])))
        announce("\(item.name), last dose removed.")
    }

    /// The moment a wall-clock time means on a logical day, and whether it is still to come.
    func moment(on day: DayKey, minutes: Int) -> (date: Date, isFuture: Bool) {
        let date = clock.date(on: day, hour: minutes / 60, minute: minutes % 60)
        return (date, date > clockNow())
    }

    /// Set time: corrects today's latest dose, or logs one at that time if none yet. A time still to come
    /// is never used (the sheet disables it), and the toast's UNDO restores the time it replaced.
    func setTime(_ item: Item, hour: Int, minute: Int) {
        let clock = self.clock
        let (at, isFuture) = moment(on: today.day, minutes: hour * 60 + minute)
        guard !isFuture else { return }
        let zone = clock.calendar.timeZone
        let existing = setTimeDose(for: item)
        let wasLocked = today.allTaken
        if let existing {
            write { $0.setDoseTime(doseId: existing.id, to: at, timeZone: zone) }
            Haptics.impact(hapticsOn)
            show(Toast(message: "\(item.name) set to", time: Fmt.clock(at, clock), undo: .restore([existing])))
            announce("\(item.name) set to \(Fmt.spoken(at)).")
        } else if let dose = write({ $0.logDose(itemId: item.id, at: at, timeZone: zone) }) ?? nil {
            afterTake(wasLocked: wasLocked)
            show(Toast(message: "\(item.name) taken at", time: Fmt.clock(at, clock), undo: .remove([dose.id])))
            announce("\(item.name) taken at \(Fmt.spoken(at)).")
        }
    }

    // MARK: Backfill (day sheet)

    /// Logs a dose at a time on a day. A time still to come is never used (the sheet disables it).
    func logDose(_ item: Item, on day: DayKey, minutes: Int) {
        let (at, isFuture) = moment(on: day, minutes: minutes)
        guard !isFuture else { return }
        let zone = clock.calendar.timeZone
        let logged = write({ $0.logDose(itemId: item.id, at: at, timeZone: zone) }) ?? nil
        guard logged != nil else { return }
        Haptics.impact(hapticsOn)
        announce("\(item.name) logged at \(Fmt.spoken(at)).")
    }

    func removeDose(_ dose: Dose) {
        write { $0.removeDoses([dose.id]) }
        Haptics.soft(hapticsOn)
    }

    // MARK: Stack editing

    func addItems(_ drafts: [ItemDraft]) {
        let at = clockNow()
        guard let added = write({ $0.addItems(drafts, now: at) }), !added.isEmpty else { return }
        Haptics.impact(hapticsOn)
        show(Toast(message: added.count == 1 ? "\(added[0].name) added" : "\(added.count) added to your stack"))
        refreshShortcuts()
    }

    func updateItem(id: UUID, name: String, code: String, frequency: Frequency, archived: Bool) {
        let at = clockNow()
        write { state in
            state.updateItem(id: id, name: name, code: code, frequency: frequency, now: at)
            state.setArchived(id: id, archived: archived, now: at)
        }
        refreshShortcuts()
    }

    func deleteItem(id: UUID) {
        write { $0.deleteItem(id: id) }
        if expandedItemID == id { expandedItemID = nil }
        refreshShortcuts()
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        write { $0.moveActiveItems(fromOffsets: source, toOffset: destination) }
    }

    private func refreshShortcuts() {
        guard !isDemo else { return }
        TakenShortcuts.updateAppShortcutParameters()
    }

    // MARK: Settings

    /// The NUDGE toggle. Turning it off always works. Turning it on needs Pro once something has been logged (no nudge
    /// is scheduled without it): locked, the tap opens the paywall and the nudge, with iOS's permission prompt, comes
    /// on once Pro does.
    func setReminder(_ enabled: Bool, anchor: PaywallAnchor) {
        guard enabled else {
            Task { await setReminderEnabled(false) }
            return
        }
        requirePro(anchor) { [weak self] in
            guard let self else { return }
            Task { await self.setReminderEnabled(true) }
        }
    }

    func setReminderEnabled(_ enabled: Bool) async {
        if enabled && !isDemo {
            askingPermission = true
            let granted = await Reminders.requestPermission()
            askingPermission = false
            notificationsDenied = !granted
            notificationsAllowed = granted
            // A trial ask waiting for this prompt: iOS has its answer now, so it is dropped (`retryTrialAsk`).
            retryTrialAsk()
            guard granted else { return }
            // Notifications are allowed now: to-dos with a time get theirs too.
            await TodoNotificationScheduler.shared.reschedule(TodoStore.shared.load().tasks)
        }
        if !enabled { notificationsDenied = false }
        // Profile's toggle answers Today's nudge offer too, so the offer never comes back after it is turned off.
        write { $0.settings.setReminder(enabled) }
    }

    func setReminderMinutes(_ minutes: Int) {
        write { $0.settings.reminderMinutes = minutes }
    }

    /// Profile > Reminder > Trial reminder. Off withdraws it, pending or delivered, and Today's line with it; the write
    /// reschedules (`Sync.afterWrite`).
    func setTrialReminder(_ enabled: Bool) {
        write { $0.settings.trialReminderEnabled = enabled }
    }

    /// Profile > Wake-up time. The day rolls over 4 hours before it (never seen or set), so every view, widget, Siri
    /// answer and nudge follows at once; the nudge moves with it until a nudge time is chosen.
    func setWakeMinutes(_ minutes: Int) {
        write { $0.settings.wakeMinutes = StackSettings.clampMinutes(minutes) }
        TodoModel.shared.attach(self)
    }

    // MARK: Profile

    func setProfileName(_ name: String) {
        var next = profile
        next.name = Profile.clean(name)
        guard next != profile else { return }
        profile = next
        guard !isDemo else { return }
        try? profileStore.save(next)
    }

    /// A photo from the photo picker: the centre square, kept small, on this iPhone.
    func setProfilePhoto(_ data: Data) async {
        let prepared = await Task.detached(priority: .userInitiated) { ProfilePhoto.prepare(data) }.value
        guard let prepared, let image = UIImage(data: prepared) else { return }
        if !isDemo { try? profileStore.savePhoto(prepared) }
        withAnimation(.snappy(duration: 0.25)) { profilePhoto = image }
    }

    func removeProfilePhoto() {
        if !isDemo { profileStore.removePhoto() }
        withAnimation(.snappy(duration: 0.25)) { profilePhoto = nil }
    }

    func setHaptics(_ enabled: Bool) {
        write { $0.settings.hapticsEnabled = enabled }
        Haptics.selection(enabled)
    }

    // MARK: Look

    /// One tap in Settings > LOOK. The app recolours at once; the widgets and the control reload with the write, and
    /// the app icon follows once Settings closes (iOS confirms an icon change with its own alert).
    func setLook(_ look: ThemeID) {
        guard look != theme.id else { return }
        Haptics.selection(hapticsOn)
        withAnimation(.easeInOut(duration: 0.3)) {
            _ = write { $0.settings.theme = look }
        }
    }

    /// Switches the app icon to the look's own after a short pause. While Settings is open it waits for Settings to
    /// close, so trying every look ends in one icon change and one system alert. Signal is the primary icon.
    private func scheduleIconSync(after delay: Duration = .milliseconds(600)) {
        guard !isDemo else { return }
        iconTask?.cancel()
        iconTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if self.sheet == .settings {
                self.iconWaitsForSettings = true
                return
            }
            await self.syncAppIcon()
        }
    }

    private func syncAppIcon() async {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active else { return }
        let wanted = theme.id.alternateIconName
        guard app.alternateIconName != wanted else { return }
        try? await app.setAlternateIconName(wanted)
    }

    /// Erase all data: the stack, every dose, the settings, every to-do, the profile, and any unreadable copy a write set
    /// aside. The look stays, and so do the Taken Pro status file and the date of the first voice note.
    func eraseAll() {
        write { $0.eraseAll() }
        TodoModel.shared.eraseAll()
        // The weigh-ins go; the tab setting, the unit, the offer's answer and the first weigh-in's date stay.
        weight.eraseAll()
        if !isDemo {
            profileStore.erase()
            store.removeSetAsideCopies()
            TodoModel.shared.store.removeSetAsideCopies()
        }
        profile = Profile()
        profilePhoto = nil
        expandedItemID = nil
        refreshShortcuts()
    }

    // MARK: Toast

    func show(_ toast: Toast) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { self.toast = toast }
        // With VoiceOver the toast stays until it is dismissed, so UNDO is still there after a swipe to it.
        guard !UIAccessibility.isVoiceOverRunning else { return }
        let id = toast.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.toast?.id == id else { return }
            withAnimation(.snappy(duration: 0.2)) { self.toast = nil }
        }
    }

    /// Spoken confirmation for VoiceOver.
    private func announce(_ text: String) {
        guard !isDemo else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    func dismissToast() {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { toast = nil }
    }
}

@MainActor
enum Haptics {
    static func impact(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success(_ enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func selection(_ enabled: Bool) {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
