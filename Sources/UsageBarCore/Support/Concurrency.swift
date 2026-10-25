import Foundation

/// Runs blocking work (subprocesses, SQLite, network) off the cooperative pool.
func inBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await Task.detached(priority: .userInitiated, operation: work).value
}
