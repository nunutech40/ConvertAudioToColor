import Foundation
import Combine

@MainActor
final class VoiceVisualizerViewModel: ObservableObject {
    @Published var state: ListeningState = .ready
    @Published var features = AudioFeatures()
    @Published var affect = AffectState()
    @Published var visual = VisualizationState()
    @Published var hasReplay = false
    @Published var summary: SessionSummary?
    @Published var chartPoints = [AudioChartPoint]()
    @Published var emotionTimeline = [EmotionTimelinePoint]()
    @Published var transcript = ""
    @Published var aiResult = ""
    @Published var isAnalyzing = false

    let capture = AudioCaptureService()
    private let replayService = AudioReplayService()
    private let mapper = AffectMapper()
    private let aiService = AIAnalysisService()
    private var lastFeatures = AudioFeatures()
    private var sessionStartedAt: Date?
    private var sessionSamples = [AffectState]()
    private var sessionEnergies = [Float]()
    private var chartSequence = 0

    init() {
        capture.onFeatures = { [weak self] features in
            self?.receive(features)
        }
        capture.onTranscript = { [weak self] text in
            Task { @MainActor in self?.transcript = text }
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
            _ = await capture.transcript.requestPermission()
            do {
                self.resetSessionSummary()
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
        finishSessionSummary()
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
            isSilent: incoming.isSilent,
            noiseLevel: incoming.noiseLevel,
            signalToNoise: incoming.signalToNoise
        )

        lastFeatures = smoothed
        features = smoothed
        affect = mapper.map(smoothed)
        visual = Self.makeVisualization(for: affect, features: smoothed)
        sessionSamples.append(affect)
        sessionEnergies.append(smoothed.energy)
        appendChartPoint(for: smoothed)
        emotionTimeline.append(EmotionTimelinePoint(id: chartSequence,
                                                     level: Double(smoothed.energy),
                                                     family: affect.family))
    }

    private func appendChartPoint(for features: AudioFeatures) {
        chartPoints.append(AudioChartPoint(id: chartSequence,
                                           level: Double(features.energy),
                                           frequency: Double(features.spectralSharpness)))
        chartSequence += 1
        if chartPoints.count > 72 {
            chartPoints.removeFirst(chartPoints.count - 72)
        }
    }

    private func resetSessionSummary() {
        summary = nil
        transcript = ""
        aiResult = ""
        sessionStartedAt = Date()
        sessionSamples.removeAll(keepingCapacity: true)
        sessionEnergies.removeAll(keepingCapacity: true)
        lastFeatures = AudioFeatures()
        chartPoints.removeAll(keepingCapacity: true)
        emotionTimeline.removeAll(keepingCapacity: true)
        chartSequence = 0
    }

    func analyzeAndRoast() {
        guard let summary, !isAnalyzing else { return }
        isAnalyzing = true
        aiResult = ""
        Task {
            do {
                aiResult = try await aiService.analyze(transcript: transcript, summary: summary)
            } catch {
                aiResult = "AI belum bisa menganalisis sesi ini: \(error.localizedDescription)"
            }
            isAnalyzing = false
        }
    }

    private func finishSessionSummary() {
        guard !sessionSamples.isEmpty else { return }
        let duration = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let averageEnergy = sessionEnergies.reduce(0, +) / Float(sessionEnergies.count)
        let peakEnergy = sessionEnergies.max() ?? 0
        let averageValence = sessionSamples.map(\.valence).reduce(0, +) / Float(sessionSamples.count)
        let averageArousal = sessionSamples.map(\.arousal).reduce(0, +) / Float(sessionSamples.count)
        let counts = Dictionary(grouping: sessionSamples, by: \.family).mapValues(\.count)
        let rankedFamilies = counts.sorted { $0.value > $1.value }.map(\.key)
        let dominantFamily = rankedFamilies.first ?? .trust
        let secondaryFamilies = rankedFamilies.dropFirst().filter { (counts[$0] ?? 0) >= 2 }.prefix(2)

        summary = SessionSummary(duration: duration, averageEnergy: averageEnergy,
                                 peakEnergy: peakEnergy, averageValence: averageValence,
                                 averageArousal: averageArousal, dominantFamily: dominantFamily,
                                 secondaryFamilies: Array(secondaryFamilies),
                                 sampleCount: sessionSamples.count)
    }

    nonisolated static func makeVisualization(for affect: AffectState, features: AudioFeatures) -> VisualizationState {
        let baseHue: Double = switch affect.family {
        case .sadness: 0.62
        case .anger: 0.01
        case .fear: 0.72
        case .joy: 0.12
        case .trust: 0.45
        case .surprise: 0.88
        case .disgust: 0.25
        case .anticipation: 0.06
        }
        // Keep the emotion family palette, but continuously shift within it.
        // This makes frame-by-frame changes visible instead of locking one color per mood.
        let hue = normalizedHue(baseHue + Double(affect.valence) * 0.07
                                + Double(features.spectralSharpness - 0.5) * 0.10)

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

    private nonisolated static func normalizedHue(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }
}
