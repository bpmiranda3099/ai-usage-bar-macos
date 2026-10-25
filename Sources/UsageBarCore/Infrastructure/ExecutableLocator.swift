import Foundation

/// The command line tools the app shells out to, with the absolute paths to try.
/// The LaunchAgent has a minimal PATH, so tools are never looked up by name.
enum Tool {
    case opencode, agy, claude, gcloud

    private var candidates: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .opencode:
            return ["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode", "\(home)/.opencode/bin/opencode", "\(home)/.local/bin/opencode"]
        case .agy:
            return ["\(home)/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
        case .claude:
            return ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.local/bin/claude"]
        case .gcloud:
            return ["/opt/homebrew/bin/gcloud", "/usr/local/bin/gcloud", "\(home)/google-cloud-sdk/bin/gcloud"]
        }
    }

    /// First candidate that exists and is executable, or nil if the tool isn't installed.
    var path: String? {
        ExecutableLocator.firstExecutable(in: candidates)
    }

    /// Runs the tool with fixed arguments (no shell) and returns its standard output.
    func run(_ arguments: [String]) -> String? {
        path.flatMap { SubprocessRunner.run(executablePath: $0, arguments: arguments) }
    }
}

enum ExecutableLocator {
    static func firstExecutable(in candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
