import Foundation

// MARK: - Cached Formatters (shared across all model types)

private enum UnraidFormatters {
    static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useTB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()

    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

// MARK: - System Info

struct UnraidSystemInfo: Codable, Hashable {
    let hostname: String
    let version: String
    let uptime: Int // seconds
    let cpu: UnraidCPU
    let memory: UnraidMemory
}

struct UnraidCPU: Codable, Hashable {
    let model: String
    let cores: Int
    let usage: Double // percentage 0-100
    let temperature: Double? // Celsius
}

struct UnraidMemory: Codable, Hashable {
    let total: Int64 // bytes
    let used: Int64
    let free: Int64
    let available: Int64? // Memory available for applications (excludes cache/buffers)
    let percentTotalFromAPI: Double? // Accurate usage percentage from API

    /// Returns accurate memory usage percentage.
    /// Prefers API-provided percentTotal which accounts for Linux cache/buffer behavior.
    /// Falls back to (total - available) / total if available is present.
    /// Last resort: used / total (can be misleading on Linux).
    nonisolated var usagePercentage: Double {
        // Use API-provided percentage if available (most accurate)
        if let apiPercent = percentTotalFromAPI {
            return apiPercent
        }
        // Calculate from available memory if present
        if let available = available, total > 0 {
            return Double(total - available) / Double(total) * 100
        }
        // Fallback to used/total (can be misleading due to cache)
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    var formattedTotal: String {
        UnraidFormatters.memoryFormatter.string(fromByteCount: total)
    }

    var formattedUsed: String {
        UnraidFormatters.memoryFormatter.string(fromByteCount: used)
    }

    var formattedFree: String {
        UnraidFormatters.memoryFormatter.string(fromByteCount: free)
    }

    var formattedAvailable: String {
        guard let available = available else { return formattedFree }
        return UnraidFormatters.memoryFormatter.string(fromByteCount: available)
    }
}

// MARK: - Array & Disks

struct UnraidArray: Codable, Hashable {
    let state: ArrayState
    let capacity: ArrayCapacity
    let disks: [UnraidDisk]
    let parity: ParityStatus?
}

enum ArrayState: String, Codable, CaseIterable {
    case started = "STARTED"
    case stopped = "STOPPED"
    case starting = "STARTING"
    case stopping = "STOPPING"
    case newArray = "NEW_ARRAY"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ArrayState(rawValue: rawValue) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .started: return "Started"
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .stopping: return "Stopping"
        case .newArray: return "New Array"
        case .unknown: return "Unknown"
        }
    }

    var isOnline: Bool {
        self == .started
    }
}

struct ArrayCapacity: Codable, Hashable {
    let total: Int64
    let used: Int64
    let free: Int64

    nonisolated var usagePercentage: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    var formattedTotal: String {
        UnraidFormatters.byteCountFormatter.string(fromByteCount: total)
    }

    var formattedUsed: String {
        UnraidFormatters.byteCountFormatter.string(fromByteCount: used)
    }

    var formattedFree: String {
        UnraidFormatters.byteCountFormatter.string(fromByteCount: free)
    }
}

struct UnraidDisk: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let size: Int64
    let used: Int64
    let status: DiskStatus
    let temperature: Int?
    let type: DiskType
    let device: String?
    let serial: String?

    nonisolated var usagePercentage: Double {
        guard size > 0 else { return 0 }
        return Double(used) / Double(size) * 100
    }

    var formattedSize: String {
        UnraidFormatters.byteCountFormatter.string(fromByteCount: size)
    }

    var formattedUsed: String {
        UnraidFormatters.byteCountFormatter.string(fromByteCount: used)
    }

    var temperatureColor: TemperatureLevel {
        guard let temp = temperature else { return .unknown }
        if temp < 35 { return .cool }
        if temp < 45 { return .normal }
        if temp < 55 { return .warm }
        return .hot
    }

    enum TemperatureLevel {
        case cool, normal, warm, hot, unknown
    }
}

enum DiskStatus: String, Codable {
    case healthy = "DISK_OK"
    case warning = "DISK_WARN"
    case error = "DISK_ERROR"
    case spunDown = "DISK_SPUN_DOWN"
    case disabled = "DISK_DISABLED"
    case missing = "DISK_NP"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = DiskStatus(rawValue: rawValue) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .error: return "Error"
        case .spunDown: return "Spun Down"
        case .disabled: return "Disabled"
        case .missing: return "Not Present"
        case .unknown: return "Unknown"
        }
    }

    var isHealthy: Bool {
        self == .healthy || self == .spunDown
    }
}

