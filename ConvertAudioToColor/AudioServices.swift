import AVFoundation
import Speech

final class SpeechTranscriptService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "id-ID"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var onText: ((String) -> Void)?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func start() {
        guard let recognizer, recognizer.isAvailable else { return }
        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            self?.onText?(result.bestTranscription.formattedString)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
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

final class AudioCaptureService {
    let engine = AVAudioEngine()
    let session = InMemoryAudioSession()

    private let analyzer = AudioAnalyzer()
    let transcript = SpeechTranscriptService()
    private let queue = DispatchQueue(label: "audio.capture.analysis", qos: .userInitiated)
    private var tapInstalled = false

    var onFeatures: ((AudioFeatures) -> Void)?
    var onTranscript: ((String) -> Void)?

    init() {
        transcript.onText = { [weak self] text in self?.onTranscript?(text) }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement,
                                     options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setPreferredSampleRate(48_000)
        try audioSession.setPreferredIOBufferDuration(0.01)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Hardware input gain is not available on every iPhone or route.
        // When supported, use the maximum hardware gain before software analysis.
        if audioSession.isInputGainSettable {
            try? audioSession.setInputGain(1.0)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        if tapInstalled { input.removeTap(onBus: 0) }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.queue.async {
                self.session.append(buffer)
                self.transcript.append(buffer)
                let features = self.analyzer.analyze(buffer)
                DispatchQueue.main.async { self.onFeatures?(features) }
            }
        }

        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    func stop() {
        transcript.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

final class AudioReplayService {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isConnected = false

    func play(buffers: [AVAudioPCMBuffer], completion: @escaping () -> Void) throws {
        guard let first = buffers.first else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement,
                                     options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)

        if !isConnected {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: first.format)
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
