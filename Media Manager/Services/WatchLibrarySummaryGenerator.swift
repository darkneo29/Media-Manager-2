#if os(iOS)
import FoundationModels

@available(iOS 27.0, *)
enum WatchLibrarySummaryGenerator {
    static func summarize(_ facts: String) async -> String {
        guard SystemLanguageModel.default.isAvailable else { return facts }
        do {
            let session = LanguageModelSession(instructions: "Rewrite the supplied facts as two short sentences for Apple Watch. Preserve every count and any stale-data warning. Never invent facts or claim an action was performed.")
            let response = try await session.respond(to: facts, options: GenerationOptions(maximumResponseTokens: 160))
            return response.content
        } catch {
            return facts
        }
    }
}
#endif
