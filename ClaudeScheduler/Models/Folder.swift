import Foundation
import SwiftUI

struct Folder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String  // hex color

    init(id: UUID = UUID(), name: String, color: String = "#007AFF") {
        self.id = id
        self.name = name
        self.color = color
    }

    static let defaultFolder = Folder(name: "Default", color: "#8E8E93")

    /// hex 문자열을 SwiftUI Color로 변환
    var swiftUIColor: Color {
        Color(hex: color) ?? .gray
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let length = hexSanitized.count

        switch length {
        case 6:
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        case 8:
            self.init(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }

    /// Color를 hex 문자열로 변환 (sRGB 색공간으로 변환 후)
    func toHex() -> String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }

        let r = srgb.redComponent
        let g = srgb.greenComponent
        let b = srgb.blueComponent

        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Preset Colors
extension Folder {
    static let presetColors: [(name: String, hex: String)] = [
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Pink", "#FF2D55"),
        ("Red", "#FF3B30"),
        ("Orange", "#FF9500"),
        ("Yellow", "#FFCC00"),
        ("Green", "#34C759"),
        ("Teal", "#5AC8FA"),
        ("Gray", "#8E8E93")
    ]
}
