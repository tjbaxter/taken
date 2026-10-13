import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Looks

/// The four looks, chosen in Settings > LOOK. The raw value is what taken.json stores (`StackSettings.theme`), so a
/// case is never renamed. A look is named for its colour, never for who might pick it.
enum ThemeID: String, CaseIterable, Codable, Identifiable, Sendable {
    case signal
    case blush
    case phosphor
    case ice

    var id: String { rawValue }

    /// "BLUSH", the mono label.
    var label: String { rawValue.uppercased() }

    /// "Blush", for VoiceOver.
    var title: String { rawValue.capitalized }

    /// The app icon that goes with the look: nil is the primary icon (Signal); the others are alternate icon sets in
    /// the asset catalog, listed in ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES (project.yml).
    var alternateIconName: String? {
        self == .signal ? nil : "AppIcon-\(title)"
    }

    /// A stored or typed name. Anything unknown (a look from a later version, a typo) is Signal.
    init(stored: String?) {
        self = stored.flatMap { ThemeID(rawValue: $0.lowercased()) } ?? .signal
    }

    /// Never fails on a name it does not know, so one unknown look can never make taken.json unreadable.
    init(from decoder: any Decoder) throws {
        let value = try? decoder.singleValueContainer().decode(String.self)
        self.init(stored: value)
    }

    var theme: Theme { Theme.look(self) }
}

/// A look as numbers: sRGB hex values, and opacities over a base colour for the lines and the signal's edge and wash.
/// Tests check every text pair against WCAG AA from these, and brand/icon.py mirrors them for the app icons.
struct ThemeTokens: Hashable, Sendable {
    /// The canvas.
    var bg: UInt32
    /// Panels, cards, toasts.
    var bgRaised: UInt32
    /// Code tags, unlit segments, a pressed row.
    var bgInset: UInt32
    var fg: UInt32
    var fgMuted: UInt32
    /// Labels and secondary readouts. AA on the canvas, like every text colour.
    var fgSubtle: UInt32
    /// Index marks, dashed rings, the footer: decoration more than text.
    var fgFaint: UInt32
    /// Hairlines are this colour at `line` and `lineStrong` opacity.
    var lineBase: UInt32
    var line: Double
    var lineStrong: Double
    /// Dashed rules and ruler ticks are this colour at `lineDash` and `tick` opacity.
    var dashBase: UInt32
    var lineDash: Double
    var tick: Double
    /// HUD brackets at rest.
    var bracket: UInt32
    /// Lit = taken: discs, segments, lamps, the glyph's lit half.
    var signal: UInt32
    /// The signal as text and thin marks, AA on the canvas, raised surfaces and the wash.
    var signalInk: UInt32
    /// Opacities of the signal for lit edges and washes.
    var signalEdge: Double
    var signalWash: Double
    /// Marks drawn on a signal fill: the check on a lit disc.
    var onSignal: UInt32
    /// The solid primary button and its label.
    var button: UInt32
    var buttonText: UInt32
    /// Destructive confirms only.
    var danger: UInt32
}

/// Corner radii, from the HUD frames down to the lamps.
struct ThemeRadius: Hashable, Sendable {
    /// Bracketed frames: the status panel, the empty state, the paywall header.
    var frame: CGFloat
    /// Panels, cards, buttons, toasts.
    var panel: CGFloat
    /// Chips, code tags, fields, segmented controls, history cells.
    var control: CGFloat
    /// Tiny marks: the plan radio, the offer tag, the PRO glyph.
    var mark: CGFloat
    /// Progress bar segments.
    var segment: CGFloat
    /// Lamps and small lit squares: 0 is square, 1 is round.
    var lampRoundness: CGFloat

    /// Signal, Phosphor and Ice: square-ish, 4 pt and under, square frames.
    static let hud = ThemeRadius(frame: 0, panel: 4, control: 3, mark: 2, segment: 0, lampRoundness: 0)
    /// Blush: softer corners everywhere, round lamps.
    static let soft = ThemeRadius(frame: 14, panel: 12, control: 8, mark: 4, segment: 3, lampRoundness: 1)
}

