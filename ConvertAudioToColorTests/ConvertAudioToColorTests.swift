import XCTest
@testable import ConvertAudioToColor

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
}
