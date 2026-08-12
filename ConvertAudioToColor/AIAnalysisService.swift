import Foundation

struct NineRouterConfiguration {
    static let baseURL = URL(string: "https://9router.103-59-94-121.nip.io/v1")!
    static let model = "codexCombo"
    static let apiKeyUserDefaultsKey = "nineRouterAPIKey"
}

enum AIAnalysisError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Masukkan API key 9Router terlebih dahulu."
        case .invalidResponse: "Respons AI tidak dapat dibaca."
        case .server(let message): message
        }
    }
}

final class AIAnalysisService {
    func analyze(transcript: String, summary: SessionSummary) async throws -> String {
        let apiKey = LocalSecrets.nineRouterAPIKey

        let prompt = """
        Analisis sesi suara berikut dan buat roasting yang lucu, ringan, dan tidak kejam.
        Gunakan data emosi dan isi ucapan. Jangan membuat diagnosis psikologis dan jangan mengarang fakta.

        Mood dominan: \(summary.dominantFamily.rawValue)
        Mood sekunder: \(summary.secondaryFamilies.map(\.rawValue).joined(separator: ", "))
        Durasi: \(summary.duration) detik
        Energi rata-rata: \(summary.averageEnergy)
        Peak energi: \(summary.peakEnergy)
        Valence rata-rata: \(summary.averageValence)
        Arousal rata-rata: \(summary.averageArousal)
        Transcript: \(transcript.isEmpty ? "(tidak tersedia)" : transcript)

        Format jawaban:
        Kesimpulan emosi:
        Analisis isi ucapan:
        Roasting:
        """

        let body = ChatRequest(model: NineRouterConfiguration.model, messages: [
            .init(role: "system", content: "Kamu adalah analis suara yang jenaka. Roasting harus playful, tidak menghina identitas, kesehatan, atau hal sensitif."),
            .init(role: "user", content: prompt)
        ])

        var request = URLRequest(url: NineRouterConfiguration.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIAnalysisError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request AI gagal (HTTP \(http.statusCode))."
            throw AIAnalysisError.server(message)
        }
        guard let result = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = result.choices.first?.message.content else {
            throw AIAnalysisError.invalidResponse
        }
        return content
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