/// The viewfinder corner brackets on the HUD frames.
struct ThemeBrackets: Hashable, Sendable {
    /// Stroke width.
    var width: CGFloat
    /// Arm length relative to Signal's.
    var scale: CGFloat
    /// Square viewfinder corners, or arcs that follow a rounded frame with round ends.
    var followCorners: Bool

    var lineCap: CGLineCap { followCorners ? .round : .square }

    var style: StrokeStyle { StrokeStyle(lineWidth: width, lineCap: lineCap) }

    static let hud = ThemeBrackets(width: 1.5, scale: 1, followCorners: false)
    static let delicate = ThemeBrackets(width: 1, scale: 0.8, followCorners: true)
}

/// Everything a view or widget draws with: the colours, the radius scale, the brackets and the glow. Injected through
/// the environment (`@Environment(\.theme)`): the app sets it from the chosen look, a widget from the look in the App
/// Group store. Views and widgets never name a colour of their own.
struct Theme: Hashable, Sendable {
    let id: ThemeID
    /// Blush is light; Signal, Phosphor and Ice are dark.
    let isLight: Bool
    let tokens: ThemeTokens
    let radius: ThemeRadius
    let brackets: ThemeBrackets
    /// The signal glow on lit elements: 1 is Signal's phosphor bloom, lower is softer.
    let glowStrength: Double

    let bg: Color
    let bgRaised: Color
    let bgInset: Color
    let fg: Color
    let fgMuted: Color
    let fgSubtle: Color
    let fgFaint: Color
    let line: Color
    let lineStrong: Color
    let lineDash: Color
    let tick: Color
    let bracket: Color
    let signal: Color
    let signalInk: Color
    let signalEdge: Color
    let signalWash: Color
    let onSignal: Color
    let button: Color
    let buttonText: Color
    let danger: Color

    init(id: ThemeID, isLight: Bool, tokens: ThemeTokens, radius: ThemeRadius, brackets: ThemeBrackets,
         glowStrength: Double) {
        self.id = id
        self.isLight = isLight
        self.tokens = tokens
        self.radius = radius
        self.brackets = brackets
        self.glowStrength = glowStrength
        bg = Color(hex: tokens.bg)
        bgRaised = Color(hex: tokens.bgRaised)
        bgInset = Color(hex: tokens.bgInset)
        fg = Color(hex: tokens.fg)
        fgMuted = Color(hex: tokens.fgMuted)
        fgSubtle = Color(hex: tokens.fgSubtle)
        fgFaint = Color(hex: tokens.fgFaint)
        line = Color(hex: tokens.lineBase, opacity: tokens.line)
        lineStrong = Color(hex: tokens.lineBase, opacity: tokens.lineStrong)
        lineDash = Color(hex: tokens.dashBase, opacity: tokens.lineDash)
        tick = Color(hex: tokens.dashBase, opacity: tokens.tick)
        bracket = Color(hex: tokens.bracket)
        signal = Color(hex: tokens.signal)
        signalInk = Color(hex: tokens.signalInk)
        signalEdge = Color(hex: tokens.signal, opacity: tokens.signalEdge)
        signalWash = Color(hex: tokens.signal, opacity: tokens.signalWash)
        onSignal = Color(hex: tokens.onSignal)
        button = Color(hex: tokens.button)
        buttonText = Color(hex: tokens.buttonText)
        danger = Color(hex: tokens.danger)
    }

    /// "SIGNAL"
    var label: String { id.label }

    /// The status bar, sheets, menus, pickers and system controls follow it (`preferredColorScheme`).
    var scheme: ColorScheme { isLight ? .light : .dark }

    /// The signal as a glow: `opacity` is Signal's, scaled for the look.
    func glow(_ opacity: Double) -> Color {
        signal.opacity(opacity * glowStrength)
    }

