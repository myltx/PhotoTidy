import SwiftUI

extension Color {
    init(hex: String) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let r, g, b: UInt64
        switch sanitized.count {
        case 6:
            r = (int >> 16) & 0xFF
            g = (int >> 8) & 0xFF
            b = int & 0xFF
        default:
            r = 255
            g = 255
            b = 255
        }
        self.init(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }
}

extension ThumbnailPalette {
    var gradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color(hex: startHex), Color(hex: endHex)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
