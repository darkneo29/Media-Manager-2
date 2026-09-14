import Foundation

/// A failed section may retain its last value, but never loses the failure or its age.
struct UnraidSection<Value> {
    var value: Value?
    var updatedAt: Date?
    var error: String?
    var connectionUnavailable = false
    var isStale: Bool { value != nil && error != nil }
    static func unavailable(_ message: String) -> Self { Self(error: message) }
}

nonisolated struct UnraidContainerSummary: Codable, Hashable {
    let id: String
    let state: ContainerState
}

struct UnraidOverview {
    var system: UnraidSection<UnraidSystemInfo>
    var metrics: UnraidSection<MetricsData>
    var storage: UnraidSection<UnraidArray>
    var containers: UnraidSection<[UnraidContainerSummary]>

    var connectionUnavailable: Bool {
        system.connectionUnavailable || metrics.connectionUnavailable || storage.connectionUnavailable || containers.connectionUnavailable
    }

    var errors: [String] {
        [("System", system.error), ("Metrics", metrics.error), ("Storage", storage.error), ("Containers", containers.error)]
            .compactMap { name, error in error.map { "\(name): \($0)" } }
    }

    /// Shared with Siri so unavailable sections are never reported as zero or healthy.
    var spokenSummary: String {
        var parts: [String] = []
        if let system = system.value {
            parts.append("\(system.hostname). Uptime: \(system.formattedUptime).")
            if self.system.isStale { parts.append("System information is out of date.") }
        } else { parts.append("System information unavailable.") }
        if metrics.error == nil, let metrics = metrics.value {
            let cpu = (metrics.cpu?.percentTotal).map { min(100, max(0, $0)) }
            parts.append("CPU: \(cpu.map { "\(Int($0))%" } ?? "unavailable").")
            if let memory = metrics.memory, memory.total > 0 {
                let value = UnraidMemory(total: memory.total, used: memory.used, free: memory.free,
                                         available: memory.available, percentTotalFromAPI: memory.percentTotal)
                parts.append("Memory: \(Int(value.usagePercentage))%.")
            } else { parts.append("Memory unavailable.") }
        } else { parts.append("CPU and memory metrics unavailable.") }
        if let storage = storage.value, self.storage.error == nil {
            parts.append("Array: \(storage.state.displayName). Storage: \(storage.capacity.formattedUsed) of \(storage.capacity.formattedTotal).")
        } else { parts.append("Storage status unavailable.") }
        if let containers = containers.value, self.containers.error == nil {
            parts.append("Containers: \(containers.filter { $0.state.isRunning }.count) of \(containers.count) running.")
        } else { parts.append("Container status unavailable.") }
        return parts.joined(separator: " ")
    }
}

nonisolated struct UnraidPermission: Codable, Hashable {
    let resource: String
    let actions: [String]
}

nonisolated struct UnraidIdentity: Codable {
    let roles: [String]
    let permissions: [UnraidPermission]?
}

nonisolated struct UnraidSchema: Codable {
    struct Field: Codable { let name: String }
    struct SchemaType: Codable { let name: String; let fields: [Field]? }
    let types: [SchemaType]
    func supports(_ type: String, _ field: String) -> Bool {
        types.first { $0.name == type }?.fields?.contains { $0.name == field } == true
    }
}

enum UnraidAccess: Equatable {
    case allowed, denied, unsupported, unknown
    var permitsAttempt: Bool { self == .allowed || self == .unknown }
    var explanation: String? {
        switch self {
        case .allowed: return nil
        case .denied: return "The API key does not grant access. Update its permissions in Unraid settings."
        case .unsupported: return "This API version does not support this feature."
        case .unknown: return "Access could not be verified. The server will check each request."
        }
    }
}

struct UnraidCapabilities {
    var schema: UnraidSchema?
    var identity: UnraidIdentity?
    var apiVersion: String?
    var issues: [String] = []

    func access(resource: String, action: String = "READ_ANY", type: String, field: String) -> UnraidAccess {
        if let schema, !schema.supports(type, field) { return .unsupported }
        guard let identity else { return .unknown }
        if identity.roles.contains("ADMIN") { return .allowed }
        if identity.permissions?.contains(where: { $0.resource == resource && $0.actions.contains(action) }) == true { return .allowed }
        if action == "READ_ANY", identity.roles.contains("VIEWER") { return .allowed }
        // Unknown/custom inherited roles must not be treated as an authoritative denial.
        if identity.roles.contains(where: { !["VIEWER", "GUEST"].contains($0) }) { return .unknown }
        return identity.permissions == nil ? .unknown : .denied
    }

    func dockerAction(_ action: String) -> UnraidAccess {
        let native = access(resource: "DOCKER", action: "UPDATE_ANY", type: "DockerMutations", field: action)
        if action == "restart", native == .unsupported {
            let start = dockerAction("start"), stop = dockerAction("stop")
            if start == .allowed && stop == .allowed { return .allowed }
            if start == .denied || stop == .denied { return .denied }
            if start == .unsupported || stop == .unsupported { return .unsupported }
            return .unknown
        }
        return native
    }
    func vmAction(_ action: String) -> UnraidAccess {
        access(resource: "VMS", action: "UPDATE_ANY", type: "VmMutations", field: action)
    }
}

nonisolated struct UnraidParityCheck: Codable {
    let status: String
    let date: String?
    let duration: Int?
    let speed: String?
    let errors: Int?
    let progress: Int?
    let running: Bool?
    let paused: Bool?
}

nonisolated struct UnraidContainerLogs: Codable {
    struct Line: Codable { let timestamp: String; let message: String }
    let containerId: String
    let lines: [Line]
    let cursor: String?
}

nonisolated struct UnraidContainerStats: Codable {
    let id: String
    let cpuPercent: Double
    let memUsage: String
    let memPercent: Double
    let netIO: String
    let blockIO: String
}

struct UnraidDetailSnapshot {
    var overview: UnraidOverview
    var disks: UnraidSection<UnraidArray>
    var containers: UnraidSection<[DockerContainer]>
    var vms: UnraidSection<[VmDomain]>
    var parity: UnraidSection<UnraidParityCheck>
    var capabilities: UnraidCapabilities
}

enum UnraidVMCommandResult: Equatable {
    case verified
    case unverified(String)
}

/// A running sample alone cannot prove that a reboot happened.
struct UnraidVMVerification {
    let action: String
    var sawRebootTransition = false
    mutating func observe(_ state: VmState) -> Bool {
        switch action {
        case "stop", "forceStop": return state == .stopped
        case "pause": return state == .paused
        case "start", "resume": return state == .running
        case "reboot":
            if state == .shuttingDown || state == .stopped { sawRebootTransition = true }
            return sawRebootTransition && state == .running
        default: return false
        }
    }
}
