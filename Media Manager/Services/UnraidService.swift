import Foundation

@MainActor
final class UnraidService {
    static let shared = UnraidService()

    // MARK: - Cached Formatters (avoid recreating on every call)

    private static let iso8601FormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let readCache = UnraidReadCache()
    var capabilityState: (connection: UnraidConnection, value: UnraidCapabilities)?
    var absentRestart: Set<UnraidConnection> = []
    var activeCommands: Set<CommandKey> = []
    struct CommandKey: Hashable { let url: URL; let resource: String }
    var statsSocketFactory: ((URLRequest) -> any UnraidStatsSocket)?
    var verificationAttempts = 30
    var verificationInterval: TimeInterval = 2
    var readClock: () -> Date = Date.init

    private let config = ConfigurationManager.shared

    private func getBaseURL() -> String {
        config.unraidURL
    }

    private func getAPIKey() -> String {
        config.unraidAPIKey
    }

    let session: URLSession
    private let credentials: (() -> (url: URL, apiKey: String))?

    init(session: URLSession = .shared, credentials: (() -> (url: URL, apiKey: String))? = nil) {
        self.session = session
        self.credentials = credentials
    }

    // MARK: - GraphQL Endpoint

    static func isConnectivityFailure(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
                .networkConnectionLost, .dnsLookupFailed, .timedOut,
                .dataNotAllowed, .internationalRoamingOff, .callIsActive].contains(error.code)
    }

    static func shouldRetryRead(_ error: Error) -> Bool {
        if case UnraidError.rateLimited = error { return true }
        if case UnraidError.httpError(let status) = error { return status == 429 || (500...599).contains(status) }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet].contains(error.code)
    }

    static func graphQLURL(from value: String) throws -> URL {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw UnraidError.invalidURL }
        components.scheme = scheme
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/graphql") { path += "/graphql" }
        components.path = path
        guard let url = components.url else { throw UnraidError.invalidURL }
        return url
    }

    typealias RequestContext = UnraidConnection

    func requestContext() throws -> RequestContext {
        if let credentials {
            let value = credentials()
            return RequestContext(url: value.url, apiKey: value.apiKey)
        }
        guard config.isUnraidConfigured else { throw UnraidError.notConfigured }
        return RequestContext(url: try Self.graphQLURL(from: getBaseURL()), apiKey: getAPIKey())
    }

    static let systemFields = """
    vars { version }
    info { os { hostname uptime } cpu { brand cores } }
    metrics { cpu { percentTotal } memory { total used free available percentTotal } }
    """

    static let arrayFields = """
    array {
        state
        capacity { kilobytes { total used free } }
        disks { id name size fsSize fsUsed fsFree status temp type device }
        caches { id name size fsSize fsUsed fsFree status temp type device }
        parities { id name size fsSize fsUsed fsFree status temp type device }
        boot { id name size fsSize fsUsed fsFree status temp type device }
    }
    """

    static let dockerFields = """
    docker { containers { id names image state status autoStart } }
    """

    static let vmFields = """
    vms { domains { id name state } }
    """

    /// Reset cached reads when saved connection settings change.
    func invalidateCache() async {
        await readCache.invalidate()
        capabilityState = nil
        absentRestart.removeAll()
    }

    // MARK: - Docker Container Actions

    func startContainer(id: String) async throws {
        try await dockerCommand(id: id, action: "start") { try await self.performDockerAction("start", id: id, context: $0) }
    }

    func resumeContainer(id: String) async throws {
        try await dockerCommand(id: id, action: "unpause") { try await self.performDockerAction("unpause", id: id, context: $0) }
    }

    func stopContainer(id: String) async throws {
        try await dockerCommand(id: id, action: "stop") { try await self.performDockerAction("stop", id: id, context: $0) }
    }

    func restartContainer(id: String) async throws {
        try await dockerCommand(id: id, action: "restart") { context in
            let schema = self.capabilityState?.connection == context ? self.capabilityState?.value.schema : nil
            let hasNativeRestart = schema?.supports("DockerMutations", "restart")
            if !self.absentRestart.contains(context), hasNativeRestart != false {
                do {
                    try await self.performDockerAction("restart", id: id, context: context)
                    return
                } catch UnraidError.graphQLError(let message) where Self.isMissingRestartField(message) {
                    self.absentRestart.insert(context)
                }
            }
            try await self.performDockerAction("stop", id: id, context: context)
            do { try await self.performDockerAction("start", id: id, context: context) }
            catch { throw UnraidError.graphQLError("Container stopped, but could not be started again: \(error.localizedDescription)") }
        }
    }

    private func dockerCommand(id: String, action: String, operation: (UnraidConnection) async throws -> Void) async throws {
        let context = try requestContext()
        if let caps = capabilityState, caps.connection == context {
            let access = caps.value.dockerAction(action)
            guard access.permitsAttempt else { throw UnraidError.featureUnavailable(access.explanation ?? "Command unavailable") }
        }
        let key = CommandKey(url: context.url, resource: "docker:\(id)")
        guard activeCommands.insert(key).inserted else { throw UnraidError.commandInProgress }
        defer { activeCommands.remove(key) }
        try await operation(context)
    }

    static func isMissingRestartField(_ message: String) -> Bool {
        message.contains("Cannot query field \"restart\" on type \"DockerMutations\"")
    }

    private struct DockerActionResponse: Codable {
        let docker: Result
        struct Result: Codable { let result: ContainerMutationResult }
    }

    private func performDockerAction(_ action: String, id: String, context: RequestContext) async throws {
        await invalidateDockerState()
        do {
            let response: GraphQLResponse<DockerActionResponse> = try await executeQuery(
                "mutation($id: PrefixedID!) { docker { result: \(action)(id: $id) { id state status } } }",
                variables: ["id": id], timeout: 120, context: context
            )
            guard response.data != nil else { throw UnraidError.noData }
            await invalidateDockerState()
        } catch {
            await invalidateDockerState()
            throw error
        }
    }

    // MARK: - Schema Introspection

    /// Introspects the GraphQL schema to discover available fields
    func introspectSchema(url: String, apiKey: String) async throws -> String {
        let testURL = try Self.graphQLURL(from: url)

        // Introspection query to discover the schema
        let query = """
        query {
            __schema {
                queryType { name }
                types {
                    name
                    kind
                    fields {
                        name
                        type { name kind ofType { name kind } }
                    }
                }
            }
        }
        """

        var request = URLRequest(url: testURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnraidError.invalidResponse
        }
        if httpResponse.statusCode == 429 { throw UnraidError.rateLimited(Self.retryAfter(httpResponse, now: Date())) }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 { throw UnraidError.forbidden }
            if httpResponse.statusCode == 401 {
                throw UnraidError.unauthorized
            }
            throw UnraidError.httpError(httpResponse.statusCode)
        }

        if let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }

        throw UnraidError.decodingFailed
    }

    // MARK: - Connection Test

    /// Tests the connection to the Unraid server using the provided URL and API key
    func testConnection(url: String, apiKey: String) async throws -> UnraidSystemInfo {
        let testURL = try Self.graphQLURL(from: url)

        // Unraid 7.2+ schema: version is in vars, uptime is ISO8601 boot timestamp
        // metrics provides real-time CPU and memory usage
        // cpu.brand contains the actual CPU name (e.g., "Ryzen 7 2700")
        let query = Self.hardwareQuery

        struct TestConnectionResponse: Codable {
            let vars: VarsData
            let info: TestInfoData
            let metrics: MetricsData?
        }

        let response: GraphQLResponse<TestConnectionResponse> = try await executeQueryWithCredentials(
            query,
            url: testURL,
            apiKey: apiKey
        )

        guard let data = response.data else {
            if let error = response.errors?.first {
                throw UnraidError.graphQLError(error.message)
            }
            throw UnraidError.connectionFailed
        }

        return parseSystemInfo(info: data.info, version: data.vars.version, metrics: data.metrics)
    }

    // MARK: - Private Helpers

    func executeQuery<T: Codable>(_ query: String, variables: [String: String] = [:], timeout: TimeInterval = 15, context: RequestContext? = nil) async throws -> GraphQLResponse<T> {
        let context = try context ?? requestContext()
        try Task.checkCancellation()
        return try await executeQueryWithCredentials(query, url: context.url, apiKey: context.apiKey, variables: variables, timeout: timeout)
    }

    func executeQueryWithCredentials<T: Codable>(
        _ query: String,
        url: URL,
        apiKey: String,
        variables: [String: String] = [:],
        timeout: TimeInterval = 15
    ) async throws -> GraphQLResponse<T> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        // Add Origin header to help with CORS
        if let scheme = url.scheme, let host = url.host {
            var origin = "\(scheme)://\(host)"
            if let port = url.port {
                origin += ":\(port)"
            }
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }

        let body: [String: Any] = ["query": query, "variables": variables]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnraidError.invalidResponse
        }

        // GraphQL validation failures can use HTTP 400. Decode errors before
        // the payload so partial data cannot hide the actual server error.
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 400 {
            let envelope = try? JSONDecoder().decode(GraphQLResponse<EmptyResponse>.self, from: data)
            if let errors = envelope?.errors, !errors.isEmpty {
                throw UnraidError.graphQLError(errors.map(\.message).joined(separator: "\n"))
            }
        }

        if httpResponse.statusCode == 429 {
            let seconds = Self.retryAfter(httpResponse, now: Date())
            await readCache.recordRateLimit(connection: UnraidConnection(url: url, apiKey: apiKey),
                                            seconds: seconds, now: readClock())
            throw UnraidError.rateLimited(seconds)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 { throw UnraidError.forbidden }
            if httpResponse.statusCode == 401 {
                throw UnraidError.unauthorized
            }
            throw UnraidError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
            if let errors = graphQLResponse.errors, !errors.isEmpty {
                let message = errors.map(\.message).joined(separator: "\n")
                throw UnraidError.graphQLError(message)
            }
            return graphQLResponse
        } catch {
            if let unraidError = error as? UnraidError {
                throw unraidError
            }
            throw UnraidError.decodingFailed
        }
    }

    // MARK: - Parsing Helpers

    func parseSystemInfo(info: TestInfoData, version: String, metrics: MetricsData?) -> UnraidSystemInfo {
        UnraidSystemInfo(
            hostname: info.os.hostname,
            version: version,
            uptime: parseUptimeFromBootTime(info.os.uptime),
            cpu: UnraidCPU(model: info.cpu.brand ?? info.cpu.model ?? "Unknown",
                          cores: info.cpu.cores.intValue,
                          usage: (metrics?.cpu?.percentTotal).map { min(100, max(0, $0)) }, temperature: nil),
            memory: UnraidMemory(total: metrics?.memory?.total ?? 0,
                                 used: metrics?.memory?.used ?? 0,
                                 free: metrics?.memory?.free ?? 0,
                                 available: metrics?.memory?.available,
                                 percentTotalFromAPI: metrics?.memory?.percentTotal)
        )
    }

    static func saturatingKilobytes(_ value: Int64) -> Int64 {
        let (result, overflow) = max(0, value).multipliedReportingOverflow(by: 1_000)
        return overflow ? Int64.max : result
    }

    private static func saturatingSum(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : result
    }

    func parseArray(from data: ArrayData) -> UnraidArray {
        // Helper to parse a single disk
        func parseDisk(_ disk: DiskData) -> UnraidDisk {
            let diskSizeKB = max(0, Int64(disk.size?.intValue ?? 0))
            let diskSizeBytes = Self.saturatingKilobytes(diskSizeKB)  // KB to bytes (SI units)

            // fsUsed is in KB
            let usedBytes = Self.saturatingKilobytes(Int64(disk.fsUsed?.intValue ?? 0))

            // Filesystem capacity can differ from physical size, especially for pools.
            // Never infer free space from physical size or turn missing values into zero.
            func filesystemNumber(_ value: DiskData.IntOrString?) -> Int64? {
                switch value {
                case .int(let number): return Int64(number)
                case .string(let number): return Int64(number)
                case nil: return nil
                }
            }
            var filesystemCapacity: ArrayCapacity?
            if let total = filesystemNumber(disk.fsSize), let used = filesystemNumber(disk.fsUsed),
               let free = filesystemNumber(disk.fsFree), total > 0, used >= 0, free >= 0,
               total <= Int64.max / 1000, used <= Int64.max / 1000, free <= Int64.max / 1000 {
                let capacity = ArrayCapacity(total: Int64(total) * 1000, used: Int64(used) * 1000, free: Int64(free) * 1000)
                if capacity.isUsable { filesystemCapacity = capacity }
            }

            return UnraidDisk(
                id: disk.id ?? disk.name ?? disk.device ?? "unknown",
                name: disk.name ?? disk.device ?? "Unknown disk",
                size: diskSizeBytes,
                used: usedBytes,
                status: DiskStatus(apiValue: disk.status ?? "UNKNOWN"),
                temperature: disk.temp,
                type: parseDiskType(disk.type ?? disk.name ?? ""),
                device: disk.device,
                serial: disk.serial,
                filesystemCapacity: filesystemCapacity
            )
        }

        // Parse all disk types
        var allDisks: [UnraidDisk] = []

        // Add parity disks first
        if let parities = data.parities {
            allDisks.append(contentsOf: parities.map(parseDisk))
        }

        // Add data disks
        allDisks.append(contentsOf: data.disks.map(parseDisk))

        // Add cache disks
        if let caches = data.caches {
            allDisks.append(contentsOf: caches.map(parseDisk))
        }

        // Add boot/flash drive
        if let boot = data.boot {
            allDisks.append(parseDisk(boot))
        }

        // Calculate total capacity from data disks (exclude parity, cache, flash)
        let dataDisks = allDisks.filter { $0.type == .data }
        let totalBytes = dataDisks.reduce(Int64(0)) { Self.saturatingSum($0, $1.size) }

        // Sum up used from individual data disks for accurate capacity
        let totalUsedBytes = dataDisks.reduce(Int64(0)) { Self.saturatingSum($0, $1.used) }

        // The API's authoritative storage capacity is expressed in kilobytes.
        // `capacity.disks` is a disk *count* and must never be treated as bytes.
        let apiTotalBytes = bytesFromKilobyteString(data.capacity.kilobytes?.total)
        let apiUsedBytes = bytesFromKilobyteString(data.capacity.kilobytes?.used)
        let apiFreeBytes = bytesFromKilobyteString(data.capacity.kilobytes?.free)

        let resolvedTotalBytes = apiTotalBytes ?? totalBytes
        let resolvedUsedBytes = apiUsedBytes ?? totalUsedBytes
        let resolvedFreeBytes = apiFreeBytes ?? max(0, resolvedTotalBytes - resolvedUsedBytes)

        return UnraidArray(
            state: ArrayState(rawValue: data.state) ?? .unknown,
            capacity: ArrayCapacity(
                total: resolvedTotalBytes,
                used: resolvedUsedBytes,
                free: resolvedFreeBytes
            ),
            disks: allDisks,
            parity: nil // Would need additional query for parity status
        )
    }

    func parseContainer(from data: ContainerData) -> DockerContainer {
        let name = data.name ?? data.names?.first ?? "Unknown"

        return DockerContainer(
            id: data.id,
            name: name,
            image: data.image,
            state: ContainerState(rawValue: data.state.lowercased()) ?? .unknown,
            status: data.status,
            autoStart: data.autoStart ?? false,
            ports: nil,
            cpuUsage: nil,
            memoryUsage: nil
        )
    }

    func parseVm(from data: VmDomainData) -> VmDomain {
        return VmDomain(
            id: data.id ?? data.uuid ?? "unknown",
            name: data.name ?? "Unnamed VM",
            uuid: data.uuid ?? data.id ?? "unknown",
            state: VmState(rawValue: data.state.uppercased()) ?? .unknown
        )
    }

    /// Parses uptime from an ISO8601 boot timestamp (Unraid 7.2+ format)
    private func parseUptimeFromBootTime(_ bootTimeString: String) -> Int {
        // Unraid 7.2+ returns boot time as ISO8601, e.g., "2025-12-28T18:46:41.080Z"
        // Use cached formatters for efficiency

        if let bootDate = Self.iso8601FormatterWithFractional.date(from: bootTimeString) {
            let uptimeSeconds = Int(Date().timeIntervalSince(bootDate))
            return max(0, uptimeSeconds)
        }

        // Try without fractional seconds
        if let bootDate = Self.iso8601FormatterStandard.date(from: bootTimeString) {
            let uptimeSeconds = Int(Date().timeIntervalSince(bootDate))
            return max(0, uptimeSeconds)
        }

        // Fallback to legacy parsing if ISO8601 fails
        return parseUptime(bootTimeString)
    }

    /// Legacy uptime parser for older formats
    private func parseUptime(_ uptimeString: String) -> Int {
        // Parse uptime string like "5 days, 3:42:15" or "1234567"
        if let seconds = Int(uptimeString) {
            return seconds
        }

        var totalSeconds = 0
        let components = uptimeString.lowercased()

        // Extract days
        if let daysRange = components.range(of: #"(\d+)\s*days?"#, options: .regularExpression) {
            let daysStr = components[daysRange].filter { $0.isNumber }
            if let days = Int(daysStr) {
                totalSeconds += days * 86400
            }
        }

        // Extract hours:minutes:seconds
        if let timeRange = components.range(of: #"(\d+):(\d+):(\d+)"#, options: .regularExpression) {
            let timeParts = components[timeRange].split(separator: ":")
            if timeParts.count == 3,
               let hours = Int(timeParts[0]),
               let minutes = Int(timeParts[1]),
               let seconds = Int(timeParts[2]) {
                totalSeconds += hours * 3600 + minutes * 60 + seconds
            }
        }

        return totalSeconds
    }

    private func bytesFromKilobyteString(_ value: String?) -> Int64? {
        guard let value,
              let kilobytes = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              kilobytes >= 0 else { return nil }
        let (bytes, overflow) = kilobytes.multipliedReportingOverflow(by: 1_000)
        return overflow ? nil : bytes
    }

    private func parseDiskType(_ typeOrName: String) -> DiskType {
        let lower = typeOrName.lowercased()
        if lower.contains("parity") { return .parity }
        if lower.contains("cache") { return .cache }
        if lower.contains("flash") || lower.contains("boot") { return .flash }
        return .data
    }
}

// MARK: - Empty Response for Mutations

private struct EmptyResponse: Codable {}

// MARK: - Error Types

nonisolated enum UnraidError: LocalizedError {
    case notConfigured
    case invalidURL
    case connectionFailed
    case unauthorized
    case forbidden
    case httpError(Int)
    case rateLimited(TimeInterval)
    case commandInProgress
    case featureUnavailable(String)
    case graphQLError(String)
    case decodingFailed
    case noData
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Unraid server is not configured"
        case .invalidURL:
            return "Invalid server URL"
        case .connectionFailed:
            return "Could not connect to server"
        case .unauthorized:
            return "Invalid or expired API key"
        case .forbidden:
            return "The API key does not have permission for this operation"
        case .rateLimited(let seconds):
            return "Server is limiting requests. Retry in \(String(format: "%.0f", seconds.rounded(.up))) seconds."
        case .commandInProgress:
            return "A command for this resource is already in progress."
        case .featureUnavailable(let message):
            return message
        case .httpError(let code):
            return "Server returned error \(code)"
        case .graphQLError(let message):
            return "GraphQL error: \(message)"
        case .decodingFailed:
            return "Failed to parse server response"
        case .noData:
            return "No data received from server"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
