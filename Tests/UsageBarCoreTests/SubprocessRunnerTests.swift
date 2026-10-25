import Foundation
import Testing
@testable import UsageBarCore

struct SubprocessRunnerTests {
    @Test func runsAnAbsolutePathWithoutAShell() {
        // A shell would expand "$HOME"; with fixed argv it stays literal.
        #expect(SubprocessRunner.run(executablePath: "/bin/echo", arguments: ["$HOME"]) == "$HOME\n")
    }

    @Test func relativePathsAreRefused() {
        #expect(SubprocessRunner.run(executablePath: "echo", arguments: ["hi"]) == nil)
    }

    @Test func missingExecutablesAreNil() {
        #expect(SubprocessRunner.run(executablePath: "/nonexistent/tool", arguments: []) == nil)
    }

    @Test func aHungProcessIsKilledAtTheTimeout() {
        let start = Date()
        _ = SubprocessRunner.run(executablePath: "/bin/sleep", arguments: ["30"], timeoutSeconds: 0.5)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func tooMuchOutputAbortsTheRun() {
        let start = Date()
        #expect(SubprocessRunner.run(executablePath: "/usr/bin/yes", arguments: [], timeoutSeconds: 10, maxOutputBytes: 1_000) == nil)
        #expect(Date().timeIntervalSince(start) < 8)
    }
}

extension SubprocessRunnerTests {
    @Test func toolsRunInThePrivateWorkingDirectoryNotHome() throws {
        let output = try #require(SubprocessRunner.run(executablePath: "/bin/pwd", arguments: []))
        let reported = URL(fileURLWithPath: output.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath().path
        #expect(reported == SubprocessRunner.workingDirectory.resolvingSymlinksInPath().path)
        #expect(reported != URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path)
    }

    @Test func standardInputIsClosedSoReadersDoNotWait() {
        let start = Date()
        _ = SubprocessRunner.run(executablePath: "/bin/cat", arguments: [], timeoutSeconds: 10)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func aProcessIgnoringSIGTERMIsStillStopped() {
        let start = Date()
        _ = SubprocessRunner.run(executablePath: "/bin/sh", arguments: ["-c", "trap '' TERM; sleep 8"], timeoutSeconds: 0.5)
        #expect(Date().timeIntervalSince(start) < 7)
    }
}
