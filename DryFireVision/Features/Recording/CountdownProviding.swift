import Foundation

public protocol CountdownProviding: Sendable {
    func countdown(from seconds: Int) -> AsyncStream<Int>
}

public struct LiveCountdownProvider: CountdownProviding {
    public init() {}

    public func countdown(from seconds: Int) -> AsyncStream<Int> {
        AsyncStream { continuation in
            let task = Task {
                for remaining in stride(from: seconds, through: 1, by: -1) {
                    continuation.yield(remaining)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