enum DiskType: String, Codable {
    case parity = "Parity"
    case data = "Data"
    case cache = "Cache"
    case flash = "Flash"
    case unknown = "Unknown"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        // Handle variations in API response
        if rawValue.lowercased().contains("parity") {
            self = .parity
        } else if rawValue.lowercased().contains("cache") {
            self = .cache
        } else if rawValue.lowercased().contains("flash") {
            self = .flash
        } else if rawValue.lowercased().contains("data") || rawValue.lowercased().contains("disk") {
            self = .data
        } else {
            self = .unknown
        }
    }
}

struct ParityStatus: Codable, Hashable {
    let valid: Bool
    let lastCheck: Date?
    let inProgress: Bool
    let progress: Double? // 0-100 if in progress
    let speed: Int64? // bytes per second
    let errors: Int?

    var lastCheckFormatted: String? {
        guard let lastCheck = lastCheck else { return nil }
        return UnraidFormatters.relativeDateFormatter.localizedString(for: lastCheck, relativeTo: Date())
    }
}

// MARK: - Docker

struct DockerContainer: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let image: String
    let state: ContainerState
    let status: String
    let autoStart: Bool
    let ports: [String]?
    let cpuUsage: Double?
    let memoryUsage: Int64?

    // Static Set for O(1) media stack lookup
    private static let mediaContainerNames: Set<String> = [
        "radarr", "sonarr", "sabnzbd", "nzbget", "plex", "jellyfin", "emby",
        "lidarr", "readarr", "prowlarr", "bazarr", "overseerr", "tautulli", "ombi"
    ]

    // Static dictionary for O(1) icon lookup (ordered by priority)
    private static let containerIcons: [(keywords: [String], icon: String)] = [
        (["radarr"], "film.fill"),
        (["sonarr"], "tv.fill"),
        (["sabnzbd", "nzbget"], "arrow.down.circle.fill"),
        (["plex", "jellyfin", "emby"], "play.rectangle.fill"),
        (["lidarr"], "music.note"),
        (["readarr"], "book.fill"),
        (["prowlarr"], "magnifyingglass"),
        (["bazarr"], "captions.bubble.fill"),
        (["overseerr", "ombi"], "hand.raised.fill"),
        (["tautulli"], "chart.bar.fill"),
        (["nginx", "traefik"], "network"),
        (["postgres", "mysql", "mariadb"], "cylinder.fill"),
        (["redis"], "memorychip.fill")
    ]

    var displayName: String {
        // Clean up container name (remove leading /)
        name.hasPrefix("/") ? String(name.dropFirst()) : name
    }

    var formattedMemory: String? {
        guard let memory = memoryUsage else { return nil }
        return UnraidFormatters.memoryFormatter.string(fromByteCount: memory)
    }

    var isMediaStack: Bool {
        let lowerName = displayName.lowercased()
        return Self.mediaContainerNames.contains { lowerName.contains($0) }
    }

    var containerIcon: String {
        let lowerName = displayName.lowercased()
        for (keywords, icon) in Self.containerIcons {
            if keywords.contains(where: { lowerName.contains($0) }) {
                return icon
            }
        }
        return "shippingbox.fill"
    }
}

enum ContainerState: String, Codable {
    case running = "running"
    case stopped = "stopped"
    case paused = "paused"
    case restarting = "restarting"
    case exited = "exited"
    case created = "created"
    case dead = "dead"
    case unknown = "unknown"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        self = ContainerState(rawValue: rawValue) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .paused: return "Paused"
        case .restarting: return "Restarting"
        case .exited: return "Exited"
        case .created: return "Created"
        case .dead: return "Dead"
        case .unknown: return "Unknown"
        }
    }

    var isRunning: Bool {
        self == .running
    }
}

// MARK: - Virtual Machines

struct VmDomain: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let uuid: String
    let state: VmState

    // Known VM icons based on name
    private static let vmIcons: [(keywords: [String], icon: String)] = [
        (["hassio", "home assistant", "hass"], "house.fill"),
        (["windows", "win10", "win11"], "desktopcomputer"),
        (["ubuntu", "debian", "linux", "fedora", "centos"], "terminal.fill"),
        (["macos", "mac os", "hackintosh"], "laptopcomputer"),
        (["pfsense", "opnsense", "router"], "network"),
        (["pihole", "adguard"], "shield.fill"),
        (["nextcloud", "cloud"], "cloud.fill"),
        (["minecraft", "game"], "gamecontroller.fill")
    ]

    var displayName: String {
        name
    }

    var vmIcon: String {
        let lowerName = name.lowercased()
        for (keywords, icon) in Self.vmIcons {
            if keywords.contains(where: { lowerName.contains($0) }) {
                return icon
            }
        }
        return "cube.fill" // Default VM icon
    }
}

