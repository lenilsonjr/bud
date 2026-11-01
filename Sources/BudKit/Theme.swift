#if canImport(SwiftUI)
import SwiftUI

enum Theme {
    static let background = Color(red: 0.07, green: 0.10, blue: 0.08)
    static let card = Color.white.opacity(0.05)
    static let stroke = Color.white.opacity(0.12)
    static let accent = Color(red: 0.55, green: 0.80, blue: 0.55)

    static func light(for role: CardRole) -> Double {
        switch role {
        case .center, .ring: return 1
        case .deep: return 0.85
        case .ghost: return 0.7
        case .kin: return 0.55
        }
    }
}
#endif
