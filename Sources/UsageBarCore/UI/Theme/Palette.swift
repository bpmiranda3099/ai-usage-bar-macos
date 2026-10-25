import SwiftUI

extension Tint {
    var color: Color {
        switch self {
        case .claude: Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757
        case .antigravity: Color(red: 0.157, green: 0.471, blue: 0.941) // #2878F0
        case .opencode: .black
        }
    }
}
