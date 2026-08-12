import Foundation

struct AudioFeatures: Sendable, Equatable {
    var energy: Float = 0
    var spectralSharpness: Float = 0
    var spectralFlux: Float = 0
    var pitchVariation: Float = 0
    var pauseRatio: Float = 1
    var speechRhythm: Float = 0
    var isSilent: Bool = true
    var noiseLevel: Float = 0
    var signalToNoise: Float = 0
}

enum EmotionFamily: String, Sendable, CaseIterable {
    case sadness = "Sadness"
    case anger = "Anger"
    case fear = "Fear"
    case joy = "Joy"
    case trust = "Trust"
    case surprise = "Surprise"
    case disgust = "Disgust"
    case anticipation = "Anticipation"
}

struct AffectState: Sendable, Equatable {
    var valence: Float = 0
    var arousal: Float = 0
    var family: EmotionFamily = .trust
    var intensity: Float = 0
}

struct VisualizationState: Sendable, Equatable {
    var hue = 0.5
    var saturation = 0.65
    var brightness = 0.55
    var orbScale = 1.0
    var glowRadius = 40.0
    var pulseAmount = 0.0
    var motionIntensity = 0.15
}

struct AudioChartPoint: Identifiable, Sendable, Equatable {
    let id: Int
    let level: Double
    let frequency: Double
}

struct SessionSummary: Sendable, Equatable {
    var duration: TimeInterval = 0
    var averageEnergy: Float = 0
    var peakEnergy: Float = 0
    var averageValence: Float = 0
    var averageArousal: Float = 0
    var dominantFamily: EmotionFamily = .trust
    var sampleCount: Int = 0

    var description: String {
        String(format: "%@ · avg energy %.2f · peak %.2f", dominantFamily.rawValue, averageEnergy, peakEnergy)
    }

    var emotionalConclusion: String {
        switch dominantFamily {
        case .trust:
            if averageArousal < 0.3 {
                return "Karakter suaramu terdengar tenang dan cukup stabil, dengan kecenderungan positif ringan. Tidak terlihat intensitas emosi yang kuat."
            }
            return "Karakter suaramu terdengar cukup positif dan stabil, dengan energi sedang."
        case .sadness:
            return "Karakter suaramu terdengar lebih pelan dan berenergi rendah, dengan kecenderungan suasana yang lebih berat atau murung."
        case .anger:
            return "Karakter suaramu menunjukkan energi tinggi dan perubahan yang cukup tajam, sehingga terbaca sebagai suasana tegang atau kesal."
        case .fear:
            return "Karakter suaramu menunjukkan energi tinggi yang tidak stabil, dengan perubahan cepat yang dapat terasa seperti tegang atau cemas."
        case .joy:
            return "Karakter suaramu terdengar hidup dan berenergi, dengan kecenderungan suasana positif atau ceria."
        case .surprise:
            return "Karakter suaramu memiliki beberapa lonjakan energi yang mendadak, sehingga terasa spontan atau terkejut."
        case .disgust:
            return "Karakter suaramu menunjukkan pola yang cukup berat dan tidak nyaman, dengan kecenderungan negatif."
        case .anticipation:
            return "Karakter suaramu menunjukkan energi yang meningkat, seolah ada dorongan atau antisipasi terhadap sesuatu."
        }
    }
}

enum ListeningState: Equatable {
    case ready, requestingPermission, listening, paused, playing
    case permissionDenied, unavailable(String), failed(String)

    var title: String {
        switch self {
        case .ready: "Ready"
        case .requestingPermission: "Requesting microphone"
        case .listening: "Listening"
        case .paused: "Paused"
        case .playing: "Replay"
        case .permissionDenied: "Microphone denied"
        case .unavailable: "Microphone unavailable"
        case .failed: "Audio failed"
        }
    }
}
