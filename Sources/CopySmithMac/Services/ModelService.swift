import Foundation
import FoundationModels

struct ModelService: Sendable {
    func fetchModels() async throws -> [String] {
        guard case .available = SystemLanguageModel.default.availability else {
            throw ChatError.apiError(
                "Apple Intelligence is not available. Please enable it in System Settings > Apple Intelligence & Siri."
            )
        }
        return ["apple-intelligence"]
    }
}