    /// Corner radius for brackets around a shape with corner radius `shape`: square viewfinder corners in Signal,
    /// Phosphor and Ice; in Blush they follow the curve.
    func bracketRadius(_ shape: CGFloat) -> CGFloat {
        brackets.followCorners ? shape : 0
    }

    /// Corner radius of a lamp (a small lit square) of `size`.
    func lampRadius(_ size: CGFloat) -> CGFloat {
        size / 2 * radius.lampRoundness
    }

    // Tinted and clear Home Screens draw every widget colour white and keep only its alpha. These are those alphas,
    // the same in every look.
    var accentedFaint: Color { Color.white.opacity(0.2) }
    var accentedFill: Color { Color.white.opacity(0.12) }
    var accentedStroke: Color { Color.white.opacity(0.6) }

    // The widget gallery's stand-in for the Lock Screen, where the system draws accessory widgets in white.
    var lockScreenPlate: Color { isLight ? Color(hex: tokens.fg, opacity: 0.9) : Color.white.opacity(0.06) }
    var lockScreenInk: Color { Color.white }

    /// LaunchBackground in the asset catalog. A light look fades in from it, so a cold launch never cuts to white.
    static let launchCanvas = Color(hex: 0x08090A)
}

extension Theme {
    /// Amber phosphor on black: the badline.ai and lupolabs.ai token system, Taken's look since 1.0. The default.
    static let signal = Theme(
        id: .signal, isLight: false,
        tokens: ThemeTokens(
            bg: 0x08090A, bgRaised: 0x0F1012, bgInset: 0x16171A,
            fg: 0xF4F4F5, fgMuted: 0xA1A1AA, fgSubtle: 0x7C7C85, fgFaint: 0x52525B,
            lineBase: 0xFFFFFF, line: 0.10, lineStrong: 0.18,
            dashBase: 0xA1A1AA, lineDash: 0.20, tick: 0.34,
            bracket: 0x7C7C85,
            signal: 0xFFB000, signalInk: 0xFFB000, signalEdge: 0.45, signalWash: 0.10, onSignal: 0x08090A,
            button: 0xE4E4E7, buttonText: 0x111113, danger: 0xFF5F57),
        radius: .hud, brackets: .hud, glowStrength: 1)

    /// Light: a warm off-white canvas, ink type, a muted rose for what is taken (a deeper rose wherever it is text),
    /// warm grey hairlines, softer corners and delicate brackets.
    static let blush = Theme(
        id: .blush, isLight: true,
        tokens: ThemeTokens(
            bg: 0xFBF6F3, bgRaised: 0xFFFDFB, bgInset: 0xF3EBE7,
            fg: 0x2A2224, fgMuted: 0x5F5357, fgSubtle: 0x776A6E, fgFaint: 0xA5979B,
            lineBase: 0x2A2224, line: 0.10, lineStrong: 0.18,
            dashBase: 0x776A6E, lineDash: 0.30, tick: 0.42,
            bracket: 0xAEA1A5,
            signal: 0xD9667F, signalInk: 0xA8425C, signalEdge: 0.50, signalWash: 0.10, onSignal: 0xFFFFFF,
            button: 0x2A2224, buttonText: 0xFBF6F3, danger: 0xC0392B),
        radius: .soft, brackets: .delicate, glowStrength: 0.35)

    /// Green phosphor on a green-black canvas.
    static let phosphor = Theme(
        id: .phosphor, isLight: false,
        tokens: ThemeTokens(
            bg: 0x060908, bgRaised: 0x0C110E, bgInset: 0x131915,
            fg: 0xEFF5F1, fgMuted: 0x9EAAA3, fgSubtle: 0x78847D, fgFaint: 0x4E5852,
            lineBase: 0xFFFFFF, line: 0.10, lineStrong: 0.18,
            dashBase: 0x9EAAA3, lineDash: 0.20, tick: 0.34,
            bracket: 0x78847D,
            signal: 0x3DFF8A, signalInk: 0x3DFF8A, signalEdge: 0.45, signalWash: 0.10, onSignal: 0x060908,
            button: 0xE2EBE5, buttonText: 0x0C110E, danger: 0xFF5F57),
        radius: .hud, brackets: .hud, glowStrength: 0.85)

