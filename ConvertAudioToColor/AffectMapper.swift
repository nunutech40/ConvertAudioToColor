import Foundation

/// Product rules that translate acoustic features into a visual mood.
/// This is intentionally deterministic and is not a claim of medical emotion detection.
final class AffectMapper {
    func map(_ features: AudioFeatures) -> AffectState {
        let arousal = AudioMath.clamp(
            0.45 * features.energy +
            0.22 * features.speechRhythm +
            0.20 * features.spectralFlux +
            0.13 * features.spectralSharpness
        )

        let valence = AudioMath.clamp(
            0.28 +
            0.22 * features.pitchVariation +
            0.12 * features.energy -
            0.28 * features.spectralFlux -
            0.24 * features.pauseRatio,
            -1,
            1
        )

        return AffectState(
            valence: valence,
            arousal: arousal,
            family: family(for: features, valence: valence, arousal: arousal),
            intensity: max(arousal, abs(valence))
        )
    }

    private func family(for features: AudioFeatures, valence: Float, arousal: Float) -> EmotionFamily {
        if features.isSilent || arousal < 0.18 {
            return valence < -0.25 ? .sadness : .trust
        }
        if arousal > 0.72 && valence < -0.25 {
            return features.spectralFlux > 0.55 ? .fear : .anger
        }
        if arousal > 0.68 && valence > 0.35 {
            return features.spectralFlux > 0.60 ? .surprise : .joy
        }
        if valence < -0.45 {
            return features.spectralSharpness > 0.65 ? .disgust : .sadness
        }
        if features.speechRhythm > 0.62 && valence > 0.1 {
            return .anticipation
        }
        return valence >= 0 ? .trust : .sadness
    }
}
