import Foundation
import Testing
@testable import Media_Manager

private struct PriorityReply {
    var status = 200
    var body: String
    var headers: [String: String] = [:]
    var delay: TimeInterval = 0.005
}

private final class PriorityHTTPState: @unchecked Sendable {
    struct Request { let name: String; let query: String; let variables: [String: String]; let url: URL? }
    private let lock = NSLock()
    private var requests: [Request] = []
    private var replies: [String: [PriorityReply]] = [:]
    func reset(_ replies: [String: [PriorityReply]]) { lock.withLock { self.replies = replies; requests = [] } }
    func set(_ name: String, _ replies: [PriorityReply]) { lock.withLock { self.replies[name] = replies } }
    func all() -> [Request] { lock.withLock { requests } }
    func route(_ request: URLRequest) -> PriorityReply {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
        }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let query = json["query"] as? String ?? ""
        let words = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let name = words.count > 1 ? String(words[1]) : "unknown"
        return lock.withLock {
            requests.append(Request(name: name, query: query, variables: json["variables"] as? [String: String] ?? [:], url: request.url))
            guard var queue = replies[name], !queue.isEmpty else {
                return PriorityReply(status: 500, body: "{}")
            }
            let reply = queue[0]
            if queue.count > 1 { queue.removeFirst(); replies[name] = queue }
            return reply
        }
    }
}

private final class PriorityURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated static let state = PriorityHTTPState()
    private let stopLock = NSLock()
    nonisolated(unsafe) private var stopped = false
    nonisolated override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".test") == true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    nonisolated override func stopLoading() { stopLock.withLock { stopped = true } }
    nonisolated override func startLoading() {
        let reply = Self.state.route(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            guard !stopLock.withLock({ stopped }) else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

private final class PriorityStatsSocket: UnraidStatsSocket, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var frames: [String]
    nonisolated(unsafe) private var sent: [String] = []
    nonisolated(unsafe) private var closed = false
    nonisolated(unsafe) private var waiting: CheckedContinuation<String, Error>?
    init(_ frames: [String]) { self.frames = frames }
    nonisolated func send(_ text: String) async throws { lock.withLock { sent.append(text) } }
    nonisolated func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if closed { continuation.resume(throwing: CancellationError()) }
                else if !frames.isEmpty { continuation.resume(returning: frames.removeFirst()) }
                else { waiting = continuation }
            }
        }
    }
    nonisolated func cancel() {
        lock.withLock { closed = true; waiting?.resume(throwing: CancellationError()); waiting = nil }
    }
    func messages() -> [String] { lock.withLock { sent } }
    func isClosed() -> Bool { lock.withLock { closed } }
}