    /// LUPO's cyan on a blue-black canvas.
    static let ice = Theme(
        id: .ice, isLight: false,
        tokens: ThemeTokens(
            bg: 0x07090C, bgRaised: 0x0D1015, bgInset: 0x14181E,
            fg: 0xF0F3F7, fgMuted: 0xA0A9B4, fgSubtle: 0x7A838E, fgFaint: 0x4F5661,
            lineBase: 0xFFFFFF, line: 0.10, lineStrong: 0.18,
            dashBase: 0xA0A9B4, lineDash: 0.20, tick: 0.34,
            bracket: 0x7A838E,
            signal: 0x8FD3E8, signalInk: 0x8FD3E8, signalEdge: 0.45, signalWash: 0.10, onSignal: 0x07090C,
            button: 0xE3E9F0, buttonText: 0x0D1015, danger: 0xFF5F57),
        radius: .hud, brackets: .hud, glowStrength: 1)

    /// Settings order.
    static let all: [Theme] = ThemeID.allCases.map { Theme.look($0) }

    static func look(_ id: ThemeID) -> Theme {
        switch id {
        case .signal: return .signal
        case .blush: return .blush
        case .phosphor: return .phosphor
        case .ice: return .ice
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.signal
}

extension EnvironmentValues {
    /// The look every view and widget draws with.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Type

/// Bundled Geist faces (SIL OFL). PostScript names.
enum Face: String, Sendable {
    case sans = "Geist-Regular"
    case sansMedium = "Geist-Medium"
    case sansSemibold = "Geist-SemiBold"
    case mono = "GeistMono-Regular"
    case monoMedium = "GeistMono-Medium"
    case monoSemibold = "GeistMono-SemiBold"
}

extension Font {
    /// Geist, scales with Dynamic Type.
    static func sans(_ size: CGFloat, _ face: Face = .sans, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(face.rawValue, size: size, relativeTo: style)
    }

    /// Geist Mono, scales with Dynamic Type.
    static func mono(_ size: CGFloat, _ face: Face = .monoMedium, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom(face.rawValue, size: size, relativeTo: style)
    }

    /// Geist Mono at a fixed size, for big numerals and tight HUD readouts.
    static func monoFixed(_ size: CGFloat, _ face: Face = .monoMedium) -> Font {
        .custom(face.rawValue, fixedSize: size)
    }
}

/// Mono caps with HUD letter-spacing; without a colour it is the look's subtle ink.
private struct HUDLabel: ViewModifier {
    @Environment(\.theme) private var theme
    let size: CGFloat
    let color: Color?
    let face: Face
    let tracking: CGFloat
    let fixed: Bool

    init(size: CGFloat, color: Color?, face: Face, tracking: CGFloat, fixed: Bool) {
        self.size = size
        self.color = color
        self.face = face
        self.tracking = tracking
        self.fixed = fixed
    }

    func body(content: Content) -> some View {
        content
            .font(fixed ? Font.monoFixed(size, face) : Font.mono(size, face))
            .tracking(size * tracking)
            .foregroundStyle(color ?? theme.fgSubtle)
    }
}

extension View {
    /// Mono caps label with HUD letter-spacing (tracking is a fraction of the size, like CSS em).
    func hud(_ size: CGFloat = 11, _ color: Color? = nil, face: Face = .monoMedium, tracking: CGFloat = 0.14) -> some View {
        modifier(HUDLabel(size: size, color: color, face: face, tracking: tracking, fixed: false))
    }

    /// Same as `hud` but never scales, for widgets and dense readouts.
    func hudFixed(_ size: CGFloat = 11, _ color: Color? = nil, face: Face = .monoMedium, tracking: CGFloat = 0.14) -> some View {
        modifier(HUDLabel(size: size, color: color, face: face, tracking: tracking, fixed: true))
    }
}

// MARK: - Shapes

/// Viewfinder corner brackets. With a `radius` each corner is an arc that follows a rounded frame (Blush); at 0 they
/// are square corners.
struct CornerBrackets: Shape {
    var length: CGFloat
    var radius: CGFloat = 0

    var animatableData: CGFloat {
        get { length }
        set { length = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        let l = max(0, min(length, rect.width / 2 - r, rect.height / 2 - r))
        var p = Path()

        // Arm, then the corner (a point, or an arc from `start` to `end` around `vertex`), then the other arm.
        func corner(_ start: CGPoint, _ vertex: CGPoint, _ end: CGPoint, _ armStart: CGPoint, _ armEnd: CGPoint) {
            p.move(to: armStart)
            if r > 0 {
                if l > 0 { p.addLine(to: start) }
                p.addArc(tangent1End: vertex, tangent2End: end, radius: r)
            } else {
                p.addLine(to: vertex)
            }
            if l > 0 || r == 0 { p.addLine(to: armEnd) }
        }

        // Top left, top right, bottom right, bottom left: arm, curve (or corner), arm.
        corner(CGPoint(x: rect.minX, y: rect.minY + r), CGPoint(x: rect.minX, y: rect.minY),
               CGPoint(x: rect.minX + r, y: rect.minY),
               CGPoint(x: rect.minX, y: rect.minY + r + l), CGPoint(x: rect.minX + r + l, y: rect.minY))
        corner(CGPoint(x: rect.maxX - r, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
               CGPoint(x: rect.maxX, y: rect.minY + r),
               CGPoint(x: rect.maxX - r - l, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + r + l))
        corner(CGPoint(x: rect.maxX, y: rect.maxY - r), CGPoint(x: rect.maxX, y: rect.maxY),
               CGPoint(x: rect.maxX - r, y: rect.maxY),
               CGPoint(x: rect.maxX, y: rect.maxY - r - l), CGPoint(x: rect.maxX - r - l, y: rect.maxY))
        corner(CGPoint(x: rect.minX + r, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
               CGPoint(x: rect.minX, y: rect.maxY - r),
               CGPoint(x: rect.minX + r + l, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY - r - l))
        return p
    }
}

/// A horizontal line, for dashed separators.
struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

struct DashedRule: View {
    @Environment(\.theme) private var theme
    var color: Color?

    init(color: Color? = nil) {
        self.color = color
    }

    var body: some View {
        HLine()
            .stroke(color ?? theme.lineDash, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
    }
}

/// A square check mark, mil-spec rather than rounded.
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.53))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.74))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.30))
        return p
    }
}

