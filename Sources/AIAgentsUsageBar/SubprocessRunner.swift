import Foundation

enum SubprocessRunner {
    /// Runs an executable with arguments, returning standard output as string.
    /// Runs with a watchdog timeout and reads the pipe concurrently to prevent buffer deadlocks.
    static func run(executablePath: String, arguments: [String], timeoutSeconds: TimeInterval = 15) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        final class OutputBox: @unchecked Sendable {
            var data = Data()
        }
        let box = OutputBox()
        let group = DispatchGroup()
        group.enter()

        // Read pipe concurrently to prevent process blocking on a full pipe buffer (>64KB)
        DispatchQueue.global(qos: .userInitiated).async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        // Watchdog timer to kill hanging CLI subprocesses
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler {
            if process.isRunning {
                process.terminate()
            }
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        _ = group.wait(timeout: .now() + 1.0)
        return String(data: box.data, encoding: .utf8)
    }
}