enum VmState: String, Codable {
    case running = "RUNNING"
    case stopped = "SHUTOFF"
    case paused = "PAUSED"
    case suspended = "PMSUSPENDED"
    case idle = "IDLE"
    case crashed = "CRASHED"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).uppercased()
        self = VmState(rawValue: rawValue) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .paused: return "Paused"
        case .suspended: return "Suspended"
        case .idle: return "Idle"
        case .crashed: return "Crashed"
        case .unknown: return "Unknown"
        }
    }

    var isRunning: Bool {
        self == .running
    }
}

// MARK: - GraphQL Response Models

struct GraphQLResponse<T: Codable>: Codable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Codable {
    let message: String
    let locations: [GraphQLErrorLocation]?
    let path: [String]?
}

struct GraphQLErrorLocation: Codable {
    let line: Int
    let column: Int
}

// MARK: - Unraid 7.2+ Response Models

/// Full system info response for Unraid 7.2+
struct SystemInfoResponse: Codable {
    let vars: VarsData
    let online: Bool
    let info: TestInfoData
}

/// Vars data containing version
struct VarsData: Codable {
    let version: String
}

/// Docker mutation response
struct DockerMutationResponse: Codable {
    let docker: DockerMutationResult
}

struct DockerMutationResult: Codable {
    let start: ContainerMutationResult?
    let stop: ContainerMutationResult?
}

struct ContainerMutationResult: Codable {
    let id: String
    let state: String
    let status: String
}

// Info query response (full)
struct InfoQueryResponse: Codable {
    let info: InfoData
}

struct InfoData: Codable {
    let os: OSInfo
    let cpu: CPUInfo
    let memory: MemoryInfo?
}

struct OSInfo: Codable {
    let hostname: String
    let version: String?
    let uptime: String
}

struct CPUInfo: Codable {
    let model: String?
    let brand: String?  // Contains actual CPU name (e.g., "Ryzen 7 2700")
    let cores: IntOrString

    // Handle cores being either Int or String from API
    enum IntOrString: Codable {
        case int(Int)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) {
                self = .int(intVal)
            } else if let strVal = try? container.decode(String.self) {
                self = .string(strVal)
            } else {
                self = .int(0)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let val): try container.encode(val)
            case .string(let val): try container.encode(val)
            }
        }

        var intValue: Int {
            switch self {
            case .int(let val): return val
            case .string(let val): return Int(val) ?? 0
            }
        }
    }
}

struct MemoryInfo: Codable {
    let total: String
    let used: String
    let free: String
}

// Simplified test response (for connection testing)
struct TestInfoResponse: Codable {
    let info: TestInfoData
}

struct TestInfoData: Codable {
    let os: TestOSInfo
    let cpu: CPUInfo
}

struct TestOSInfo: Codable {
    let hostname: String
    let uptime: String
}

// Array query response
struct ArrayQueryResponse: Codable {
    let array: ArrayData
}

struct ArrayData: Codable {
    let state: String
    let capacity: CapacityData
    let disks: [DiskData]
    let caches: [DiskData]?
    let parities: [DiskData]?
    let boot: DiskData?
}

struct CapacityData: Codable {
    let disks: DiskCapacity
}

struct DiskCapacity: Codable {
    let total: String
    let used: String
    let free: String
}

struct DiskData: Codable {
    let id: String?
    let name: String
    let size: IntOrString
    let fsUsed: IntOrString?  // Unraid 7.2+: filesystem used space in KB
    let fsFree: IntOrString?  // Unraid 7.2+: filesystem free space in KB
    let status: String
    let temp: Int?
    let type: String?
    let device: String?
    let serial: String?

    // Reuse IntOrString from CPUInfo for size field
    typealias IntOrString = CPUInfo.IntOrString
}

// Docker query response
struct DockerQueryResponse: Codable {
    let dockerContainers: [ContainerData]
}

struct ContainerData: Codable {
    let id: String
    let names: [String]?
    let name: String?
    let image: String
    let state: String
    let status: String
    let autoStart: Bool?
}

// MARK: - VM Response Models

struct VmsData: Codable {
    let domains: [VmDomainData]?
}

struct VmDomainData: Codable {
    let id: String?
    let name: String
    let uuid: String
    let state: String
}

/// VM mutation response
struct VmMutationResponse: Codable {
    let vm: VmMutationResult
}

struct VmMutationResult: Codable {
    let start: Bool?
    let stop: Bool?
    let forceStop: Bool?
    let reboot: Bool?
    let pause: Bool?
    let resume: Bool?
}

// MARK: - Metrics Response Models (CPU/Memory usage)

struct MetricsData: Codable {
    let cpu: CpuUtilization?
    let memory: MemoryUtilization?
}

struct CpuUtilization: Codable {
    let percentTotal: Double
}

struct MemoryUtilization: Codable {
    let total: Int64
    let used: Int64
    let free: Int64
    let available: Int64?
    let percentTotal: Double?
}

// MARK: - Uptime Formatting Helper

extension UnraidSystemInfo {
    var formattedUptime: String {
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let minutes = (uptime % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
