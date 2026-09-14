import Foundation

extension UnraidService {
    enum RefreshInterval {
        static let hardware: TimeInterval = 300
        static let metrics: TimeInterval = 10
        static let storage: TimeInterval = 30
        static let containers: TimeInterval = 15
        static let vms: TimeInterval = 15
        static let disks: TimeInterval = 120
        static let capabilities: TimeInterval = 600
        static let parity: TimeInterval = 30
    }

    static let hardwareQuery = "query Hardware { vars { version } info { os { hostname uptime } cpu { brand cores } } }"
    static let metricsQuery = "query Metrics { metrics { cpu { percentTotal } memory { total used free available percentTotal } } }"
    static let storageQuery = "query Storage { array { state capacity { kilobytes { total used free } } } }"
    static let containerSummaryQuery = "query ContainerSummary { docker { containers { id state } } }"
    static let schemaQuery = "query Capabilities { __schema { types { name fields { name } } } }"
    static let permissionsQuery = "query Permissions { me { roles permissions { resource actions } } }"
    static let apiVersionQuery = "query ApiVersion { info { versions { core { api } } } }"
    static let parityQuery = "query Parity { array { parityCheckStatus { status date duration speed errors progress running paused } } }"
    static let logsQuery = "query ContainerLogs($id: PrefixedID!) { docker { logs(id: $id, tail: 200) { containerId lines { timestamp message } cursor } } }"
    static let statsQuery = "subscription ContainerStats { dockerContainerStats { id cpuPercent memUsage memPercent netIO blockIO } }"

    nonisolated struct HardwareResponse: Codable { let vars: VarsData; let info: TestInfoData }
    nonisolated struct MetricsResponse: Codable { let metrics: MetricsData? }
    nonisolated struct StorageResponse: Codable {
        struct ArraySummary: Codable { let state: String; let capacity: CapacityData }
        let array: ArraySummary
    }
    nonisolated struct SummaryResponse: Codable {
        struct Docker: Codable { let containers: [UnraidContainerSummary] }
        let docker: Docker
    }
    nonisolated struct ContainersResponse: Codable {
        struct Docker: Codable { let containers: [ContainerData] }
        let docker: Docker
    }
    nonisolated struct VMsResponse: Codable { let vms: VmsData }
    nonisolated struct SchemaResponse: Codable { let __schema: UnraidSchema }
    nonisolated struct PermissionsResponse: Codable { let me: UnraidIdentity }
    nonisolated struct APIVersionResponse: Codable {
        struct Info: Codable {
            struct Versions: Codable {
                struct Core: Codable { let api: String? }
                let core: Core
            }
            let versions: Versions
        }
        let info: Info
    }
    nonisolated struct ParityResponse: Codable {
        struct Array: Codable { let parityCheckStatus: UnraidParityCheck }
        let array: Array
    }
    nonisolated struct LogsResponse: Codable {
        struct Docker: Codable { let logs: UnraidContainerLogs }
        let docker: Docker
    }

    func readSection<T: Codable>(_ type: T.Type, name: String, query: String, ttl: TimeInterval,
                                force: Bool, context: UnraidConnection, variables: [String: String] = [:]) async throws -> UnraidSection<T> {
        let task = await readCache.task(key: name, connection: context, ttl: ttl, force: force, now: readClock(), clock: { await self.readClock() }) { [self] in
            let response: GraphQLResponse<T> = try await executeQuery(query, variables: variables, context: context)
            guard let value = response.data else { throw UnraidError.noData }
            return try JSONEncoder().encode(value)
        }
        do {
            let result = try await task.value
            try Task.checkCancellation()
            guard try requestContext() == context else { throw CancellationError() }
            return UnraidSection(value: try JSONDecoder().decode(T.self, from: result.data), updatedAt: result.updatedAt)
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            guard try requestContext() == context else { throw CancellationError() }
            let previous = await readCache.previous(key: name, connection: context)
            return UnraidSection(value: previous.flatMap { try? JSONDecoder().decode(T.self, from: $0.data) },
                                 updatedAt: previous?.updatedAt, error: error.localizedDescription)
        }
    }

    func fetchOverview(forceRefresh: Bool = false, includeContainers: Bool = true) async throws -> UnraidOverview {
        let context = try requestContext()
        async let hardware = readSection(HardwareResponse.self, name: "hardware", query: Self.hardwareQuery,
                                         ttl: RefreshInterval.hardware, force: forceRefresh, context: context)
        async let metrics = readSection(MetricsResponse.self, name: "metrics", query: Self.metricsQuery,
                                        ttl: RefreshInterval.metrics, force: forceRefresh, context: context)
        async let storage = readSection(StorageResponse.self, name: "storage", query: Self.storageQuery,
                                        ttl: RefreshInterval.storage, force: forceRefresh, context: context)
        async let containers = summarySection(include: includeContainers, force: forceRefresh, context: context)
        let (h, m, s, c) = try await (hardware, metrics, storage, containers)
        let system = h.map { parseSystemInfo(info: $0.info, version: $0.vars.version, metrics: m.error == nil ? m.value?.metrics : nil) }
        var metricSection = m.compactMap { $0.metrics }
        if metricSection.value == nil && metricSection.error == nil { metricSection.error = "Metrics are not available from this server." }
        return UnraidOverview(system: system, metrics: metricSection,
                              storage: s.map { value in
                                  parseArray(from: ArrayData(state: value.array.state, capacity: value.array.capacity,
                                                           disks: [], caches: nil, parities: nil, boot: nil))
                              }, containers: c)
    }

