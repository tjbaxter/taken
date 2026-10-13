import XCTest
@testable import Taken

/// The four looks (SPEC section 4): the choice persists in the App Group store with the stack, a file from before
/// looks existed (or with a look this version does not know) reads as Signal without losing anything else, Signal is
/// 1.0's look exactly, every look's text passes WCAG AA, and each look's app icon ships in the bundle.
final class ThemeTests: XCTestCase {

    // MARK: Persistence

    func testAFileFromBeforeLooksReadsAsSignal() throws {
        let json = #"{"items":[],"doses":[],"settings":{"dayStartHour":3,"reminderEnabled":true,"reminderMinutes":1230,"hapticsEnabled":false}}"#
        let state = try TakenStore.decode(Data(json.utf8))
        XCTAssertEqual(state.settings.theme, .signal)
        XCTAssertEqual(state.settings.dayStartHour, 3, "the other settings are untouched")
        XCTAssertEqual(state.settings.reminderMinutes, 1230)
        XCTAssertFalse(state.settings.hapticsEnabled)
        XCTAssertEqual(StackSettings().theme, .signal, "new installs start on Signal")
    }

    func testAnUnknownLookReadsAsSignalAndKeepsTheRest() throws {
        let later = #"{"settings":{"dayStartHour":5,"theme":"aurora","reminderEnabled":true}}"#
        let state = try TakenStore.decode(Data(later.utf8))
        XCTAssertEqual(state.settings.theme, .signal, "a look from a later version")
        XCTAssertEqual(state.settings.dayStartHour, 5)
        XCTAssertTrue(state.settings.reminderEnabled)

        let malformed = #"{"settings":{"dayStartHour":6,"theme":7}}"#
        let other = try TakenStore.decode(Data(malformed.utf8))
        XCTAssertEqual(other.settings.theme, .signal, "not even a string")
        XCTAssertEqual(other.settings.dayStartHour, 6)

        let cased = #"{"settings":{"theme":"BLUSH"}}"#
        XCTAssertEqual(try TakenStore.decode(Data(cased.utf8)).settings.theme, .blush)
    }

    func testTheLookRoundTripsThroughTheAppGroupStore() throws {
        let store = TakenStore(fileURL: temporaryStoreURL(), postsChangeNotifications: false)
        for look in ThemeID.allCases {
            try store.update { $0.settings.theme = look }
            XCTAssertEqual(store.load().settings.theme, look)
            XCTAssertEqual(TakenStore(fileURL: store.fileURL, postsChangeNotifications: false).load().settings.theme, look,
                           "the widget extension and the control read the same file")
        }
        let data = try TakenStore.encode(StackState(settings: StackSettings(theme: .phosphor)))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""theme":"phosphor""#), text)
    }

    func testEraseAllKeepsTheLook() {
        var state = StackState(items: [makeItem("Zinc", "ZNC", created: at(2026, 10, 1, 8))],
                               settings: StackSettings(dayStartHour: 2, reminderEnabled: true, theme: .ice))
        state.eraseAll()
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertEqual(state.settings.dayStartHour, 4, "settings reset")
        XCTAssertFalse(state.settings.reminderEnabled)
        XCTAssertEqual(state.settings.theme, .ice, "the look is how the phone shows Taken, not data")
    }

    func testWidgetsReadTheLookFromTheStore() {
        var state = DemoData.state(now: at(2026, 10, 12, 21, 41), allTaken: false, timeZone: london)
        state.settings.theme = .blush
        let snapshot = WidgetSnapshot(state: state, now: at(2026, 10, 12, 21, 41), timeZone: london)
        XCTAssertEqual(snapshot.theme, .blush)
        XCTAssertEqual(snapshot.theme.theme, Theme.blush)
        XCTAssertEqual(WidgetSnapshot.demo(now: at(2026, 10, 12, 21, 41), theme: .ice).theme, .ice,
                       "the widget gallery preview follows the look too")
        XCTAssertEqual(WidgetSnapshot(state: StackState(), now: at(2026, 10, 12, 9)).theme, .signal)
    }

