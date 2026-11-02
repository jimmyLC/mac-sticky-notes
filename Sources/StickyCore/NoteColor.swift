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

    /// The colour to draw in dark mode: pastel notes become deep, saturated versions with light
    /// text, while colours that are already dark are left alone.
    public func displayColor(dark: Bool) -> NoteColor {
        guard dark else { return self }
        let c = components
        let maximum = max(c.red, c.green, c.blue)
        let minimum = min(c.red, c.green, c.blue)
        guard maximum > 0.45 else { return self }

        let delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == c.red { hue = ((c.green - c.blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == c.green { hue = (c.blue - c.red) / delta + 2 }
            else { hue = (c.red - c.green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maximum == 0 ? 0 : delta / maximum
        let newSaturation = min(1, saturation * 1.7 + 0.05)
        let newValue = 0.38

        let chroma = newValue * newSaturation
        let x = chroma * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = newValue - chroma
        let (r, g, b): (Double, Double, Double)
        switch Int(hue * 6) % 6 {
        case 0: (r, g, b) = (chroma, x, 0)
        case 1: (r, g, b) = (x, chroma, 0)
        case 2: (r, g, b) = (0, chroma, x)
        case 3: (r, g, b) = (0, x, chroma)
        case 4: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        return NoteColor(red: r + m, green: g + m, blue: b + m)
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
