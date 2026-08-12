import Foundation

struct AudioFeatures: Sendable, Equatable {
    var energy: Float = 0
    var spectralSharpness: Float = 0
    var spectralFlux: Float = 0
    var pitchVariation: Float = 0
    var pauseRatio: Float = 1
    var speechRhythm: Float = 0
    var isSilent: Bool = true
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
