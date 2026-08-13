import XCTest
import AVFoundation
@testable import ConvertAudioToColor

@MainActor
final class ConvertAudioToColorTests: XCTestCase {
    func testNormalizationAndClamping() {
        XCTAssertEqual(AudioMath.normalized(5, min: 0, max: 10), 0.5)
        XCTAssertEqual(AudioMath.normalized(-2, min: 0, max: 10), 0)
        XCTAssertEqual(AudioMath.normalized(20, min: 0, max: 10), 1)
    }

    func testSmoothingMovesTowardCurrentValue() {
        let result = AudioMath.smooth(previous: 0, current: 1, factor: 0.2)
        XCTAssertEqual(result, 0.2, accuracy: 0.001)
    }

    func testHighEnergyNegativeFeaturesMapToAngerOrFear() {
        let features = AudioFeatures(energy: 0.95, spectralSharpness: 0.7, spectralFlux: 0.25,
                                     pitchVariation: 0.1, pauseRatio: 0, speechRhythm: 0.8, isSilent: false)
        let affect = AffectMapper().map(features)
        XCTAssertTrue([.anger, .fear].contains(affect.family))
        XCTAssertGreaterThan(affect.arousal, 0.7)
    }

    func testQuietNegativeFeaturesMapToSadness() {
        let features = AudioFeatures(energy: 0.08, spectralSharpness: 0.2, spectralFlux: 0.05,
                                     pitchVariation: 0.05, pauseRatio: 0.8, speechRhythm: 0.1, isSilent: false)
        XCTAssertEqual(AffectMapper().map(features).family, .sadness)
    }

    func testVisualizationIntensityIsBounded() {
        let affect = AffectState(valence: -1, arousal: 1, family: .anger, intensity: 1)
        let visual = VoiceVisualizerViewModel.makeVisualization(for: affect, features: AudioFeatures())
        XCTAssertEqual(visual.hue, 0.01)
        XCTAssertGreaterThanOrEqual(visual.saturation, 0)
        XCTAssertLessThanOrEqual(visual.saturation, 1)
        XCTAssertGreaterThan(visual.glowRadius, 20)
    }

    func testQuietAudioFeaturesExposeNoiseAndSignalToNoise() {
        let features = AudioFeatures(energy: 0.08, pauseRatio: 0,
                                     isSilent: false, noiseLevel: 0.02, signalToNoise: 0.5)
        XCTAssertEqual(features.noiseLevel, 0.02)
        XCTAssertEqual(features.signalToNoise, 0.5)
    }

    func testInMemorySessionRollsOutOldestBuffers() throws {
        let session = InMemoryAudioSession(maxBufferCount: 3)
        let format = makeFormat()
        let first = makeBuffer(format)
        let second = makeBuffer(format)
        let third = makeBuffer(format)
        let fourth = makeBuffer(format)

        session.append(first)
        session.append(second)
        session.append(third)
        XCTAssertEqual(session.buffers.count, 3)
        XCTAssertTrue(session.buffers[0] === first)

        session.append(fourth)
        XCTAssertEqual(session.buffers.count, 3)
        XCTAssertTrue(session.buffers[0] === second)
        XCTAssertTrue(session.buffers[1] === third)
        XCTAssertTrue(session.buffers[2] === fourth)
    }

    func testInMemorySessionRetainedAndCapacityDuration() throws {
        let session = InMemoryAudioSession(maxBufferCount: 900)
        let format = makeFormat()
        session.append(makeBuffer(format))
        session.append(makeBuffer(format))

        XCTAssertEqual(session.retainedDuration, 2 * 1024.0 / 48_000.0, accuracy: 0.0001)
        XCTAssertEqual(session.capacityDuration, 900 * 1024.0 / 48_000.0, accuracy: 0.0001)
    }

    func testInMemorySessionClearResetsReplayData() throws {
        let session = InMemoryAudioSession(maxBufferCount: 3)
        session.append(makeBuffer(makeFormat()))
        session.append(makeBuffer(makeFormat()))
        XCTAssertFalse(session.isEmpty)
        session.clear()
        XCTAssertTrue(session.isEmpty)
        XCTAssertEqual(session.retainedDuration, 0)
    }

    private func makeFormat() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    }

    private func makeBuffer(_ format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        return buffer
    }
}
