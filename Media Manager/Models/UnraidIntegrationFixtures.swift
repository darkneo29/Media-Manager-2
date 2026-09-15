#if DEBUG
import Foundation

/// Explicit offline UI-test mode. Synthetic credentials are used only on a disposable simulator.
enum UnraidIntegrationFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--unraid-integration-fixtures") }
    static func installIfRequested() {
        guard enabled else { return }
        URLProtocol.registerClass(UnraidFixtureProtocol.self)
        var defaults = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults["unraidURL"] = "https://unraid-fixture.invalid"
        defaults["unraidAPIKey"] = "synthetic-offline-key"
        defaults["iCloudSyncEnabled"] = false
        defaults["unraidStorageWarningPercent"] = 10
        for name in ["radarrURL", "sonarrURL", "sabnzbURL"] { defaults[name] = "" }
        UserDefaults.standard.setVolatileDomain(defaults, forName: UserDefaults.argumentDomain)
        UnraidService.shared.statsSocketFactory = { _ in UnraidFixtureSocket() }
    }
}

private final class UnraidFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "unraid-fixture.invalid" }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private let stopLock = NSLock()
    nonisolated(unsafe) private var stopped = false
    nonisolated override func stopLoading() { stopLock.withLock { stopped = true } }
    nonisolated override func startLoading() {
        if ProcessInfo.processInfo.arguments.contains("--unraid-offline") {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let query = object?["query"] as? String ?? ""
        let viewer = ProcessInfo.processInfo.arguments.contains("--unraid-viewer")
        let partial = ProcessInfo.processInfo.arguments.contains("--unraid-partial")
        var body: [String: Any] = [:]
        if query.contains("Capabilities") {
            let types: [String: [String]] = ["DockerMutations": ["start", "stop", "restart", "unpause"],
                "VmMutations": ["start", "stop", "reboot", "resume", "forceStop"], "CoreVersions": ["api"],
                "Docker": ["logs"], "Subscription": ["dockerContainerStats"], "UnraidArray": ["parityCheckStatus"]]
            body = ["__schema": ["types": types.map { ["name": $0.key, "fields": $0.value.map { ["name": $0] }] }]]
        } else if query.contains("Permissions") {
            body = ["me": ["roles": [viewer ? "VIEWER" : "ADMIN"], "permissions": []]]
        } else if query.contains("ApiVersion") {
            body = ["info": ["versions": ["core": ["api": "4.36.0"]]]]
        } else if query.contains("Hardware") {
            if ProcessInfo.processInfo.arguments.contains("--unraid-hardware-failure") {
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                    send(["errors": [["message": "Hardware unavailable"]]])
                }
                return
            }
            body = ["vars": ["version": "7.3.0"], "info": ["os": ["hostname": "Test Tower", "uptime": "2026-09-01T00:00:00Z"], "cpu": ["brand": "Ryzen", "cores": 8]]]
        } else if query.contains("Metrics") {
            body = ["metrics": ["cpu": ["percentTotal": 12], "memory": ["total": 16000000000, "used": 7000000000, "free": 9000000000, "available": 10000000000, "percentTotal": 40]]]
        } else if query.contains("ContainerLogs") {
            body = ["docker": ["logs": ["containerId": "server:plex", "lines": [["timestamp": "2026-09-14T12:00:00Z", "message": "Plex service started successfully"]], "cursor": "2026-09-14T12:00:00Z"]]]
        } else if query.contains("Parity") {
            body = ["array": ["parityCheckStatus": ["status": "COMPLETED", "errors": 0, "progress": 100, "running": false, "paused": false, "speed": "125"]]]
        } else if query.contains("VMs") || query.contains("VerifyVM") {
            if partial {
                send(["errors": [["message": "VM service unavailable"]]])
                return
            }
            body = ["vms": ["domains": [["id": "server:vm", "name": "Linux", "state": "RUNNING"]]]]
        } else if query.contains("mutation") {
            if query.contains("docker") { body = ["docker": ["result": ["id": "server:plex", "state": "RUNNING", "status": "Up"]]] }
            else { body = ["vm": ["result": true]] }
        } else if query.contains("Containers") || query.contains("ContainerSummary") {
            body = ["docker": ["containers": [["id": "server:plex", "names": ["/Plex"], "image": "plex:latest", "state": "RUNNING", "status": "Up 3 hours", "autoStart": true]]]]
        } else if query.contains("Storage") || query.contains("Disks") {
            body = ["array": ["state": "STARTED", "capacity": ["kilobytes": ["total": "10000000000", "used": "5000000000", "free": "5000000000"]], "disks": [], "caches": [], "parities": []]]
            if ProcessInfo.processInfo.arguments.contains("--unraid-storage-warnings") {
                body = ["array": ["state": "STARTED", "capacity": ["kilobytes": ["total": "10000000000", "used": "9200000000", "free": "800000000"]],
                    "disks": [["id": "disk1", "name": "disk1", "type": "DATA", "size": "10000000000", "fsSize": "10000000000", "fsUsed": "9200000000", "fsFree": "800000000", "status": "DISK_OK"]],
                    "caches": [["id": "cache", "name": "Download cache", "type": "CACHE", "size": "2000000000", "fsSize": "1000000000", "fsUsed": "982000000", "fsFree": "18000000", "status": "DISK_OK"],
                               ["id": "cache2", "name": "Cache member", "type": "CACHE", "size": "1000000000", "status": "DISK_OK"]], "parities": []]]
            }
        }
        let reply: [String: Any] = ["data": body]
        if query.contains("mutation") {
            DispatchQueue.global().asyncAfter(deadline: .now() + 6) { [self] in send(reply) }
        } else { send(reply) }
    }
    nonisolated private func send(_ body: [String: Any]) {
        guard !stopLock.withLock({ stopped }) else { return }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class UnraidFixtureSocket: UnraidStatsSocket, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var acknowledged = false
    nonisolated(unsafe) private var closed = false
    nonisolated func send(_ text: String) async throws {}
    nonisolated func receive() async throws -> String {
        let ack = lock.withLock { let old = acknowledged; acknowledged = true; return !old }
        if ack { return #"{"type":"connection_ack"}"# }
        try await Task.sleep(for: .milliseconds(300))
        if lock.withLock({ closed }) { throw CancellationError() }
        return #"{"type":"next","id":"container-stats","payload":{"data":{"dockerContainerStats":{"id":"server:plex","cpuPercent":12,"memUsage":"1 GB / 16 GB","memPercent":6.25,"netIO":"2 MB / 3 MB","blockIO":"1 MB / 4 MB"}}}}"#
    }
    nonisolated func cancel() { lock.withLock { closed = true } }
}
#endif
