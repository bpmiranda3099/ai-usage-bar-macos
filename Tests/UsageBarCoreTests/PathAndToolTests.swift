import Foundation
import Testing
@testable import UsageBarCore

struct PathAndToolTests {
    @Test func opencodePathsAreParsedByName() {
        let output = """
        home       /Users/me
        data       /Users/me/.local/share/opencode
        cache      /Users/me/.cache/opencode
        db         /Users/me/.local/share/opencode/opencode.db
        """
        let paths = OpenCodePaths.parse(output)
        #expect(paths["db"] == "/Users/me/.local/share/opencode/opencode.db")
        #expect(paths["cache"] == "/Users/me/.cache/opencode")
        #expect(paths["missing"] == nil)
    }

    @Test func pathsWithSpacesKeepTheirTail() {
        #expect(OpenCodePaths.parse("db   /Users/me/My Files/opencode.db")["db"] == "/Users/me/My Files/opencode.db")
    }

    @Test func firstExecutableSkipsMissingAndNonExecutableFiles() throws {
        let directory = NSTemporaryDirectory() + "usagebar-tools-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let plain = directory + "/plain"
        let runnable = directory + "/runnable"
        try "x".write(toFile: plain, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(toFile: runnable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnable)

        #expect(ExecutableLocator.firstExecutable(in: [directory + "/absent", plain, runnable]) == runnable)
        #expect(ExecutableLocator.firstExecutable(in: [directory + "/absent", plain]) == nil)
    }
}
