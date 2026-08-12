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
        Analisis sesi suara berikut dengan gaya manusia yang santai, natural, dan lucu.
        Fokus pada kondisi atau situasi yang mungkin sedang dialami orang ini, bukan membedah semua kalimatnya satu per satu.
        Gunakan gabungan karakter suara, perubahan mood, energi, dan konteks umum transcript.

        Jangan mengutip transcript secara verbatim.
        Jangan mengulang, menyebut, atau membocorkan kata kasar, hinaan, umpatan, atau istilah sensitif yang ada di transcript.
        Jika ada kata kasar, cukup sebut "bahasa yang cukup kasar" atau "ucapan yang emosional".
        Jangan membuat diagnosis psikologis dan jangan menyatakan dugaan sebagai fakta.
        Gunakan bahasa kemungkinan: "kelihatannya", "mungkin", atau "terdengar seperti".
        Jangan membuat analisis akademis atau penjelasan panjang.

        Mood dominan: \(summary.dominantFamily.rawValue)
        Mood sekunder: \(summary.secondaryFamilies.map(\.rawValue).joined(separator: ", "))
        Durasi: \(summary.duration) detik
        Energi rata-rata: \(summary.averageEnergy)
        Peak energi: \(summary.peakEnergy)
        Valence rata-rata: \(summary.averageValence)
        Arousal rata-rata: \(summary.averageArousal)
        Transcript: \(transcript.isEmpty ? "(tidak tersedia)" : transcript)

        Format jawaban:
        Kondisinya:
        Tulis 2-4 kalimat tentang kemungkinan kondisi/situasi orang ini berdasarkan data suara dan konteks umum ucapannya.

        Roasting:
        Tulis 1-3 kalimat roasting yang terasa seperti teman dekat sedang nyeletuk. Harus ringan, relevan dengan energi dan mood sesi, tanpa mengulang kata kasar atau isi transcript secara detail.
        """

        let body = ChatRequest(model: NineRouterConfiguration.model, messages: [
            .init(role: "system", content: "Kamu adalah teman yang peka, jenaka, dan bisa membaca suasana. Jawabanmu harus natural seperti obrolan manusia. Roasting harus playful, tidak menghina identitas, kesehatan, kondisi mental, atau hal sensitif. Jangan pernah mengulang kata kasar dari transcript."),
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
