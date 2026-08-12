//
//  ContentView.swift
//  ConvertAudioToColor
//

import Accelerate
import AVFoundation
import Combine
import SwiftUI

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

enum FeatureMath {
    static func clamp(_ value: Float, _ lower: Float = 0, _ upper: Float = 1) -> Float {
        min(max(value, lower), upper)
    }

    static func normalized(_ value: Float, min: Float, max: Float) -> Float {
        guard max > min else { return 0 }
        return clamp((value - min) / (max - min))
    }

    static func smooth(previous: Float, current: Float, factor: Float = 0.18) -> Float {
        previous + (current - previous) * clamp(factor)
    }
}

final class AffectMapper {
    func map(_ features: AudioFeatures) -> AffectState {
        let arousal = FeatureMath.clamp(
            0.45 * features.energy +
            0.22 * features.speechRhythm +
            0.20 * features.spectralFlux +
            0.13 * features.spectralSharpness
        )
        let valence = FeatureMath.clamp(
            0.28 +
            0.22 * features.pitchVariation +
            0.12 * features.energy -
            0.28 * features.spectralFlux -
            0.24 * features.pauseRatio,
            -1,
            1
        )

        let family: EmotionFamily
        if features.isSilent || arousal < 0.18 {
            family = valence < -0.25 ? .sadness : .trust
        } else if arousal > 0.72 && valence < -0.25 {
            family = features.spectralFlux > 0.55 ? .fear : .anger
        } else if arousal > 0.68 && valence > 0.35 {
            family = features.spectralFlux > 0.60 ? .surprise : .joy
        } else if valence < -0.45 {
            family = features.spectralSharpness > 0.65 ? .disgust : .sadness
        } else if features.speechRhythm > 0.62 && valence > 0.1 {
            family = .anticipation
        } else {
            family = valence >= 0 ? .trust : .sadness
        }

        return AffectState(valence: valence, arousal: arousal, family: family, intensity: max(arousal, abs(valence)))
    }
}

final class AudioAnalyzer {
    private var previousEnergy: Float = 0
    private var previousSpectrum = [Float]()

    func analyze(_ buffer: AVAudioPCMBuffer) -> AudioFeatures {
        guard let channelData = buffer.floatChannelData else { return AudioFeatures() }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return AudioFeatures() }
        let samples = channelData[0]
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        let energy = FeatureMath.clamp(rms * 8)

        let fftSize = min(1024, 1 << Int(log2(Double(max(2, count)))))
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        if fftSize >= 16 {
            var window = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
            let log2n = vDSP_Length(log2(Float(fftSize)))
            guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return AudioFeatures(energy: energy, pauseRatio: energy < 0.04 ? 1 : 0, isSilent: energy < 0.04) }
            defer { vDSP_destroy_fftsetup(setup) }
            var real = [Float](repeating: 0, count: fftSize / 2)
            var imaginary = [Float](repeating: 0, count: fftSize / 2)
            real.withUnsafeMutableBufferPointer { realPtr in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imaginaryPtr.baseAddress!)
                    windowed.withUnsafeBufferPointer { input in
                        input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftSize / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }
            var total: Float = 0
            vDSP_sve(magnitudes, 1, &total, vDSP_Length(magnitudes.count))
            let weighted = magnitudes.enumerated().reduce(Float(0)) { $0 + Float($1.offset) * $1.element }
            let sharpness = total > 0 ? FeatureMath.clamp((weighted / total) / Float(magnitudes.count)) : 0
            let flux: Float
            if previousSpectrum.count == magnitudes.count {
                flux = FeatureMath.clamp(magnitudes.enumerated().reduce(Float(0)) { $0 + max(0, $1.element - previousSpectrum[$1.offset]) } / max(total, 0.0001) * 5)
            } else { flux = 0 }
            previousSpectrum = magnitudes
            let silent = energy < 0.04
            let rhythm = FeatureMath.clamp(abs(energy - previousEnergy) * 6)
            previousEnergy = energy
            return AudioFeatures(energy: energy, spectralSharpness: sharpness, spectralFlux: flux, pitchVariation: rhythm, pauseRatio: silent ? 1 : 0, speechRhythm: rhythm, isSilent: silent)
        }
        return AudioFeatures(energy: energy, pauseRatio: energy < 0.04 ? 1 : 0, isSilent: energy < 0.04)
    }
}

final class InMemoryAudioSession {
    private(set) var buffers: [AVAudioPCMBuffer] = []
    private let maxBuffers = 900

    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffers.count < maxBuffers else { return }
        buffers.append(buffer)
    }

    func clear() { buffers.removeAll() }
    var isEmpty: Bool { buffers.isEmpty }
}

final class AudioReplayService {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isConnected = false

