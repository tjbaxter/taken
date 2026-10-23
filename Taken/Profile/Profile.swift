import SwiftUI
import UIKit

/// Profile (REDESIGN.md): a name and a photo, both optional, kept on this iPhone in the App Group next to the log.
/// Nothing is asked at first launch; the avatar on every tab opens it.
struct Profile: Codable, Hashable, Sendable {
    var name: String

    init(name: String = "") {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case name }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }

    /// At most this many characters.
    static let maxNameLength = 40

    /// The name as typed, trimmed and capped.
    static func clean(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(words.prefix(maxNameLength))
    }

    /// "TB" for Thomas Baxter, "T" for Tom. Nil without a name.
    var initials: String? {
        let words = name.split(whereSeparator: { $0.isWhitespace }).filter { $0.first?.isLetter == true }
        guard let first = words.first?.first else { return nil }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }
}

/// `profile.json` and `profile-photo.jpg` in the App Group. Only the app reads them.
final class ProfileStore: Sendable {
    static let shared = ProfileStore(directory: TakenStore.defaultFileURL().deletingLastPathComponent())

    let fileURL: URL
    let photoURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("profile.json")
        photoURL = directory.appendingPathComponent("profile-photo.jpg")
    }

    func load() -> Profile {
        guard let data = try? Data(contentsOf: fileURL),
              let profile = try? JSONDecoder().decode(Profile.self, from: data) else { return Profile() }
        return profile
    }

    func save(_ profile: Profile) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(profile).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func loadPhoto() -> Data? {
        try? Data(contentsOf: photoURL)
    }

    func savePhoto(_ jpeg: Data) throws {
        try FileManager.default.createDirectory(at: photoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: photoURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: photoURL)
    }

    /// Erase all data: the name and the photo go.
    func erase() {
        try? FileManager.default.removeItem(at: fileURL)
        removePhoto()
    }
}

/// A chosen photo as Taken keeps it: the centre square, at most 600 pixels, as JPEG. Shown in a circle.
enum ProfilePhoto {
    static let side: CGFloat = 600

    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let target = min(side, min(image.size.width, image.size.height) * image.scale)
        let scale = target / min(image.size.width, image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(x: (target - drawn.width) / 2, y: (target - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
        return square.jpegData(compressionQuality: 0.85)
    }
}

/// The photo in a circle, or the initials, or a person when there is neither.
struct ProfileAvatar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let size: CGFloat

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        ZStack {
            if let photo = model.profilePhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                theme.bgInset
                if let initials = model.profile.initials {
                    Text(initials)
                        .font(.sans(size * 0.38, .sansSemibold, relativeTo: .body))
                        .foregroundStyle(theme.fg)
                        .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42, weight: .regular))
                        .foregroundStyle(theme.fgSubtle)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.lineStrong, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Top right on every tab: opens Profile, where every setting lives.
struct ProfileButton: View {
    @Environment(AppModel.self) private var model

    init() {}

    var body: some View {
        Button {
            model.sheet = .settings
        } label: {
            ProfileAvatar(size: 36)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(model.profile.name.isEmpty ? "Profile and settings" : "\(model.profile.name), profile and settings")
    }
}

/// The top of each tab: a large title, a line under it, and the profile avatar, with an optional accessory left of the
/// avatar (the Weight tab's More button, SPEC 3.12). Without one it lays out exactly as it always has.
struct TabHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String?
    let accessory: AnyView?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = nil
    }

    init<Accessory: View>(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.sans(34, .sansSemibold, relativeTo: .largeTitle))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.sans(15, .sans, relativeTo: .subheadline))
                        .foregroundStyle(theme.fgSubtle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let accessory {
                accessory
                    .padding(.top, 2)
                    .padding(.trailing, -8)
            }
            ProfileButton()
                .padding(.top, 2)
        }
        .padding(.top, 8)
    }
}
