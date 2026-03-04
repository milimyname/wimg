import Foundation

struct ClaudeResult {
    let categorized: Int
    let errors: [String]
}

/// Claude API integration for iOS — mirrors wimg-web/src/lib/claude.ts
enum ClaudeAPI {
    private static let storageKey = "wimg_claude_api_key"
    private static let apiURL = "https://api.anthropic.com/v1/messages"

    static var hasKey: Bool {
        getKey() != nil
    }

    static func getKey() -> String? {
        UserDefaults.standard.string(forKey: storageKey)
    }

    static func setKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: storageKey)
    }

    static func removeKey() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Build category list string for the prompt.
    private static func categoryList() -> String {
        WimgCategory.allCases
            .filter { $0.rawValue != 0 && $0.rawValue != 255 }
            .map { "\($0.rawValue): \($0.name)" }
            .joined(separator: "\n")
    }

    /// Build name→id map for parsing Claude's response.
    private static func nameToId() -> [String: Int] {
        var map: [String: Int] = [:]
        for cat in WimgCategory.allCases {
            map[cat.name.lowercased()] = cat.rawValue
        }
        return map
    }

    /// Categorize uncategorized transactions via Claude API.
    static func categorize(transactions: [Transaction]) async -> ClaudeResult {
        guard let apiKey = getKey(), !apiKey.isEmpty else {
            return ClaudeResult(categorized: 0, errors: ["Kein API-Key konfiguriert"])
        }

        let uncategorized = transactions.filter { $0.category == 0 }
        if uncategorized.isEmpty {
            return ClaudeResult(categorized: 0, errors: [])
        }

        let batchSize = 50
        let map = nameToId()
        var totalCategorized = 0
        var errors: [String] = []

        for batchStart in stride(from: 0, to: uncategorized.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, uncategorized.count)
            let batch = Array(uncategorized[batchStart..<batchEnd])

            let descriptions = batch.enumerated().map { idx, tx in
                let sign = tx.amount > 0 ? "+" : ""
                return "\(idx + 1). \"\(tx.description)\" (\(sign)\(String(format: "%.2f", tx.amount))€)"
            }.joined(separator: "\n")

            let prompt = """
            You are a personal finance categorizer for a German bank account. Categorize each transaction into exactly one category.

            Available categories:
            \(categoryList())

            Transactions to categorize:
            \(descriptions)

            Respond with ONLY a JSON array of objects, one per transaction, in order:
            [{"index": 1, "category": "Category Name"}, ...]

            Use the exact category names from the list above. If unsure, use "Sonstiges".
            """

            do {
                let result = try await callAPI(apiKey: apiKey, prompt: prompt)
                guard let jsonMatch = result.range(of: #"\[[\s\S]*\]"#, options: .regularExpression) else {
                    errors.append("Batch \(batchStart / batchSize + 1): Antwort konnte nicht geparst werden")
                    continue
                }

                let jsonString = String(result[jsonMatch])
                guard let data = jsonString.data(using: .utf8) else { continue }

                struct CatResult: Decodable {
                    let index: Int
                    let category: String
                }

                let results = try JSONDecoder().decode([CatResult].self, from: data)

                for cat in results {
                    let idx = cat.index - 1
                    guard idx >= 0, idx < batch.count else { continue }
                    if let catId = map[cat.category.lowercased()], catId != 0 {
                        try? LibWimg.setCategory(id: batch[idx].id, category: UInt8(catId))
                        totalCategorized += 1
                    }
                }
            } catch {
                if error.localizedDescription.contains("401") {
                    errors.append("Ungültiger API-Key")
                    break
                }
                errors.append("Batch \(batchStart / batchSize + 1): \(error.localizedDescription)")
            }
        }

        return ClaudeResult(categorized: totalCategorized, errors: errors)
    }

    private static func callAPI(apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: apiURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode != 200 {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "ClaudeAPI",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API error \(httpResponse.statusCode): \(String(text.prefix(100)))"]
            )
        }

        struct APIResponse: Decodable {
            struct Content: Decodable {
                let text: String?
            }
            let content: [Content]?
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        return apiResponse.content?.first?.text ?? ""
    }
}
