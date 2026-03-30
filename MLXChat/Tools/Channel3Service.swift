import Foundation

// MARK: - Channel3 Models

struct Channel3Price: Sendable {
    let currency: String?
    let amount: String?
}

struct Channel3Product: Sendable {
    let id: String
    let title: String
    let description: String?
    let price: Channel3Price?
    let url: String?
    let imageURL: String?
    let brandName: String?

    var formattedPrice: String? {
        guard let p = price, let a = p.amount else { return nil }
        return "\(p.currency ?? "USD") \(a)"
    }

    func toSearchResult() -> SearchResult {
        SearchResult(
            title: title,
            description: description ?? "",
            url: url ?? "",
            thumbnailURL: imageURL,
            siteName: brandName,
            price: formattedPrice
        )
    }
}

// MARK: - Codable (manual, tolerant decoding)

extension Channel3Product: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)

        id    = c.stringOrNil("id") ?? UUID().uuidString
        title = c.stringOrNil("title") ?? c.stringOrNil("name") ?? "Unknown Product"
        description = c.stringOrNil("description")
        url         = c.stringOrNil("url")
        imageURL    = c.stringOrNil("image_url") ?? c.stringOrNil("imageUrl") ?? c.stringOrNil("imageURL")
        brandName   = c.stringOrNil("brand_name")
            ?? c.stringOrNil("brandName")
            ?? c.stringOrNil("brand")
            ?? c.stringOrNil("merchant")

        // price: nested object { currency, price/amount/value } OR flat string/number
        if let sub = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .init("price")) {
            let currency = sub.stringOrNil("currency")
            let amount   = sub.stringOrNil("price")
                ?? sub.stringOrNil("amount")
                ?? sub.stringOrNil("value")
                ?? sub.doubleOrNil("price").map { String(format: "%.2f", $0) }
                ?? sub.doubleOrNil("amount").map { String(format: "%.2f", $0) }
                ?? sub.doubleOrNil("value").map { String(format: "%.2f", $0) }
            price = Channel3Price(currency: currency, amount: amount)
        } else if let flat = c.stringOrNil("price") {
            price = Channel3Price(currency: nil, amount: flat)
        } else if let flatD = c.doubleOrNil("price") {
            price = Channel3Price(currency: nil, amount: String(format: "%.2f", flatD))
        } else {
            price = nil
        }
    }
}

// MARK: - Helpers

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(_ string: String) { stringValue = string; intValue = nil }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { stringValue = "\(intValue)"; self.intValue = intValue }
}

private extension KeyedDecodingContainer where K == AnyCodingKey {
    func stringOrNil(_ key: String) -> String? {
        try? decodeIfPresent(String.self, forKey: .init(key))
    }
    func doubleOrNil(_ key: String) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: .init(key)) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: .init(key)) { return Double(s) }
        return nil
    }
}

// MARK: - HTTP Client

class Channel3Service {

    static let shared = Channel3Service()

    private let apiKey = "enec9oLnLd8AhDAWLzyCe6ZEkjikINJC41tThgy3"
    private let baseURL = "https://api.trychannel3.com/v0/search"

    private init() {}

    func search(query: String, limit: Int = 10) async throws -> [Channel3Product] {
        guard let url = URL(string: baseURL) else { throw Channel3Error.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 15

        let payload: [String: Any] = [
            "query": query,
            "limit": limit,
            "config": ["keyword_search_only": false]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw Channel3Error.invalidResponse }
        guard http.statusCode == 200 else {
            throw Channel3Error.httpError(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "no body"
            )
        }

        return try Self.decode(data)
    }

    // MARK: Flexible decoding

    private static func decode(_ data: Data) throws -> [Channel3Product] {
        let decoder = JSONDecoder()

        // 1. Top-level array
        if let products = try? decoder.decode([Channel3Product].self, from: data), !products.isEmpty {
            return products
        }

        // 2. Wrapper object — try common key names
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let key = ["results", "products", "items", "data"].first { json[$0] is [[String: Any]] }
            if let key, let array = json[key] as? [[String: Any]],
               let arrayData = try? JSONSerialization.data(withJSONObject: array),
               let products = try? decoder.decode([Channel3Product].self, from: arrayData),
               !products.isEmpty {
                return products
            }
        }

        // 3. Surface a useful error
        let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
        throw Channel3Error.decodingError(
            NSError(domain: "Channel3", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Unrecognised response: \(preview)"])
        )
    }
}

// MARK: - Errors

enum Channel3Error: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid Channel3 API URL"
        case .invalidResponse:          return "Invalid response from Channel3 API"
        case .httpError(let c, let b):  return "Channel3 API HTTP \(c): \(b)"
        case .decodingError(let e):     return "Channel3 decode error: \(e.localizedDescription)"
        }
    }
}