@Suite(.serialized)
struct UnraidPriorityTests {
    @MainActor private func service() -> (UnraidService, URLSession) {
        PriorityURLProtocol.state.reset(Self.fixtures)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PriorityURLProtocol.self]
        let session = URLSession(configuration: config)
        let service = UnraidService(session: session, credentials: { (URL(string: "https://tower.test/graphql")!, "synthetic-key") })
        service.verificationInterval = 0.01
        service.verificationAttempts = 10
        return (service, session)
    }

    private static var fixtures: [String: [PriorityReply]] {
        [
            "Hardware": [.init(body: #"{"data":{"vars":{"version":"7.3.0"},"info":{"os":{"hostname":"Tower","uptime":"2026-09-01T00:00:00Z"},"cpu":{"brand":"CPU","cores":8}}}}"#)],
            "Metrics": [.init(body: #"{"data":{"metrics":{"cpu":{"percentTotal":20},"memory":{"total":"16000","used":"8000","free":"8000","available":"9000","percentTotal":44}}}}"#)],
            "Storage": [.init(body: #"{"data":{"array":{"state":"STARTED","capacity":{"kilobytes":{"total":"100000","used":"50000","free":"50000"}}}}}"#)],
            "ContainerSummary": [.init(body: #"{"data":{"docker":{"containers":[{"id":"server:abc","state":"RUNNING"}]}}}"#)],
            "Containers": [.init(body: #"{"data":{"docker":{"containers":[{"id":"server:abc","names":["/Plex"],"image":"plex:latest","state":"RUNNING","status":"Up","autoStart":true}]}}}"#)],
            "VMs": [.init(body: Self.vm("RUNNING"))],
            "VerifyVM": [.init(body: Self.vm("RUNNING"))],
            "VMCommand": [.init(body: #"{"data":{"vm":{"result":true}}}"#)],
            "Disks": [.init(body: #"{"data":{"array":{"state":"STARTED","capacity":{"kilobytes":{"total":"100000","used":"50000","free":"50000"}},"disks":[],"caches":[],"parities":[],"boot":null}}}"#)],
            "Capabilities": [.init(body: #"{"data":{"__schema":{"types":[{"name":"DockerMutations","fields":[{"name":"start"},{"name":"stop"},{"name":"restart"},{"name":"unpause"}]},{"name":"VmMutations","fields":[{"name":"start"},{"name":"stop"},{"name":"reboot"},{"name":"forceStop"},{"name":"resume"},{"name":"pause"}]},{"name":"CoreVersions","fields":[{"name":"api"}]},{"name":"UnraidArray","fields":[{"name":"parityCheckStatus"}]},{"name":"Docker","fields":[{"name":"logs"}]},{"name":"Subscription","fields":[{"name":"dockerContainerStats"}]}]}}}"#)],
            "Permissions": [.init(body: #"{"data":{"me":{"roles":["ADMIN"],"permissions":[]}}}"#)],
            "ApiVersion": [.init(body: #"{"data":{"info":{"versions":{"core":{"api":"4.36.0"}}}}}"#)],
            "Parity": [.init(body: #"{"data":{"array":{"parityCheckStatus":{"status":"RUNNING","date":null,"duration":120,"speed":"100","errors":0,"progress":25,"running":true,"paused":false}}}}"#)],
            "ContainerLogs": [.init(body: #"{"data":{"docker":{"logs":{"containerId":"server:abc","lines":[{"timestamp":"2026-09-14T12:00:00Z","message":"Started"}],"cursor":"2026-09-14T12:00:00Z"}}}}"#)]
        ]
    }
    private static func vm(_ state: String) -> String { "{\"data\":{\"vms\":{\"domains\":[{\"id\":\"server:vm1\",\"name\":\"Linux\",\"state\":\"\(state)\"}]}}}" }

    @Test @MainActor
    func overviewIsSmallAndFailuresAreIndependent() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        PriorityURLProtocol.state.set("ContainerSummary", [.init(body: #"{"data":null,"errors":[{"message":"Docker denied","path":["docker","containers",0]}]}"#)])
        let overview = try await service.fetchOverview()
        #expect(overview.system.value?.hostname == "Tower")
        #expect(overview.storage.value?.state == .started)
        #expect(overview.containers.value == nil)
        #expect(overview.containers.error?.contains("Docker denied") == true)
        #expect(overview.spokenSummary.contains("Container status unavailable"))
        #expect(!overview.spokenSummary.contains("0 of 0"))
        let requests = PriorityURLProtocol.state.all()
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { !$0.query.contains("domains") && !$0.query.contains("disks {") && !$0.query.contains("image") })
    }

    @Test @MainActor
    func hardwareFailureDoesNotHideSiriMetrics() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        PriorityURLProtocol.state.set("Hardware", [.init(status: 403, body: "{}")])
        let overview = try await service.fetchOverview()
        #expect(overview.system.value == nil)
        #expect(overview.metrics.value != nil)
        #expect(overview.spokenSummary.contains("CPU: 20%"))
        #expect(overview.spokenSummary.contains("Memory: 44%"))
    }

    @Test @MainActor
    func sectionClocksShareRequestsAndKeepHardwareLonger() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        var now = Date(timeIntervalSince1970: 1000)
        service.readClock = { now }
        async let first = service.fetchOverview()
        async let second = service.fetchOverview()
        _ = try await (first, second)
        #expect(PriorityURLProtocol.state.all().count == 4)
        now = now.addingTimeInterval(16)
        _ = try await service.fetchOverview()
        #expect(PriorityURLProtocol.state.all().count == 6) // metrics and container counts only
        now = now.addingTimeInterval(20)
        _ = try await service.fetchOverview()
        #expect(PriorityURLProtocol.state.all().filter { $0.name == "Hardware" }.count == 1)
        #expect(PriorityURLProtocol.state.all().filter { $0.name == "Storage" }.count == 2)
        _ = try await service.fetchOverview(forceRefresh: true)
        #expect(PriorityURLProtocol.state.all().filter { $0.name == "Hardware" }.count == 2)
    }

    @Test @MainActor
    func staleSectionAndRetryAfterArePreserved() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        var now = Date(timeIntervalSince1970: 1000)
        service.readClock = { now }
        let first = try await service.fetchOverview()
        PriorityURLProtocol.state.set("Storage", [.init(status: 429, body: "{}", headers: ["Retry-After": "60"])])
        now = now.addingTimeInterval(31)
        let failed = try await service.fetchOverview()
        #expect(failed.storage.isStale)
        #expect(failed.storage.updatedAt == first.storage.updatedAt)
        let count = PriorityURLProtocol.state.all().filter { $0.name == "Storage" }.count
        _ = try await service.fetchOverview(forceRefresh: true)
        #expect(PriorityURLProtocol.state.all().filter { $0.name == "Storage" }.count == count)
        #expect(failed.system.error == nil)
        #expect(UnraidReadCache.retryDelay(error: UnraidError.httpError(503), attempt: 3) == 40)
    }

    @Test @MainActor
    func capabilitiesDisableDeniedControlsAndRefreshPermissions() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        PriorityURLProtocol.state.set("Permissions", [.init(body: #"{"data":{"me":{"roles":["VIEWER"],"permissions":[]}}}"#)])
        let caps = try await service.fetchCapabilities()
        #expect(caps.dockerAction("start") == .denied)
        #expect(caps.apiVersion == "4.36.0")
        let count = PriorityURLProtocol.state.all().count
        await #expect(throws: (any Error).self) { try await service.startContainer(id: "server:abc") }
        #expect(PriorityURLProtocol.state.all().count == count)
        PriorityURLProtocol.state.set("Permissions", [.init(body: #"{"data":{"me":{"roles":[],"permissions":[{"resource":"DOCKER","actions":["READ_ANY","UPDATE_ANY"]}]}}}"#)])
        let refreshed = try await service.fetchCapabilities(forceRefresh: true)
        #expect(refreshed.dockerAction("start") == .allowed)
        #expect(refreshed.vmAction("start") == .denied)
        var oldAPI = refreshed
        oldAPI.schema = UnraidSchema(types: [.init(name: "DockerMutations", fields: [.init(name: "start"), .init(name: "stop")])])
        #expect(oldAPI.dockerAction("restart") == .allowed)
        #expect(oldAPI.dockerAction("unpause") == .unsupported)
    }

    @Test @MainActor
    func detailsIncludeParityAndLogsAreBounded() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        PriorityURLProtocol.state.set("VMs", [.init(status: 403, body: "{}")])
        let details = try await service.fetchDetails()
        #expect(details.containers.value?.first?.displayName == "Plex")
        #expect(details.parity.value?.progress == 25)
        #expect(details.vms.error != nil)
        #expect(details.overview.system.value != nil)
        #expect(!PriorityURLProtocol.state.all().contains { $0.name == "ContainerSummary" })
        let logs = try await service.fetchContainerLogs(id: "server:abc")
        #expect(logs.value?.lines.first?.message == "Started")
        let request = try #require(PriorityURLProtocol.state.all().first { $0.name == "ContainerLogs" })
        #expect(request.query.contains("tail: 200"))
        #expect(request.variables["id"] == "server:abc")
    }

    @Test @MainActor
    func vmCommandsVerifyStatesAndDoNotPretendUnchangedRebootsCompleted() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        PriorityURLProtocol.state.set("VerifyVM", [.init(body: Self.vm("SHUTOFF")), .init(body: Self.vm("RUNNING"))])
        #expect(try await service.startVm(id: "server:vm1") == .verified)
        PriorityURLProtocol.state.set("VerifyVM", [.init(body: Self.vm("RUNNING"))])
        service.verificationAttempts = 2
        let stopped = try await service.stopVm(id: "server:vm1")
        if case .verified = stopped { Issue.record("An unchanged running VM must not be reported stopped") }
        let reboot = try await service.restartVm(id: "server:vm1")
        if case .verified = reboot { Issue.record("A running sample cannot prove reboot completion") }
        var verifier = UnraidVMVerification(action: "reboot")
        let initial = verifier.observe(.running)
        let stopping = verifier.observe(.shuttingDown)
        let restarted = verifier.observe(.running)
        #expect(!initial)
        #expect(!stopping)
        #expect(restarted)
    }

    @Test @MainActor
    func statsProtocolFiltersSamplesRespondsToPingAndCloses() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        func sample(_ id: String) -> String { "{\"type\":\"next\",\"id\":\"container-stats\",\"payload\":{\"data\":{\"dockerContainerStats\":{\"id\":\"\(id)\",\"cpuPercent\":12,\"memUsage\":\"1 GB / 8 GB\",\"memPercent\":12.5,\"netIO\":\"2 MB / 3 MB\",\"blockIO\":\"1 MB / 1 MB\"}}}}" }
        let socket = PriorityStatsSocket([#"{"type":"connection_ack"}"#, sample("server:other"), #"{"type":"ping"}"#, sample("server:abc"), #"{"type":"complete"}"#])
        service.statsSocketFactory = { request in
            #expect(request.url?.scheme == "wss")
            #expect(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "graphql-transport-ws")
            return socket
        }
        var samples: [UnraidContainerStats] = []
        try await service.watchContainerStats(id: "server:abc") { samples.append($0) }
        #expect(samples.count == 1)
        #expect(samples.first?.cpuPercent == 12)
        #expect(socket.isClosed())
        #expect(socket.messages().contains { $0.contains("connection_init") && $0.contains("synthetic-key") })
        #expect(socket.messages().contains { $0.contains("subscribe") })
        #expect(socket.messages().contains { $0.contains("pong") })
    }

    @Test @MainActor
    func cancellingStatsClosesTheSocket() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        _ = try await service.fetchCapabilities()
        let socket = PriorityStatsSocket([#"{"type":"connection_ack"}"#])
        service.statsSocketFactory = { _ in socket }
        let task = Task { try await service.watchContainerStats(id: "server:abc") { _ in } }
        for _ in 0..<50 {
            if socket.messages().contains(where: { $0.contains("subscribe") }) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        _ = try? await task.value
        #expect(socket.isClosed())
    }
}

extension UnraidPriorityTests {
    @Test @MainActor
    func serverAndKeyChangesCannotReuseOrPublishAnotherConnection() async throws {
        PriorityURLProtocol.state.reset(Self.fixtures)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PriorityURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var endpoint = URL(string: "https://first.test/graphql")!
        var apiKey = "first-key"
        let service = UnraidService(session: session, credentials: { (endpoint, apiKey) })
        _ = try await service.fetchOverview()
        #expect(PriorityURLProtocol.state.all().count == 4)
        apiKey = "second-key"
        _ = try await service.fetchOverview()
        #expect(PriorityURLProtocol.state.all().count == 8)
        endpoint = URL(string: "https://second.test/graphql")!
        _ = try await service.fetchOverview()
        #expect(PriorityURLProtocol.state.all().count == 12)
        #expect(PriorityURLProtocol.state.all().suffix(4).allSatisfy { $0.url?.host == "second.test" })
        var delayed = Self.fixtures["Hardware"]![0]
        delayed.delay = 0.2
        PriorityURLProtocol.state.set("Hardware", [delayed])
        let obsolete = Task { try await service.fetchOverview(forceRefresh: true) }
        try await Task.sleep(for: .milliseconds(20))
        endpoint = URL(string: "https://third.test/graphql")!
        _ = try await service.fetchOverview()
        await #expect(throws: (any Error).self) { _ = try await obsolete.value }
    }

    @Test @MainActor
    func vmStopVerifiesAndConcurrentCommandsAreRejected() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        PriorityURLProtocol.state.set("VerifyVM", [.init(body: Self.vm("RUNNING")), .init(body: Self.vm("SHUTOFF"))])
        #expect(try await service.stopVm(id: "server:vm1") == .verified)
        PriorityURLProtocol.state.set("VMCommand", [.init(body: #"{"data":{"vm":{"result":true}}}"#, delay: 0.1)])
        PriorityURLProtocol.state.set("VerifyVM", [.init(body: Self.vm("RUNNING"))])
        let first = Task { try await service.startVm(id: "server:vm1") }
        try await Task.sleep(for: .milliseconds(20))
        await #expect(throws: (any Error).self) { _ = try await service.startVm(id: "server:vm1") }
        #expect(try await first.value == .verified)
        #expect(PriorityURLProtocol.state.all().filter { $0.name == "VMCommand" }.count == 2)
    }

    @Test @MainActor
    func rebootObservedAcrossShutdownAndRunningIsVerified() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        PriorityURLProtocol.state.set("VMCommand", [.init(body: #"{"data":{"vm":{"result":true}}}"#, delay: 0.08)])
        PriorityURLProtocol.state.set("VerifyVM", [.init(body: Self.vm("RUNNING")), .init(body: Self.vm("SHUTDOWN")), .init(body: Self.vm("RUNNING"))])
        #expect(try await service.restartVm(id: "server:vm1") == .verified)
    }
}

extension UnraidPriorityTests {
    @Test @MainActor
    func nullableDevicesAndLargeMetricsRemainUsable() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        PriorityURLProtocol.state.set("Disks", [.init(body: #"{"data":{"array":{"state":"STOPPED","capacity":{"kilobytes":{"total":"1000","used":"250","free":"750"}},"disks":[{"id":"disk:1","name":null,"size":null,"status":null,"temp":null,"type":"DATA"}],"caches":[],"parities":[],"boot":{"id":"disk:boot","name":"boot","size":"1024","status":"DISK_OK","type":"BOOT"}}}}"#)])
        PriorityURLProtocol.state.set("VMs", [.init(body: #"{"data":{"vms":{"domains":[{"id":"vm:123","name":null,"state":"SHUTOFF"}]}}}"#)])
        PriorityURLProtocol.state.set("Metrics", [.init(body: #"{"data":{"metrics":{"cpu":{"percentTotal":12},"memory":{"total":"34359738368","used":8589934592,"free":"25769803776","available":"30000000000","percentTotal":12.7}}}}"#)])
        let data = try await service.fetchDetails()
        #expect(data.disks.value?.disks.first?.size == 0)
        #expect(data.disks.value?.disks.first?.status == .unknown)
        #expect(data.disks.value?.disks.last?.type == .flash)
        #expect(data.vms.value?.first?.id == "vm:123")
        #expect(data.vms.value?.first?.name == "Unnamed VM")
        #expect(data.overview.system.value?.memory.total == 34359738368)
        #expect(data.overview.system.value?.memory.available == 30000000000)
    }
}

private actor UnraidTestClock {
    private var date = Date(timeIntervalSince1970: 1000)
    func now() -> Date { date }
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}

extension UnraidPriorityTests {
    @Test @MainActor
    func cacheFreshnessAndRetryAfterStartWhenResponseArrives() async throws {
        let cache = UnraidReadCache()
        let clock = UnraidTestClock()
        let context = UnraidConnection(url: URL(string: "https://timing.test/graphql")!, apiKey: "test")
        let first = await cache.task(key: "hardware", connection: context, ttl: 30, force: false,
                                     now: await clock.now(), clock: { await clock.now() }) {
            await clock.advance(20)
            return Data("cached".utf8)
        }
        let received = try await first.value
        #expect(received.updatedAt == Date(timeIntervalSince1970: 1020))
        await clock.advance(15)
        let hit = await cache.task(key: "hardware", connection: context, ttl: 30, force: false,
                                   now: await clock.now(), clock: { await clock.now() }) { throw UnraidError.invalidResponse }
        #expect(try await hit.value.data == Data("cached".utf8))
        let failure = await cache.task(key: "storage", connection: context, ttl: 30, force: false,
                                       now: await clock.now(), clock: { await clock.now() }) {
            await clock.advance(20)
            throw UnraidError.rateLimited(60)
        }
        await #expect(throws: (any Error).self) { _ = try await failure.value }
        await clock.advance(45) // 65 seconds since request start, only 45 since response.
        await cache.recordRateLimit(connection: context, seconds: 2, now: await clock.now())
        // A later short cooldown must not shorten the outstanding 60-second limit.
        let limited = await cache.task(key: "storage", connection: context, ttl: 30, force: true,
                                       now: await clock.now(), clock: { await clock.now() }) { Data("too soon".utf8) }
        await #expect(throws: (any Error).self) { _ = try await limited.value }
    }

    @Test @MainActor
    func vmVerificationStopsOnRateLimitAndRefreshHonorsCooldown() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        _ = try await service.fetchDetails()
        PriorityURLProtocol.state.set("VerifyVM", [.init(status: 429, body: "{}", headers: ["Retry-After": "60"])])
        let result = try await service.stopVm(id: "server:vm1")
        guard case .unverified = result else { Issue.record("Rate-limited verification must stay unverified"); return }
        #expect(PriorityURLProtocol.state.all().filter { $0.name == "VerifyVM" }.count == 1)
        let count = PriorityURLProtocol.state.all().count
        let details = try await service.fetchDetails(forceRefresh: true)
        #expect(PriorityURLProtocol.state.all().count == count)
        #expect(details.vms.error != nil)
    }
}

extension UnraidPriorityTests {
    @Test @MainActor
    func pausedOrIdleSamplesDoNotProveAReboot() {
        for state in [VmState.paused, .idle, .suspended, .crashed, .unknown] {
            var verifier = UnraidVMVerification(action: "reboot")
            let before = verifier.observe(state)
            let after = verifier.observe(.running)
            #expect(!before && !after)
        }
    }

    @Test @MainActor
    func statsPartialErrorsPreserveServerMessage() async throws {
        let (service, session) = service(); defer { session.invalidateAndCancel() }
        let socket = PriorityStatsSocket([
            #"{"type":"connection_ack"}"#,
            #"{"type":"next","id":"container-stats","payload":{"data":{"dockerContainerStats":null},"errors":[{"message":"Docker metrics denied","path":["dockerContainerStats"]}]}}"#
        ])
        service.statsSocketFactory = { _ in socket }
        do {
            try await service.watchContainerStats(id: "server:abc") { _ in Issue.record("Unexpected metrics") }
            Issue.record("Expected server error")
        } catch {
            #expect(error.localizedDescription.contains("Docker metrics denied"))
        }
        #expect(socket.isClosed())
    }
}
