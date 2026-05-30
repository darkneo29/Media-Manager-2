import Foundation

// MARK: - SabNZB Error Types

enum SabNZBError: LocalizedError {
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return message
        }
    }
}

class SabNZBService {
    static let shared = SabNZBService()

    private let config = ConfigurationManager.shared

    private var baseURL: String {
        config.sabnzbURL
    }

    private var apiKey: String {
        config.sabnzbAPIKey
    }

    private init() {}

    // MARK: - Request Helpers

    /// Creates an authenticated URLRequest for SabNZB with API key header and timeout
    private func authenticatedRequest(url: URL, apiKey: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(apiKey ?? self.apiKey, forHTTPHeaderField: "X-Api-Key")
        return request
    }

    /// Builds a SabNZB API URL with mode and optional extra params (keeps output=json, moves apikey to header)
    private func sabURL(base: String? = nil, mode: String, extraParams: [(String, String)] = []) -> URL? {
        let apiBase = base ?? baseURL
        var components = URLComponents(string: "\(apiBase)/api")
        var queryItems = [URLQueryItem(name: "mode", value: mode), URLQueryItem(name: "output", value: "json")]
        for (key, value) in extraParams {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    /// Checks the SabNZB response for "status": false and throws the error message
    private func checkSabNZBResponse(_ data: Data) throws {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? Bool, !status {
            let errorMessage = json["error"] as? String ?? "Unknown SabNZB error"
            throw SabNZBError.apiError(errorMessage)
        }
    }

    // MARK: - Connection Testing

    /// Tests the connection to the SabNZB server using the provided URL and API key
    func testConnection(url: String, apiKey: String) async throws {
        guard let testURL = sabURL(base: url, mode: "version") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: testURL, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    // MARK: - Queue Operations

    /// Fetches the current download queue from SabNZB
    func fetchQueue() async throws -> DownloadQueue {
        guard let url = sabURL(mode: "queue") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)

        let sabResponse = try JSONDecoder().decode(SabNZBQueueResponse.self, from: data)
        return convertToDownloadQueue(sabResponse)
    }

    /// Fetches the download history from SabNZB
    func fetchHistory() async throws -> [HistoryDownload] {
        guard let url = sabURL(mode: "history") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)

        let sabResponse = try JSONDecoder().decode(SabNZBHistoryResponse.self, from: data)
        return convertToHistoryDownloads(sabResponse)
    }

    // MARK: - Individual Download Operations

    /// Pauses a specific download
    func pauseDownload(id: String) async throws {
        guard let url = sabURL(mode: "queue", extraParams: [("name", "pause"), ("value", id)]) else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    /// Resumes a paused download
    func resumeDownload(id: String) async throws {
        guard let url = sabURL(mode: "queue", extraParams: [("name", "resume"), ("value", id)]) else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    /// Deletes a download from the queue
    func deleteDownload(id: String) async throws {
        guard let url = sabURL(mode: "queue", extraParams: [("name", "delete"), ("value", id), ("del_files", "1")]) else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    // MARK: - History Operations

    /// Deletes a history item
    func deleteHistoryItem(id: String) async throws {
        guard let url = sabURL(mode: "history", extraParams: [("name", "delete"), ("value", id)]) else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    /// Clears all history
    func clearHistory() async throws {
        guard let url = sabURL(mode: "history", extraParams: [("name", "delete"), ("value", "all")]) else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    // MARK: - Warnings/Logs Operations

    /// Fetches current warnings from SabNZB
    func fetchWarnings(url: String, apiKey: String) async throws -> [SabNZBWarning] {
        guard let requestURL = sabURL(base: url, mode: "warnings") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: requestURL, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)

        let warningsResponse = try JSONDecoder().decode(SabNZBWarningsResponse.self, from: data)
        return warningsResponse.warnings.map { warning in
            SabNZBWarning(
                id: UUID().uuidString,
                type: warning.type,
                text: warning.text,
                time: warning.time
            )
        }
    }

    /// Clears all warnings from SabNZB
    func clearWarnings(url: String, apiKey: String) async throws {
        guard let requestURL = sabURL(base: url, mode: "warnings", extraParams: [("name", "clear")]) else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: requestURL, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    // MARK: - Global Queue Operations

    /// Pauses the entire download queue
    func pauseQueue() async throws {
        guard let url = sabURL(mode: "pause") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    /// Resumes the entire download queue
    func resumeQueue() async throws {
        guard let url = sabURL(mode: "resume") else {
            throw URLError(.badURL)
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try checkSabNZBResponse(data)
    }

    // MARK: - Conversion Helpers

    private func convertToDownloadQueue(_ response: SabNZBQueueResponse) -> DownloadQueue {
        let queueData = response.queue

        // Parse speed limit (could be empty, "0", or a number)
        let speedLimit: Int? = {
            guard let value = Int(queueData.speedlimit), value > 0 else { return nil }
            return value
        }()

        // Parse current speed in bytes/sec
        let speedBytesPerSec: Int64 = {
            if let kbps = Double(queueData.kbpersec) {
                return Int64(kbps * 1024)
            }
            return 0
        }()

        let downloads = queueData.slots.map { slot -> Download in
            let progress = Double(slot.percentage) ?? 0
            let totalMB = Double(slot.mb) ?? 0
            let leftMB = Double(slot.mbleft) ?? 0
            let totalBytes = Int64(totalMB * 1024 * 1024)
            let leftBytes = Int64(leftMB * 1024 * 1024)

            return Download(
                id: slot.nzo_id,
                name: slot.filename,
                category: slot.cat,
                status: DownloadStatus(from: slot.status),
                progress: progress,
                size: totalBytes,
                sizeLeft: leftBytes,
                timeLeft: slot.timeleft,
                speed: speedBytesPerSec
            )
        }

        return DownloadQueue(
            paused: queueData.paused,
            speedLimit: speedLimit,
            speed: speedBytesPerSec,
            downloads: downloads
        )
    }

    private func convertToHistoryDownloads(_ response: SabNZBHistoryResponse) -> [HistoryDownload] {
        return response.history.slots.map { slot in
            let completedDate: Date? = slot.completed > 0 ? Date(timeIntervalSince1970: Double(slot.completed)) : nil

            return HistoryDownload(
                id: slot.nzo_id,
                name: slot.name,
                category: slot.category,
                status: DownloadStatus(from: slot.status),
                size: slot.bytes,
                completedAt: completedDate,
                downloadTime: slot.download_time,
                failMessage: slot.fail_message
            )
        }
    }
}
