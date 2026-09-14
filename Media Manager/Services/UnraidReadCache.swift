import Foundation

nonisolated struct UnraidConnection: Hashable, Sendable {
    let url: URL
    let apiKey: String
}

/// Independent clocks and failures prevent one resolver from holding the whole screen hostage.
actor UnraidReadCache {
    struct Payload: Sendable { let data: Data; let updatedAt: Date }
    private struct Flight { let token: UUID; let task: Task<Payload, Error> }
    private struct Failure { let error: Error; let count: Int; let retryAt: Date }
    private var connection: UnraidConnection?
    private var values: [String: Payload] = [:]
    private var flights: [String: Flight] = [:]
    private var failures: [String: Failure] = [:]
    private var serverCooldown: Failure?

    func task(key: String, connection: UnraidConnection, ttl: TimeInterval, force: Bool, now: Date,
              clock: @Sendable @escaping () async -> Date = { Date() },
              operation: @Sendable @escaping () async throws -> Data) -> Task<Payload, Error> {
        if self.connection != connection {
            invalidate()
            self.connection = connection
            serverCooldown = nil
        }
        if let flight = flights[key] { return flight.task }
        if let failure = failures[key], now < failure.retryAt,
           !force || Self.serverDirected(failure.error) {
            return Task { throw failure.error }
        }
        if !force, let value = values[key], now.timeIntervalSince(value.updatedAt) < ttl {
            return Task { value }
        }
        if let cooldown = serverCooldown, now < cooldown.retryAt {
            return Task { throw cooldown.error }
        }
        let token = UUID()
        let task = Task<Payload, Error> {
            do {
                let data = try await operation()
                try Task.checkCancellation()
                let result = Payload(data: data, updatedAt: await clock())
                try Task.checkCancellation()
                if flights[key]?.token == token {
                    values[key] = result
                    failures[key] = nil
                    flights[key] = nil
                }
                return result
            } catch {
                let failedAt = await clock()
                if flights[key]?.token == token {
                    flights[key] = nil
                    if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                        let count = (failures[key]?.count ?? 0) + 1
                        let delay = Self.retryDelay(error: error, attempt: count)
                        let failure = Failure(error: error, count: count, retryAt: failedAt.addingTimeInterval(delay))
                        failures[key] = failure
                        if Self.serverDirected(error) { recordRateLimit(connection: connection, seconds: delay, now: failedAt) }
                    }
                }
                throw error
            }
        }
        flights[key] = Flight(token: token, task: task)
        return task
    }

    func recordRateLimit(connection: UnraidConnection, seconds: TimeInterval, now: Date) {
        // An old server's response must not throttle a newly selected connection.
        guard self.connection == nil || self.connection == connection else { return }
        self.connection = connection
        let until = now.addingTimeInterval(max(1, seconds))
        if serverCooldown == nil || serverCooldown!.retryAt < until {
            serverCooldown = Failure(error: UnraidError.rateLimited(seconds), count: 1, retryAt: until)
        }
    }

    func previous(key: String, connection: UnraidConnection) -> Payload? {
        self.connection == connection ? values[key] : nil
    }

    func invalidate(keys: Set<String>? = nil) {
        if let keys {
            for key in keys {
                flights.removeValue(forKey: key)?.task.cancel()
                values[key] = nil
                failures[key] = nil
            }
        } else {
            flights.values.forEach { $0.task.cancel() }
            flights.removeAll()
            values.removeAll()
            failures.removeAll()
        }
    }

    private static func serverDirected(_ error: Error) -> Bool {
        if case UnraidError.rateLimited = error { return true }
        return false
    }

    static func retryDelay(error: Error, attempt: Int) -> TimeInterval {
        if case UnraidError.rateLimited(let seconds) = error { return max(1, seconds) }
        if error is URLError { return min(300, 10 * pow(2, Double(min(5, max(0, attempt - 1))))) }
        if case UnraidError.httpError(let status) = error, status >= 500 {
            return min(300, 10 * pow(2, Double(min(5, max(0, attempt - 1)))))
        }
        return 300 // Bad key, denied permission, or unsupported schema: no aggressive retry loop.
    }
}
