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

/// Token system shared with badline.ai and lupolabs.ai.
enum Palette {
    static let bg = Color(hex: 0x08090A)
    static let bgRaised = Color(hex: 0x0F1012)
    static let bgInset = Color(hex: 0x16171A)
    static let fg = Color(hex: 0xF4F4F5)
    static let fgMuted = Color(hex: 0xA1A1AA)
    static let fgSubtle = Color(hex: 0x7C7C85)
    static let fgFaint = Color(hex: 0x52525B)
    static let line = Color(hex: 0xFFFFFF, opacity: 0.10)
    static let lineStrong = Color(hex: 0xFFFFFF, opacity: 0.18)
    static let lineDash = Color(hex: 0xA1A1AA, opacity: 0.20)
    static let tick = Color(hex: 0xA1A1AA, opacity: 0.34)
    static let signal = Color(hex: 0xFFB000)
    static let signalEdge = Color(hex: 0xFFB000, opacity: 0.45)
    static let signalWash = Color(hex: 0xFFB000, opacity: 0.10)
    static let danger = Color(hex: 0xFF5F57)
    static let button = Color(hex: 0xE4E4E7)
    static let buttonText = Color(hex: 0x111113)
}

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

extension View {
    /// Mono caps label with HUD letter-spacing (tracking is a fraction of the size, like CSS em).
    func hud(_ size: CGFloat = 11, _ color: Color = Palette.fgSubtle, face: Face = .monoMedium, tracking: CGFloat = 0.14) -> some View {
        self
            .font(.mono(size, face))
            .tracking(size * tracking)
            .foregroundStyle(color)
    }

    /// Same as `hud` but never scales, for widgets and dense readouts.
    func hudFixed(_ size: CGFloat = 11, _ color: Color = Palette.fgSubtle, face: Face = .monoMedium, tracking: CGFloat = 0.14) -> some View {
        self
            .font(.monoFixed(size, face))
            .tracking(size * tracking)
            .foregroundStyle(color)
    }
}

/// Viewfinder corner brackets.
struct CornerBrackets: Shape {
    var length: CGFloat

    var animatableData: CGFloat {
        get { length }
        set { length = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let l = min(length, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))

        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))

        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))

        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
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
    var color: Color = Palette.lineDash
    var body: some View {
        HLine()
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
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

/// The Taken mark: a split capsule, one half lit, one half outlined, set at 45 degrees.
struct CapsuleGlyph: View {
    var fill: Color = Palette.signal
    var stroke: Color = Palette.fgMuted

    var body: some View {
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