    @MainActor
    func testScreenshotLaunchArgumentsPickTheLook() {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today", "-theme", "blush"])
        XCTAssertTrue(model.isDemo)
        XCTAssertEqual(model.theme.id, .blush)
        XCTAssertEqual(model.state.settings.theme, .blush)
        XCTAssertEqual(AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "add", "-theme", "ice"]).theme.id, .ice)
        XCTAssertEqual(AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"]).theme.id, .signal)
    }

    // MARK: Names and icons

    func testNames() {
        XCTAssertEqual(ThemeID.allCases, [.signal, .blush, .phosphor, .ice], "the order in Settings")
        XCTAssertEqual(ThemeID.allCases.map(\.label), ["SIGNAL", "BLUSH", "PHOSPHOR", "ICE"])
        XCTAssertEqual(ThemeID.allCases.map(\.rawValue), ["signal", "blush", "phosphor", "ice"],
                       "stored in taken.json: never renamed")
        XCTAssertEqual(ThemeID(stored: "Phosphor"), .phosphor)
        XCTAssertEqual(ThemeID(stored: "ice"), .ice)
        XCTAssertEqual(ThemeID(stored: ""), .signal)
        XCTAssertEqual(ThemeID(stored: nil), .signal)
        XCTAssertEqual(Theme.all.map(\.id), ThemeID.allCases)
        for id in ThemeID.allCases {
            XCTAssertEqual(Theme.look(id).id, id)
        }
    }

    func testEachLookHasItsOwnIconAndSignalIsThePrimary() {
        XCTAssertNil(ThemeID.signal.alternateIconName, "Signal is the primary icon")
        XCTAssertEqual(ThemeID.blush.alternateIconName, "AppIcon-Blush")
        XCTAssertEqual(ThemeID.phosphor.alternateIconName, "AppIcon-Phosphor")
        XCTAssertEqual(ThemeID.ice.alternateIconName, "AppIcon-Ice")
    }

    func testTheAlternateIconsShipInTheApp() throws {
        // The test host is Taken.app: actool writes the alternate icons into its Info.plist from
        // ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES, and setAlternateIconName only accepts names listed there.
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any], "\(icons)")
        for look in ThemeID.allCases {
            guard let name = look.alternateIconName else { continue }
            XCTAssertNotNil(alternates[name], "\(name) is missing from CFBundleAlternateIcons: \(alternates.keys.sorted())")
        }
    }

    // MARK: Tokens

    func testSignalIsTheOriginalLookExactly() {
        let t = Theme.signal.tokens
        XCTAssertEqual([t.bg, t.bgRaised, t.bgInset], [0x08090A, 0x0F1012, 0x16171A])
        XCTAssertEqual([t.fg, t.fgMuted, t.fgSubtle, t.fgFaint], [0xF4F4F5, 0xA1A1AA, 0x7C7C85, 0x52525B])
        XCTAssertEqual(t.lineBase, 0xFFFFFF)
        XCTAssertEqual([t.line, t.lineStrong], [0.10, 0.18])
        XCTAssertEqual(t.dashBase, 0xA1A1AA)
        XCTAssertEqual([t.lineDash, t.tick], [0.20, 0.34])
        XCTAssertEqual([t.signal, t.signalInk, t.onSignal, t.bracket], [0xFFB000, 0xFFB000, 0x08090A, 0x7C7C85])
        XCTAssertEqual([t.signalEdge, t.signalWash], [0.45, 0.10])
        XCTAssertEqual([t.button, t.buttonText, t.buttonLamp, t.danger], [0xE4E4E7, 0x111113, 0xFFB000, 0xFF5F57])
        XCTAssertEqual(Theme.signal.radius, .hud)
        XCTAssertEqual(Theme.signal.radius.frame, 0, "square HUD frames")
        XCTAssertEqual(Theme.signal.radius.panel, 4)
        XCTAssertEqual(Theme.signal.radius.lampRoundness, 0, "square lamps")
        XCTAssertEqual(Theme.signal.brackets, .hud)
        XCTAssertEqual(Theme.signal.brackets.width, 1.5)
        XCTAssertFalse(Theme.signal.brackets.followCorners)
        XCTAssertEqual(Theme.signal.glowStrength, 1)
        XCTAssertFalse(Theme.signal.isLight)
    }

    func testBlushIsLightSofterAndDelicate() {
        let blush = Theme.blush
        XCTAssertTrue(blush.isLight)
        XCTAssertGreaterThan(luminance(blush.tokens.bg), 0.85, "a light canvas")
        XCTAssertLessThan(luminance(blush.tokens.fg), 0.05, "ink type")
        XCTAssertGreaterThan(blush.radius.panel, Theme.signal.radius.panel, "softer corners")
        XCTAssertGreaterThan(blush.radius.frame, 0)
        XCTAssertLessThan(blush.brackets.width, Theme.signal.brackets.width, "delicate brackets")
        XCTAssertTrue(blush.brackets.followCorners)
        XCTAssertNotEqual(blush.tokens.signalInk, blush.tokens.signal, "a deeper rose wherever the rose is text")
        for dark in [Theme.signal, .phosphor, .ice] {
            XCTAssertFalse(dark.isLight)
            XCTAssertLessThan(luminance(dark.tokens.bg), 0.01)
            XCTAssertEqual(dark.radius, .hud, "the Signal composition, recoloured")
        }
    }

    func testTextPassesAAInEveryLook() {
        for theme in Theme.all {
            let t = theme.tokens
            let name = theme.label
            let wash = over(t.signal, t.signalWash, t.bg)
            for (label, ink) in [("fg", t.fg), ("fgMuted", t.fgMuted), ("fgSubtle", t.fgSubtle), ("signalInk", t.signalInk),
                                 ("danger", t.danger)] {
                XCTAssertGreaterThanOrEqual(contrast(ink, t.bg), 4.5, "\(name) \(label) on the canvas")
                XCTAssertGreaterThanOrEqual(contrast(ink, t.bgRaised), 4.5, "\(name) \(label) on a panel")
            }
            XCTAssertGreaterThanOrEqual(contrast(t.fg, wash), 4.5, "\(name) fg on the signal wash")
            XCTAssertGreaterThanOrEqual(contrast(t.fgMuted, wash), 4.5,
                                        "\(name) the chosen plan's units and about $1.67 / month on the wash")
            XCTAssertGreaterThanOrEqual(contrast(t.signalInk, wash), 4.5,
                                        "\(name) lit text on a lit chip or plan, and a fully taken day's number in the log")
            XCTAssertGreaterThanOrEqual(contrast(t.buttonText, t.button), 4.5, "\(name) the primary button")
            XCTAssertGreaterThanOrEqual(contrast(t.buttonText, t.signalInk), 4.5, "\(name) the paywall button once Pro is on")
            XCTAssertGreaterThanOrEqual(contrast(t.onSignal, t.signal), 3, "\(name) the check on a lit disc")
            XCTAssertGreaterThanOrEqual(contrast(t.signal, t.bg), 3, "\(name) a lit segment against the canvas")
            XCTAssertGreaterThan(contrast(t.fgFaint, t.bg), 2, "\(name) dashed rings and index marks still show")
        }
    }

    func testWidgetsStayReadableWhereTheSystemRemovesTheCanvas() {
        // StandBy and CarPlay draw the small widget on black without its canvas. The dark looks need no change; Blush
        // switches to dark-canvas text and keeps its rose.
        let black: UInt32 = 0x000000
        for theme in Theme.all {
            let shown = theme.withoutBackground
            let t = shown.tokens
            let name = theme.label
            XCTAssertFalse(shown.isLight, "\(name) draws light on black")
            XCTAssertEqual(shown.id, theme.id)
            XCTAssertEqual(shown.radius, theme.radius, "\(name) keeps its shapes")
            XCTAssertEqual(t.signal, theme.tokens.signal, "\(name) keeps its signal")
            for (label, ink) in [("fg", t.fg), ("fgMuted", t.fgMuted), ("fgSubtle", t.fgSubtle), ("signalInk", t.signalInk)] {
                XCTAssertGreaterThanOrEqual(contrast(ink, black), 4.5, "\(name) \(label) on black")
            }
            XCTAssertGreaterThanOrEqual(contrast(t.signal, black), 3, "\(name) a lit segment on black")
            XCTAssertGreaterThan(luminance(t.signal), luminance(t.bgInset), "\(name) lit segments outshine unlit ones")
            XCTAssertGreaterThanOrEqual(contrast(t.buttonText, t.button), 4.5, "\(name) TAKE ALL")
            XCTAssertGreaterThanOrEqual(contrast(t.onSignal, t.signal), 3, "\(name) the check on a lit disc")
        }
        XCTAssertEqual(Theme.signal.withoutBackground, Theme.signal, "the dark looks are unchanged")
        XCTAssertNotEqual(Theme.blush.withoutBackground.tokens.fg, Theme.blush.tokens.fg, "Blush's ink would vanish on black")
    }

    // MARK: WCAG 2 contrast

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `top` at `alpha` over `base`, as the screen shows it.
    private func over(_ top: UInt32, _ alpha: Double, _ base: UInt32) -> UInt32 {
        func mix(_ shift: UInt32) -> UInt32 {
            let a = Double((top >> shift) & 0xFF)
            let b = Double((base >> shift) & 0xFF)
            return UInt32((a * alpha + b * (1 - alpha)).rounded()) << shift
        }
        return mix(16) | mix(8) | mix(0)
    }
}
