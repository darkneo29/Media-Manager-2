import Foundation
import WatchKit

@MainActor
enum WatchVoiceInput {
    static func requestTitle(completion: @escaping (String?) -> Void) {
        let controller = WKExtension.shared().visibleInterfaceController
            ?? WKExtension.shared().rootInterfaceController

        guard let controller else {
            completion(nil)
            return
        }

        controller.presentTextInputController(
            withSuggestions: [],
            allowedInputMode: .plain
        ) { results in
            let phrase = results?
                .compactMap { $0 as? String }
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            Task { @MainActor in
                completion(phrase?.isEmpty == false ? phrase : nil)
            }
        }
    }
}