/// A small lit square (round in Blush), the HUD's status light.
struct LampShape: Shape {
    var roundness: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 * max(0, min(roundness, 1))
        return r > 0 ? Path(roundedRect: rect, cornerRadius: r) : Path(rect)
    }
}

/// The Taken mark: a split capsule, one half lit, one half outlined, set at 45 degrees.
struct CapsuleGlyph: View {
    @Environment(\.theme) private var theme
    var fill: Color?
    var stroke: Color?

    init(fill: Color? = nil, stroke: Color? = nil) {
        self.fill = fill
        self.stroke = stroke
    }

    var body: some View {
        let fill = self.fill ?? theme.signal
        let stroke = self.stroke ?? theme.fgMuted
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let width = side * 0.98
            let height = side * 0.44
            let lineWidth = max(1, side * 0.075)
            let gap = max(1, side * 0.05)
            let half = (width - gap) / 2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(fill)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: half)
                    }
                ZStack(alignment: .leading) {
                    Capsule().strokeBorder(stroke, lineWidth: lineWidth)
                    Rectangle()
                        .fill(stroke)
                        .frame(width: lineWidth)
                        .offset(x: half + gap)
                }
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: half)
                }
            }
            .frame(width: width, height: height)
            .rotationEffect(.degrees(-45))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}
