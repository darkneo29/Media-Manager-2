import Foundation

class UnraidService {
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

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static let bytesRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^([\d.,]+)\s*([KMGTP]?B?)$"#, options: [])
    }()

    // MARK: - Request Cache (deduplication and caching)

    private actor CacheManager {
        private var cachedData: (system: UnraidSystemInfo, array: UnraidArray, containers: [DockerContainer], vms: [VmDomain])?
        private var cacheTimestamp: Date?
        private var inFlightTask: Task<(system: UnraidSystemInfo, array: UnraidArray, containers: [DockerContainer], vms: [VmDomain]), Error>?

        private let cacheValiditySeconds: TimeInterval = 5  // Cache valid for 5 seconds

        func getCachedData() -> (system: UnraidSystemInfo, array: UnraidArray, containers: [DockerContainer], vms: [VmDomain])? {
            guard let cached = cachedData,
                  let timestamp = cacheTimestamp,
                  Date().timeIntervalSince(timestamp) < cacheValiditySeconds else {
                return nil
            }
            return cached
        }

        func setCachedData(_ data: (system: UnraidSystemInfo, array: UnraidArray, containers: [DockerContainer], vms: [VmDomain])) {
            cachedData = data
            cacheTimestamp = Date()
        }

        typealias UnraidAllData = (system: UnraidSystemInfo, array: UnraidArray, containers: [DockerContainer], vms: [VmDomain])

        func getOrCreateFetchTask(factory: @Sendable @escaping () async throws -> UnraidAllData) -> Task<UnraidAllData, Error> {
            if let existing = inFlightTask {
                return existing
            }
            let task = Task<UnraidAllData, Error> {
                defer {
                    Task { await self.clearInFlightTask() }
                }
                let result = try await factory()
                await self.setCachedData(result)
                return result
            }
            inFlightTask = task
            return task
        }

        func clearInFlightTask() {
            inFlightTask = nil
        }

        func invalidateCache() {
            cachedData = nil
            cacheTimestamp = nil
        }
    }

    private let cacheManager = CacheManager()
    private let config = ConfigurationManager.shared

    private func getBaseURL() -> String {
        config.unraidURL
    }

    private func getAPIKey() -> String {
        config.unraidAPIKey
    }

    /// Sanitizes an ID for use in GraphQL string interpolation to prevent injection
    private func sanitizeId(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private init() {}

    // MARK: - GraphQL Endpoint

    private func getGraphQLURL() -> URL? {
        let baseURL = getBaseURL()
        guard !baseURL.isEmpty else { return nil }
        let cleanURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(cleanURL)/graphql")
    }

    // MARK: - Public API Methods

    /// Fetches system information including hostname, CPU, memory, and version
    func fetchSystemInfo() async throws -> UnraidSystemInfo {
        // Unraid 7.2+ schema: version is in vars, uptime is ISO8601 boot timestamp
        // metrics provides real-time CPU and memory usage
        // cpu.brand contains the actual CPU name (e.g., "Ryzen 7 2700")
        let query = """
        query {
            vars { version }
            online
            info {
                os { hostname uptime }
                cpu { brand cores }
            }
            metrics {
                cpu { percentTotal }
                memory { total used free available percentTotal }
            }
        }
        """

        struct SystemInfoWithMetrics: Codable {
            let vars: VarsData
            let online: Bool
            let info: TestInfoData
            let metrics: MetricsData?
        }

        let response: GraphQLResponse<SystemInfoWithMetrics> = try await executeQuery(query)

        guard let data = response.data else {
            if let error = response.errors?.first {
                throw UnraidError.graphQLError(error.message)
            }
            throw UnraidError.noData
        }

        return UnraidSystemInfo(
            hostname: data.info.os.hostname,
            version: data.vars.version,
            uptime: parseUptimeFromBootTime(data.info.os.uptime),
            cpu: UnraidCPU(
                model: data.info.cpu.brand ?? data.info.cpu.model ?? "Unknown",
                cores: data.info.cpu.cores.intValue,
                usage: data.metrics?.cpu?.percentTotal ?? 0,
                temperature: nil
            ),
            memory: UnraidMemory(
                total: data.metrics?.memory?.total ?? 0,
                used: data.metrics?.memory?.used ?? 0,
                free: data.metrics?.memory?.free ?? 0,
                available: data.metrics?.memory?.available,
                percentTotalFromAPI: data.metrics?.memory?.percentTotal
            )
        )
    }

    /// Fetches array status including capacity and disk information
    func fetchArray() async throws -> UnraidArray {
        let query = """
        query {
            array {
                state
                capacity {
                    disks { total used free }
                }
                disks {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                caches {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                parities {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                boot {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
            }
        }
        """

        let response: GraphQLResponse<ArrayQueryResponse> = try await executeQuery(query)

        guard let data = response.data else {
            if let error = response.errors?.first {
                throw UnraidError.graphQLError(error.message)
            }
            throw UnraidError.noData
        }

        return parseArray(from: data.array)
    }

    /// Fetches all Docker containers
    func fetchDockerContainers() async throws -> [DockerContainer] {
        // Try the nested docker.containers query first (Unraid 7.1)
        let query = """
        query {
            docker {
                containers {
                    id
                    names
                    image
                    state
                    status
                    autoStart
                }
            }
        }
        """

        struct DockerResponse: Codable {
            let docker: DockerData?
        }

        struct DockerData: Codable {
            let containers: [ContainerData]?
        }

        let response: GraphQLResponse<DockerResponse> = try await executeQuery(query)

        if let data = response.data, let containers = data.docker?.containers {
            return containers.map { parseContainer(from: $0) }
        }

        // If that fails, the API might not support docker queries
        #if DEBUG
        if let error = response.errors?.first {
            print("Docker query failed: \(error.message)")
        }
        #endif

        return []
    }

    /// Fetches all data at once for efficiency with caching and request deduplication
    func fetchAllData() async throws -> (system: UnraidSystemInfo, array: UnraidArray, containers: [DockerContainer], vms: [VmDomain]) {
        // Check cache first
        if let cached = await cacheManager.getCachedData() {
            return cached
        }

        // Atomically get or create the fetch task (prevents race condition)
        let task = await cacheManager.getOrCreateFetchTask { [self] in
            try await self.performFetchAllData()
        }
        return try await task.value
    }

    /// Internal method that performs the actual fetch
    private func performFetchAllData() async throws -> (system: UnraidSystemInfo, array: UnraidArray, containers: [DockerContainer], vms: [VmDomain]) {
        // Unraid 7.2+ schema with version from vars, fsUsed/fsFree for disks, and metrics for CPU/memory
        // cpu.brand contains the actual CPU name (e.g., "Ryzen 7 2700")
        let query = """
        query {
            vars { version }
            online
            info {
                os { hostname uptime }
                cpu { brand cores }
            }
            metrics {
                cpu { percentTotal }
                memory { total used free available percentTotal }
            }
            array {
                state
                capacity {
                    disks { total used free }
                }
                disks {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                caches {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                parities {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                boot {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
            }
            docker {
                containers {
                    id
                    names
                    image
                    state
                    status
                    autoStart
                }
            }
            vms {
                domains {
                    name
                    uuid
                    state
                }
            }
        }
        """

        struct CombinedResponse: Codable {
            let vars: VarsData
            let online: Bool
            let info: TestInfoData
            let metrics: MetricsData?
            let array: ArrayData
            let docker: DockerData?
            let vms: VmsData?
        }

        struct DockerData: Codable {
            let containers: [ContainerData]?
        }

        let response: GraphQLResponse<CombinedResponse> = try await executeQuery(query)

        guard let data = response.data else {
            if let error = response.errors?.first {
                // If docker query fails, try without it
                #if DEBUG
                print("Combined query failed, trying without docker: \(error.message)")
                #endif
                return try await fetchAllDataWithoutDocker()
            }
            throw UnraidError.noData
        }

        let systemInfo = UnraidSystemInfo(
            hostname: data.info.os.hostname,
            version: data.vars.version,
            uptime: parseUptimeFromBootTime(data.info.os.uptime),
            cpu: UnraidCPU(
                model: data.info.cpu.brand ?? data.info.cpu.model ?? "Unknown",
                cores: data.info.cpu.cores.intValue,
                usage: data.metrics?.cpu?.percentTotal ?? 0,
                temperature: nil
            ),
            memory: UnraidMemory(
                total: data.metrics?.memory?.total ?? 0,
                used: data.metrics?.memory?.used ?? 0,
                free: data.metrics?.memory?.free ?? 0,
                available: data.metrics?.memory?.available,
                percentTotalFromAPI: data.metrics?.memory?.percentTotal
            )
        )
        let array = parseArray(from: data.array)
        let containers = data.docker?.containers?.map { parseContainer(from: $0) } ?? []
        let vms = data.vms?.domains?.map { parseVm(from: $0) } ?? []

        return (systemInfo, array, containers, vms)
    }

    /// Invalidates the cache (call after mutations like start/stop container)
    func invalidateCache() async {
        await cacheManager.invalidateCache()
    }

    /// Fallback method without docker query
    private func fetchAllDataWithoutDocker() async throws -> (system: UnraidSystemInfo, array: UnraidArray, containers: [DockerContainer], vms: [VmDomain]) {
        let query = """
        query {
            vars { version }
            online
            info {
                os { hostname uptime }
                cpu { brand cores }
            }
            metrics {
                cpu { percentTotal }
                memory { total used free available percentTotal }
            }
            array {
                state
                capacity {
                    disks { total used free }
                }
                disks {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                caches {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                parities {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
                boot {
                    id
                    name
                    size
                    fsUsed
                    fsFree
                    status
                    temp
                    type
                    device
                }
            }
            vms {
                domains {
                    name
                    uuid
                    state
                }
            }
        }
        """

        struct SimpleResponse: Codable {
            let vars: VarsData
            let online: Bool
            let info: TestInfoData
            let metrics: MetricsData?
            let array: ArrayData
            let vms: VmsData?
        }

        let response: GraphQLResponse<SimpleResponse> = try await executeQuery(query)

        guard let data = response.data else {
            if let error = response.errors?.first {
                throw UnraidError.graphQLError(error.message)
            }
            throw UnraidError.noData
        }

        let systemInfo = UnraidSystemInfo(
            hostname: data.info.os.hostname,
            version: data.vars.version,
            uptime: parseUptimeFromBootTime(data.info.os.uptime),
            cpu: UnraidCPU(
                model: data.info.cpu.brand ?? data.info.cpu.model ?? "Unknown",
                cores: data.info.cpu.cores.intValue,
                usage: data.metrics?.cpu?.percentTotal ?? 0,
                temperature: nil
            ),
            memory: UnraidMemory(
                total: data.metrics?.memory?.total ?? 0,
                used: data.metrics?.memory?.used ?? 0,
                free: data.metrics?.memory?.free ?? 0,
                available: data.metrics?.memory?.available,
                percentTotalFromAPI: data.metrics?.memory?.percentTotal
            )
        )
        let array = parseArray(from: data.array)
        let vms = data.vms?.domains?.map { parseVm(from: $0) } ?? []

        return (systemInfo, array, [], vms)
    }

    // MARK: - Docker Container Actions

    /// Starts a Docker container
    func startContainer(id: String) async throws {
        // Invalidate cache before mutation
        await invalidateCache()

        let safeId = sanitizeId(id)
        let mutation = """
        mutation {
            docker {
                start(id: "\(safeId)") {
                    id
                    state
                    status
                }
            }
        }
        """

        let _: GraphQLResponse<DockerMutationResponse> = try await executeQuery(mutation)
    }

    /// Stops a Docker container
    func stopContainer(id: String) async throws {
        // Invalidate cache before mutation
        await invalidateCache()

        let safeId = sanitizeId(id)
        let mutation = """
        mutation {
            docker {
                stop(id: "\(safeId)") {
                    id
                    state
                    status
                }
            }
        }
        """

        let _: GraphQLResponse<DockerMutationResponse> = try await executeQuery(mutation)
    }

    /// Restarts a Docker container (stop + start since no direct restart mutation)
    func restartContainer(id: String) async throws {
        // Invalidate cache before mutations
        await invalidateCache()

        // Unraid 7.2 doesn't have a restart mutation, so we stop then start
        try await stopContainer(id: id)
        // Small delay to ensure container is fully stopped
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        try await startContainer(id: id)
    }

    // MARK: - VM Actions

    /// Starts a VM
    func startVm(id: String) async throws {
        await invalidateCache()

        let safeId = sanitizeId(id)
        let mutation = """
        mutation {
            vm {
                start(id: "\(safeId)")
            }
        }
        """

        let _: GraphQLResponse<VmMutationResponse> = try await executeQuery(mutation)
    }

    /// Stops a VM gracefully
    func stopVm(id: String) async throws {
        await invalidateCache()

        let safeId = sanitizeId(id)
        let mutation = """
        mutation {
            vm {
                stop(id: "\(safeId)")
            }
        }
        """

        let _: GraphQLResponse<VmMutationResponse> = try await executeQuery(mutation)
    }

    /// Force stops a VM (like pulling the power)
    func forceStopVm(id: String) async throws {
        await invalidateCache()

        let safeId = sanitizeId(id)
        let mutation = """
        mutation {
            vm {
                forceStop(id: "\(safeId)")
            }
        }
        """

        let _: GraphQLResponse<VmMutationResponse> = try await executeQuery(mutation)
    }

    /// Restarts a VM
    func restartVm(id: String) async throws {
        await invalidateCache()

        let safeId = sanitizeId(id)
        let mutation = """
        mutation {
            vm {
                reboot(id: "\(safeId)")
            }
        }
        """

        let _: GraphQLResponse<VmMutationResponse> = try await executeQuery(mutation)
    }

    /// Pauses a VM
    func pauseVm(id: String) async throws {
        await invalidateCache()

        let safeId = sanitizeId(id)
        let mutation = """
        mutation {
            vm {
                pause(id: "\(safeId)")
            }
        }
        """

        let _: GraphQLResponse<VmMutationResponse> = try await executeQuery(mutation)
    }

    /// Resumes a paused VM
    func resumeVm(id: String) async throws {
        await invalidateCache()

        let safeId = sanitizeId(id)
        let mutation = """
        mutation {
            vm {
                resume(id: "\(safeId)")
            }
        }
        """

        let _: GraphQLResponse<VmMutationResponse> = try await executeQuery(mutation)
    }

    // MARK: - Schema Introspection

    /// Introspects the GraphQL schema to discover available fields
    func introspectSchema(url: String, apiKey: String) async throws -> String {
        guard !url.isEmpty else {
            throw UnraidError.invalidURL
        }

        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let testURL = URL(string: "\(cleanURL)/graphql") else {
            throw UnraidError.invalidURL
        }

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
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }

        throw UnraidError.decodingFailed
    }

    // MARK: - Connection Test

    /// Tests the connection to the Unraid server using the provided URL and API key
    func testConnection(url: String, apiKey: String) async throws -> UnraidSystemInfo {
        guard !url.isEmpty else {
            throw UnraidError.invalidURL
        }

        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let testURL = URL(string: "\(cleanURL)/graphql") else {
            throw UnraidError.invalidURL
        }

        // Unraid 7.2+ schema: version is in vars, uptime is ISO8601 boot timestamp
        // metrics provides real-time CPU and memory usage
        // cpu.brand contains the actual CPU name (e.g., "Ryzen 7 2700")
        let query = """
        query {
            vars { version }
            online
            info {
                os { hostname uptime }
                cpu { brand cores }
            }
            metrics {
                cpu { percentTotal }
                memory { total used free available percentTotal }
            }
        }
        """

        struct TestConnectionResponse: Codable {
            let vars: VarsData
            let online: Bool
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

        return UnraidSystemInfo(
            hostname: data.info.os.hostname,
            version: data.vars.version,
            uptime: parseUptimeFromBootTime(data.info.os.uptime),
            cpu: UnraidCPU(
                model: data.info.cpu.brand ?? data.info.cpu.model ?? "Unknown",
                cores: data.info.cpu.cores.intValue,
                usage: data.metrics?.cpu?.percentTotal ?? 0,
                temperature: nil
            ),
            memory: UnraidMemory(
                total: data.metrics?.memory?.total ?? 0,
                used: data.metrics?.memory?.used ?? 0,
                free: data.metrics?.memory?.free ?? 0,
                available: data.metrics?.memory?.available,
                percentTotalFromAPI: data.metrics?.memory?.percentTotal
            )
        )
    }

    // MARK: - Private Helpers

    private func executeQuery<T: Codable>(_ query: String) async throws -> GraphQLResponse<T> {
        guard let url = getGraphQLURL() else {
            throw UnraidError.notConfigured
        }

        return try await executeQueryWithCredentials(query, url: url, apiKey: getAPIKey())
    }

    private func executeQueryWithCredentials<T: Codable>(
        _ query: String,
        url: URL,
        apiKey: String
    ) async throws -> GraphQLResponse<T> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
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

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnraidError.invalidResponse
        }

        #if DEBUG
        if !(200...299).contains(httpResponse.statusCode) {
            if let responseBody = String(data: data, encoding: .utf8) {
                print("Unraid API Error (\(httpResponse.statusCode)): \(responseBody)")
            }
            print("Request URL: \(url)")
            print("Request Headers: \(request.allHTTPHeaderFields ?? [:])")
        }
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw UnraidError.unauthorized
            }
            throw UnraidError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(GraphQLResponse<T>.self, from: data)
        } catch {
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Failed to decode response: \(jsonString)")
            }
            #endif
            throw UnraidError.decodingFailed
        }
    }

    // MARK: - Parsing Helpers

    private func parseSystemInfo(from data: InfoData) -> UnraidSystemInfo {
        let uptimeSeconds = parseUptime(data.os.uptime)

        let memory: UnraidMemory
        if let mem = data.memory {
            memory = UnraidMemory(
                total: parseBytes(mem.total),
                used: parseBytes(mem.used),
                free: parseBytes(mem.free),
                available: nil,
                percentTotalFromAPI: nil
            )
        } else {
            memory = UnraidMemory(total: 0, used: 0, free: 0, available: nil, percentTotalFromAPI: nil)
        }

        return UnraidSystemInfo(
            hostname: data.os.hostname,
            version: data.os.version ?? "Unknown",
            uptime: uptimeSeconds,
            cpu: UnraidCPU(
                model: data.cpu.model ?? "Unknown",
                cores: data.cpu.cores.intValue,
                usage: 0, // Not provided by basic query
                temperature: nil
            ),
            memory: memory
        )
    }

    private func parseArray(from data: ArrayData) -> UnraidArray {
        // Helper to parse a single disk
        func parseDisk(_ disk: DiskData) -> UnraidDisk {
            let diskSizeKB = Int64(disk.size.intValue)
            let diskSizeBytes = diskSizeKB * 1000  // KB to bytes (SI units)

            // fsUsed is in KB
            let usedBytes = Int64(disk.fsUsed?.intValue ?? 0) * 1000

            return UnraidDisk(
                id: disk.id ?? disk.name,
                name: disk.name,
                size: diskSizeBytes,
                used: usedBytes,
                status: DiskStatus(rawValue: disk.status) ?? .unknown,
                temperature: disk.temp,
                type: parseDiskType(disk.type ?? disk.name),
                device: disk.device,
                serial: disk.serial
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
        let totalBytes = dataDisks.reduce(Int64(0)) { $0 + $1.size }

        // Sum up used from individual data disks for accurate capacity
        let totalUsedBytes = dataDisks.reduce(Int64(0)) { $0 + $1.used }

        // Use API capacity values as fallback (they're in TB)
        let apiUsed = Double(data.capacity.disks.used) ?? 0
        let tbToBytes: Double = 1_000_000_000_000

        // Prefer disk-level data if available, otherwise use API capacity
        let usedBytes = totalUsedBytes > 0 ? totalUsedBytes : Int64(apiUsed * tbToBytes)

        return UnraidArray(
            state: ArrayState(rawValue: data.state) ?? .unknown,
            capacity: ArrayCapacity(
                total: totalBytes,
                used: usedBytes,
                free: totalBytes - usedBytes
            ),
            disks: allDisks,
            parity: nil // Would need additional query for parity status
        )
    }

    private func parseContainer(from data: ContainerData) -> DockerContainer {
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

    private func parseVm(from data: VmDomainData) -> VmDomain {
        return VmDomain(
            id: data.id ?? data.uuid,
            name: data.name,
            uuid: data.uuid,
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

    private func parseBytes(_ bytesString: String) -> Int64 {
        // Handle numeric strings
        if let bytes = Int64(bytesString) {
            return bytes
        }

        // Handle strings like "1.5 TB", "500 GB", "1024 MB"
        let cleanedString = bytesString.trimmingCharacters(in: .whitespaces).uppercased()

        // Use cached regex for efficiency
        guard let regex = Self.bytesRegex,
              let match = regex.firstMatch(in: cleanedString, range: NSRange(cleanedString.startIndex..., in: cleanedString)) else {
            return 0
        }

        guard let numberRange = Range(match.range(at: 1), in: cleanedString),
              let unitRange = Range(match.range(at: 2), in: cleanedString) else {
            return 0
        }

        let numberStr = String(cleanedString[numberRange]).replacingOccurrences(of: ",", with: "")
        guard let number = Double(numberStr) else { return 0 }

        let unit = String(cleanedString[unitRange])

        let multiplier: Double
        switch unit {
        case "KB", "K": multiplier = 1024
        case "MB", "M": multiplier = 1024 * 1024
        case "GB", "G": multiplier = 1024 * 1024 * 1024
        case "TB", "T": multiplier = 1024 * 1024 * 1024 * 1024
        case "PB", "P": multiplier = 1024 * 1024 * 1024 * 1024 * 1024
        default: multiplier = 1
        }

        return Int64(number * multiplier)
    }

    private func parseDiskType(_ typeOrName: String) -> DiskType {
        let lower = typeOrName.lowercased()
        if lower.contains("parity") { return .parity }
        if lower.contains("cache") { return .cache }
        if lower.contains("flash") { return .flash }
        return .data
    }
}

// MARK: - Empty Response for Mutations

private struct EmptyResponse: Codable {}

// MARK: - Error Types

enum UnraidError: LocalizedError {
    case notConfigured
    case invalidURL
    case connectionFailed
    case unauthorized
    case httpError(Int)
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
            return "Invalid API key"
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
