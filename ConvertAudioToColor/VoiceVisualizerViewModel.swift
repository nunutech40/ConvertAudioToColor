import Foundation
import Combine

@MainActor
final class VoiceVisualizerViewModel: ObservableObject {
    @Published var state: ListeningState = .ready
    @Published var features = AudioFeatures()
    @Published var affect = AffectState()
    @Published var visual = VisualizationState()
    @Published var hasReplay = false

    let capture = AudioCaptureService()
    private let replayService = AudioReplayService()
    private let mapper = AffectMapper()
    private var lastFeatures = AudioFeatures()

    init() {
        capture.onFeatures = { [weak self] features in
            self?.receive(features)
        }
    }

    func start() {
        guard state != .listening else { return }
        state = .requestingPermission

        Task {
            guard await capture.requestPermission() else {
                state = .permissionDenied
                return
            }
            do {
                try capture.start()
                state = .listening
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        capture.stop()
        replayService.stop()
        hasReplay = !capture.session.isEmpty
        state = .ready
    }

    func replay() {
        guard hasReplay else { return }
        state = .playing

        do {
            try replayService.play(buffers: capture.session.buffers) { [weak self] in
                Task { @MainActor in self?.state = .ready }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopReplay() {
        replayService.stop()
        state = .ready
    }

    func discard() {
        capture.stop()
        replayService.stop()
        capture.session.clear()
        hasReplay = false
        state = .ready
    }

    private func receive(_ incoming: AudioFeatures) {
        guard state == .listening else { return }

        let smoothed = AudioFeatures(
            energy: AudioMath.smooth(previous: lastFeatures.energy, current: incoming.energy),
            spectralSharpness: AudioMath.smooth(previous: lastFeatures.spectralSharpness, current: incoming.spectralSharpness),
            spectralFlux: AudioMath.smooth(previous: lastFeatures.spectralFlux, current: incoming.spectralFlux),
            pitchVariation: AudioMath.smooth(previous: lastFeatures.pitchVariation, current: incoming.pitchVariation),
            pauseRatio: AudioMath.smooth(previous: lastFeatures.pauseRatio, current: incoming.pauseRatio),
            speechRhythm: AudioMath.smooth(previous: lastFeatures.speechRhythm, current: incoming.speechRhythm),
            isSilent: incoming.isSilent
        )

        lastFeatures = smoothed
        features = smoothed
        affect = mapper.map(smoothed)
        visual = Self.makeVisualization(for: affect, features: smoothed)
    }

    nonisolated static func makeVisualization(for affect: AffectState, features: AudioFeatures) -> VisualizationState {
        let hue: Double = switch affect.family {
        case .sadness: 0.62
        case .anger: 0.01
        case .fear: 0.72
        case .joy: 0.12
        case .trust: 0.45
        case .surprise: 0.88
        case .disgust: 0.25
        case .anticipation: 0.06
        }

        return VisualizationState(
            hue: hue,
            saturation: Double(0.35 + affect.intensity * 0.6),
            brightness: Double(0.3 + affect.arousal * 0.7),
            orbScale: Double(0.75 + affect.arousal * 1.2),
            glowRadius: Double(20 + affect.intensity * 90),
            pulseAmount: Double(features.spectralFlux),
            motionIntensity: Double(0.1 + affect.arousal * 0.9)
        )
    }
}
