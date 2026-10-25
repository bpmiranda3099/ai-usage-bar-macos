import Foundation

enum SubprocessRunner {
    /// Empty, private directory the tools run in. Running from $HOME would let a stray
    /// project config file there (hooks, MCP servers, plugins) execute on every refresh.
    static let workingDirectory: URL = {
        let fallback = FileManager.default.temporaryDirectory
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return fallback }
        let directory = support.appendingPathComponent("AIAgentsUsageBar/workdir", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return directory
        } catch {
            return fallback
        }
    }()

    /// Runs an executable with fixed arguments (no shell) and returns standard output.
    /// Only absolute paths are accepted; stdin and stderr are closed off; a watchdog sends
    /// SIGTERM after `timeoutSeconds` and SIGKILL two seconds later; output beyond
    /// `maxOutputBytes` aborts the run. Returns nil on any failure.
    static func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval = 15,
        maxOutputBytes: Int = 8_000_000
    ) -> String? {
        guard executablePath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executablePath) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        final class OutputBox: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()
            private var overflowed = false

            /// Returns false once the output is larger than allowed.
            func append(_ chunk: Data, limit: Int) -> Bool {
                lock.withLock {
                    data.append(chunk)
                    if data.count > limit { overflowed = true }
                    return !overflowed
                }
            }

            func result() -> String? {
                lock.withLock { overflowed ? nil : String(data: data, encoding: .utf8) }
            }
        }
        let box = OutputBox()
        let group = DispatchGroup()
        group.enter()

        // Read the pipe concurrently so a full buffer can't block the process, and stop
        // collecting (and kill the process) once the output is larger than expected.
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = pipe.fileHandleForReading
            while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
                if !box.append(chunk, limit: maxOutputBytes) {
                    if process.isRunning { process.terminate() }
                    break
                }
            }
            group.leave()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let pid = process.processIdentifier
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler {
            guard process.isRunning else { return }
            process.terminate()
            // A tool that ignores SIGTERM (stuck on a prompt) must not hang the app.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        // If a child still holds the pipe open, treat the output as incomplete.
        guard group.wait(timeout: .now() + 1.0) == .success else { return nil }
        return box.result()
    }
}
