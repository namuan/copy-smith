import Foundation

struct ModelService: Sendable {
    let endpoint: URL
    let timeout: TimeInterval

    init(
        endpoint: URL = URL(string: "http://localhost:2276/v1/models")!,
        timeout: TimeInterval = 10
    ) {
        self.endpoint = endpoint
        self.timeout = timeout
    }

    func fetchModels() async throws -> [String] {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)

        let (data, _) = try await session.data(from: endpoint)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArray = json["data"] as? [[String: Any]]
        else {
            throw URLError(.badServerResponse)
        }

        return dataArray.compactMap { $0["id"] as? String }
    }
}
