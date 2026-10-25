import Foundation

/// The providers shown in the panel, in display order.
enum ProviderRegistry {
    static let all: [any UsageProvider] = [
        AntigravityProvider(),
        ClaudeCodeProvider(),
        OpenCodeProvider(),
    ]
}
