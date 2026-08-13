import AVFoundation
import Speech

final class SpeechTranscriptService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "id-ID"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var didFinish = false
    private var generation = 0
    private let lock = NSLock()

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
        cancel()
        lock.lock()
        generation += 1
        let activeGeneration = generation
        lock.unlock()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.lock.lock()
            guard self.generation == activeGeneration else {
                self.lock.unlock()
                return
            }
            if result != nil {
                let text = result!.bestTranscription.formattedString
                let isFinal = result!.isFinal
                self.lock.unlock()
                self.onText?(text)
                if isFinal {
                    self.lock.lock()
                    if self.generation == activeGeneration { self.didFinish = true }
                    self.lock.unlock()
                }
            } else {
                if error != nil { self.didFinish = true }
                self.lock.unlock()
            }
        }
        lock.lock()
        self.request = request
        self.task = task
        self.didFinish = false
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let activeRequest = request
        lock.unlock()
        activeRequest?.append(buffer)
    }

    /// Signals the recognizer that audio ended, then waits up to `timeout` for
    /// the final transcript before cancelling. The last partial/final text is
    /// still delivered through `onText` when it arrives.
    func finish(timeout: TimeInterval = 2.0) async {
        lock.lock()
        let activeTask = task
        let activeRequest = request
        lock.unlock()
        activeRequest?.endAudio()

        let deadline = Date().addingTimeInterval(timeout)
        var done = false
        while Date() < deadline {
            lock.lock()
            done = didFinish
            lock.unlock()
            if done { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !done { activeTask?.cancel() }

        lock.lock()
        // Only clear the state this call still owns; a newer start() may have
        // installed a fresh task that must not be touched or reset.
        if task === activeTask {
            task = nil
            didFinish = false
        }
        if request === activeRequest {
            request = nil
        }
        lock.unlock()
    }

    /// Immediately discards the in-flight recognition without waiting.
    func cancel() {
        lock.lock()
        let activeTask = task
        let activeRequest = request
        task = nil
        request = nil
        didFinish = false
        generation += 1
        lock.unlock()
        activeRequest?.endAudio()
        activeTask?.cancel()
    }
}

final class InMemoryAudioSession {
    private var storedBuffers: [AVAudioPCMBuffer] = []
    private let maxBufferCount: Int
    private let lock = NSLock()

    var buffers: [AVAudioPCMBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return storedBuffers
    }

    init(maxBufferCount: Int = 900) {
        self.maxBufferCount = maxBufferCount
    }

    /// Rolling policy: keeps only the newest `maxBufferCount` chunks and
    /// discards the oldest ones, so replay memory stays bounded.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if storedBuffers.count >= maxBufferCount {
            storedBuffers.removeFirst(storedBuffers.count - maxBufferCount + 1)
        }
        storedBuffers.append(buffer)
    }

    func clear() {
        lock.lock()
        storedBuffers.removeAll()
        lock.unlock()
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedBuffers.isEmpty
    }

    /// Actual audio duration currently retained for replay.
    var retainedDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let first = storedBuffers.first else { return 0 }
        let totalFrames = storedBuffers.reduce(0) { $0 + $1.frameLength }
        return Double(totalFrames) / first.format.sampleRate
    }

    /// Maximum audio duration the rolling window can hold.
    var capacityDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let first = storedBuffers.first else { return 0 }
        return Double(maxBufferCount) * Double(first.frameLength) / first.format.sampleRate
    }
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
        do {
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
            transcript.start()

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
        } catch {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            transcript.cancel()
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    /// Stops the engine and tap. When `finalizeTranscript` is true the speech
    /// recognizer is allowed to finish with a timeout instead of being cancelled
    /// immediately, so the final transcript text can arrive.
    func stop(finalizeTranscript: Bool = false) {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        if finalizeTranscript {
            Task { await transcript.finish(timeout: 2.0) }
        } else {
            transcript.cancel()
        }
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
            player.scheduleBuffer(buffer, completionHandler: index == buffers.count - 1 ? { [weak self] in
                self?.stop()
                completion()
            } : nil)
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