    func play(buffers: [AVAudioPCMBuffer], completion: @escaping () -> Void) throws {
        guard let first = buffers.first else { return }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
        if !engine.attachedNodes.contains(player) { engine.attach(player) }
        let format = first.format
        if !isConnected {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isConnected = true
        }
        for (index, buffer) in buffers.enumerated() {
            player.scheduleBuffer(buffer, completionHandler: index == buffers.count - 1 ? completion : nil)
        }
        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

final class AudioCaptureService {
    let engine = AVAudioEngine()
    let session = InMemoryAudioSession()
    private let analyzer = AudioAnalyzer()
    private let queue = DispatchQueue(label: "audio.capture.analysis", qos: .userInitiated)
    private var tapInstalled = false
    var onFeatures: ((AudioFeatures) -> Void)?
    var onError: ((Error) -> Void)?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
    }

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        if tapInstalled { input.removeTap(onBus: 0); tapInstalled = false }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.queue.async {
                self.session.append(buffer)
                let features = self.analyzer.analyze(buffer)
                DispatchQueue.main.async { self.onFeatures?(features) }
            }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

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
        capture.onFeatures = { [weak self] features in self?.receive(features) }
        capture.onError = { [weak self] error in self?.state = .failed(error.localizedDescription) }
    }

    func start() {
        guard state != .listening else { return }
        state = .requestingPermission
        Task {
            guard await capture.requestPermission() else { state = .permissionDenied; return }
            do { try capture.start(); state = .listening }
            catch { state = .failed(error.localizedDescription) }
        }
    }

    func stop() {
        capture.stop()
        replayService.stop()
        hasReplay = !capture.session.isEmpty
        state = .ready
    }

    func discard() {
        capture.stop()
        replayService.stop()
        capture.session.clear()
        hasReplay = false
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

    private func receive(_ incoming: AudioFeatures) {
        guard state == .listening else { return }
        let smoothed = AudioFeatures(
            energy: FeatureMath.smooth(previous: lastFeatures.energy, current: incoming.energy),
            spectralSharpness: FeatureMath.smooth(previous: lastFeatures.spectralSharpness, current: incoming.spectralSharpness),
            spectralFlux: FeatureMath.smooth(previous: lastFeatures.spectralFlux, current: incoming.spectralFlux),
            pitchVariation: FeatureMath.smooth(previous: lastFeatures.pitchVariation, current: incoming.pitchVariation),
            pauseRatio: FeatureMath.smooth(previous: lastFeatures.pauseRatio, current: incoming.pauseRatio),
            speechRhythm: FeatureMath.smooth(previous: lastFeatures.speechRhythm, current: incoming.speechRhythm),
            isSilent: incoming.isSilent
        )
        lastFeatures = smoothed
        features = smoothed
        affect = mapper.map(smoothed)
        visual = Self.visualization(for: affect, features: smoothed)
    }

    static func visualization(for affect: AffectState, features: AudioFeatures) -> VisualizationState {
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
        return VisualizationState(hue: hue, saturation: Double(0.35 + affect.intensity * 0.6), brightness: Double(0.3 + affect.arousal * 0.7), orbScale: Double(0.75 + affect.arousal * 1.2), glowRadius: Double(20 + affect.intensity * 90), pulseAmount: Double(features.spectralFlux), motionIntensity: Double(0.1 + affect.arousal * 0.9))
    }
}

struct ContentView: View {
    @StateObject private var model = VoiceVisualizerViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VisualizerCanvas(state: model.visual)
            VStack {
                header
                Spacer()
                controls
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("VOICE TO COLOR").font(.caption.weight(.bold)).tracking(2)
                Spacer()
                Circle().fill(statusColor).frame(width: 9, height: 9)
                Text(model.state.title).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(model.affect.family.rawValue).font(.system(size: 34, weight: .bold, design: .rounded))
                Spacer()
            }
            HStack {
                Text("valence \(model.affect.valence, specifier: "%.2f")")
                Text("arousal \(model.affect.arousal, specifier: "%.2f")")
                Spacer()
                if model.hasReplay { Text("Replay available").foregroundStyle(.secondary) }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(model.state == .listening ? "Stop" : (model.state == .playing ? "Stop replay" : "Start")) {
                if model.state == .listening { model.stop() }
                else if model.state == .playing { model.stopReplay() }
                else { model.start() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)

            if model.hasReplay {
                Button("Replay", action: model.replay).buttonStyle(.bordered)
                if model.state == .playing {
                    Button("Stop replay", action: model.stopReplay).buttonStyle(.bordered)
                }
                Button("Discard", action: model.discard).buttonStyle(.bordered).tint(.red)
            }
        }
    }

    private var statusColor: Color { model.state == .listening ? .green : .gray }
}

struct VisualizerCanvas: View {
    let state: VisualizationState
    @State private var phase = 0.0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let breathing = sin(time * 1.4) * 0.025
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.19 * (state.orbScale + breathing)
                let color = Color(hue: state.hue, saturation: state.saturation, brightness: state.brightness)
                let glow = color.opacity(0.18)
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: state.glowRadius))
                    layer.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(glow))
                }
                let orb = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                context.fill(orb, with: .radialGradient(Gradient(colors: [color, color.opacity(0.45), .clear]), center: center, startRadius: 0, endRadius: radius))
                context.stroke(orb, with: .color(color.opacity(0.8)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