    private func summarySection(include: Bool, force: Bool, context: UnraidConnection) async throws -> UnraidSection<[UnraidContainerSummary]> {
        guard include else { return UnraidSection() }
        let result = try await readSection(SummaryResponse.self, name: "containerSummary", query: Self.containerSummaryQuery,
                                           ttl: RefreshInterval.containers, force: force, context: context)
        return result.map { $0.docker.containers }
    }

    func fetchCapabilities(forceRefresh: Bool = false) async throws -> UnraidCapabilities {
        let context = try requestContext()
        async let schema = readSection(SchemaResponse.self, name: "schema", query: Self.schemaQuery,
                                       ttl: RefreshInterval.capabilities, force: forceRefresh, context: context)
        async let permissions = readSection(PermissionsResponse.self, name: "permissions", query: Self.permissionsQuery,
                                            ttl: RefreshInterval.capabilities, force: forceRefresh, context: context)
        let (s, p) = try await (schema, permissions)
        var result = UnraidCapabilities(schema: s.error == nil ? s.value?.__schema : nil,
                                        identity: p.error == nil ? p.value?.me : nil)
        if let error = s.error { result.issues.append("Schema discovery: \(error)") }
        if let error = p.error { result.issues.append("Permission discovery: \(error)") }
        if result.schema?.supports("CoreVersions", "api") != false {
            let version = try await readSection(APIVersionResponse.self, name: "apiVersion", query: Self.apiVersionQuery,
                                                 ttl: RefreshInterval.capabilities, force: forceRefresh, context: context)
            result.apiVersion = version.value?.info.versions.core.api
            if let error = version.error { result.issues.append("API version: \(error)") }
        }
        guard try requestContext() == context else { throw CancellationError() }
        if forceRefresh || result.schema?.supports("DockerMutations", "restart") == true { absentRestart.remove(context) }
        capabilityState = (context, result)
        return result
    }

    func fetchDetails(forceRefresh: Bool = false) async throws -> UnraidDetailSnapshot {
        let context = try requestContext()
        async let overview = fetchOverview(forceRefresh: forceRefresh, includeContainers: false)
        async let disks = readSection(ArrayQueryResponse.self, name: "disks", query: "query Disks { \(Self.arrayFields) }",
                                      ttl: RefreshInterval.disks, force: forceRefresh, context: context)
        async let containers = readSection(ContainersResponse.self, name: "containers", query: "query Containers { \(Self.dockerFields) }",
                                           ttl: RefreshInterval.containers, force: forceRefresh, context: context)
        async let vms = readSection(VMsResponse.self, name: "vms", query: "query VMs { \(Self.vmFields) }",
                                    ttl: RefreshInterval.vms, force: forceRefresh, context: context)
        async let capabilities = fetchCapabilities(forceRefresh: forceRefresh)
        let (o, d, c, v, caps) = try await (overview, disks, containers, vms, capabilities)
        var finalOverview = o
        finalOverview.containers = c.map { $0.docker.containers.map { UnraidContainerSummary(id: $0.id, state: ContainerState(rawValue: $0.state.lowercased()) ?? .unknown) } }
        let parity = try await fetchParity(capabilities: caps, force: forceRefresh, context: context)
        var vmSection = v.compactMap { $0.vms.domains?.map { parseVm(from: $0) } }
        if vmSection.value == nil && vmSection.error == nil { vmSection.error = "VM service did not return a domain list." }
        return UnraidDetailSnapshot(overview: finalOverview, disks: d.map { parseArray(from: $0.array) },
                                    containers: c.map { $0.docker.containers.map { parseContainer(from: $0) } },
                                    vms: vmSection,
                                    parity: parity, capabilities: caps)
    }

    private func fetchParity(capabilities: UnraidCapabilities, force: Bool, context: UnraidConnection) async throws -> UnraidSection<UnraidParityCheck> {
        let access = capabilities.access(resource: "ARRAY", type: "UnraidArray", field: "parityCheckStatus")
        guard access.permitsAttempt else { return .unavailable(access.explanation ?? "Parity status unavailable") }
        let result = try await readSection(ParityResponse.self, name: "parity", query: Self.parityQuery,
                                           ttl: RefreshInterval.parity, force: force, context: context)
        return result.map { $0.array.parityCheckStatus }
    }

    func fetchContainerLogs(id: String, forceRefresh: Bool = false) async throws -> UnraidSection<UnraidContainerLogs> {
        let context = try requestContext()
        let caps = try await fetchCapabilities()
        let access = caps.access(resource: "DOCKER", type: "Docker", field: "logs")
        guard access.permitsAttempt else { return .unavailable(access.explanation ?? "Logs unavailable") }
        let result = try await readSection(LogsResponse.self, name: "logs:\(id)", query: Self.logsQuery,
                                           ttl: 5, force: forceRefresh, context: context, variables: ["id": id])
        return result.map { $0.docker.logs }
    }

    static func retryAfter(_ response: HTTPURLResponse, now: Date) -> TimeInterval {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return 30 }
        if let seconds = Double(header), seconds.isFinite { return max(1, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: header).map { max(1, $0.timeIntervalSince(now)) } ?? 30
    }
}

extension UnraidSection {
    func map<NewValue>(_ transform: (Value) -> NewValue) -> UnraidSection<NewValue> {
        UnraidSection<NewValue>(value: value.map(transform), updatedAt: updatedAt, error: error)
    }
    func compactMap<NewValue>(_ transform: (Value) -> NewValue?) -> UnraidSection<NewValue> {
        UnraidSection<NewValue>(value: value.flatMap(transform), updatedAt: updatedAt, error: error)
    }
}
