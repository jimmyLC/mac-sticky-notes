import Foundation

/// A note background colour stored as `#RRGGBB`. The four presets match the palette of the
/// reference app; any other colour comes from the system colour panel.
public struct NoteColor: Hashable, Codable, Sendable {
    public let hex: String

    public init(hex: String) {
        self.hex = NoteColor.normalize(hex) ?? "#FFF299"
    }

    public init(red: Double, green: Double, blue: Double) {
        func byte(_ value: Double) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        self.hex = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    public var components: (red: Double, green: Double, blue: Double) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFF299
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// Dark backgrounds get white text so custom colours stay readable.
    public var prefersLightText: Bool {
        let c = components
        return 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue < 0.5
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(hex: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + text.uppercased()
    }

    public static let yellow = NoteColor(hex: "#FFF299")
    public static let pink = NoteColor(hex: "#FFD9E6")
    public static let blue = NoteColor(hex: "#D9EBFF")
    public static let green = NoteColor(hex: "#D9F7D9")

    public static let presets: [NoteColor] = [.yellow, .pink, .blue, .green]
    public static let `default` = NoteColor.yellow
}
