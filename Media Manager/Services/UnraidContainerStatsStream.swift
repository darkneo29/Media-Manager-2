import Foundation

protocol UnraidStatsSocket: Sendable {
    nonisolated func send(_ text: String) async throws
    nonisolated func receive() async throws -> String
    nonisolated func cancel()
}

final class UnraidURLSessionStatsSocket: UnraidStatsSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    init(session: URLSession, request: URLRequest) {
        task = session.webSocketTask(with: request)
        task.maximumMessageSize = 131_072
        task.resume()
    }
    nonisolated func send(_ text: String) async throws { try await task.send(.string(text)) }
    nonisolated func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
            return text
        @unknown default: throw URLError(.badServerResponse)
        }
    }
    nonisolated func cancel() { task.cancel(with: .goingAway, reason: nil) }
}

extension UnraidService {
    private struct StatsErrors: Decodable { let errors: [GraphQLError]? }
    struct StatsResponse: Codable { let dockerContainerStats: UnraidContainerStats }

    func watchContainerStats(id: String, onValue: (UnraidContainerStats) -> Void) async throws {
        let context = try requestContext()
        let caps = try await fetchCapabilities()
        let access = caps.access(resource: "DOCKER", type: "Subscription", field: "dockerContainerStats")
        guard access.permitsAttempt else { throw UnraidError.featureUnavailable(access.explanation ?? "Metrics unavailable") }
        var components = URLComponents(url: context.url, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let url = components.url else { throw UnraidError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.setValue("graphql-transport-ws", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let socket = statsSocketFactory?(request) ?? UnraidURLSessionStatsSocket(session: session, request: request)
        defer { socket.cancel() }
        try await withTaskCancellationHandler {
            // Unraid's authentication guard reads headers directly from connectionParams.
            try await socket.send(Self.json(["type": "connection_init", "payload": ["x-api-key": context.apiKey]]))
            var subscribed = false
            while !Task.isCancelled {
                let text = try await Self.receiveStats(socket, timeout: subscribed ? 30 : 15)
                try Task.checkCancellation()
                guard try requestContext() == context else { throw CancellationError() }
                let data = Data(text.utf8)
                guard data.count <= 131_072,
                      let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = frame["type"] as? String else { throw UnraidError.invalidResponse }
                switch type {
                case "connection_ack":
                    guard !subscribed else { continue }
                    subscribed = true
                    try await socket.send(Self.json(["id": "container-stats", "type": "subscribe", "payload": ["query": Self.statsQuery]]))
                case "ping":
                    var pong: [String: Any] = ["type": "pong"]
                    if let payload = frame["payload"] { pong["payload"] = payload }
                    try await socket.send(Self.json(pong))
                case "next":
                    guard frame["id"] as? String == "container-stats", let payload = frame["payload"] else { continue }
                    let payloadData = try JSONSerialization.data(withJSONObject: payload)
                    let envelope = try JSONDecoder().decode(StatsErrors.self, from: payloadData)
                    if let errors = envelope.errors, !errors.isEmpty {
                        throw UnraidError.graphQLError(errors.map(\.message).joined(separator: "\n"))
                    }
                    let response = try JSONDecoder().decode(GraphQLResponse<StatsResponse>.self, from: payloadData)
                    if let errors = response.errors, !errors.isEmpty { throw UnraidError.graphQLError(errors.map(\.message).joined(separator: "\n")) }
                    guard let value = response.data?.dockerContainerStats else { throw UnraidError.noData }
                    if Self.sameContainer(value.id, id) { onValue(value) }
                case "error":
                    let payload = try JSONSerialization.data(withJSONObject: frame["payload"] ?? [])
                    let errors = try JSONDecoder().decode([GraphQLError].self, from: payload)
                    throw UnraidError.graphQLError(errors.map(\.message).joined(separator: "\n"))
                case "complete": return
                default: continue
                }
            }
            throw CancellationError()
        } onCancel: { socket.cancel() }
    }

    static func sameContainer(_ received: String, _ selected: String) -> Bool {
        !received.isEmpty && !selected.isEmpty && (received == selected || received.split(separator: ":").last == selected.split(separator: ":").last)
    }

    private static func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func receiveStats(_ socket: any UnraidStatsSocket, timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await socket.receive() }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                socket.cancel()
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw CancellationError() }
            return value
        }
    }
}
