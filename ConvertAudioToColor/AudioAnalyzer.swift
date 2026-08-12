import Accelerate
import AVFoundation

final class AudioAnalyzer {
    private var previousEnergy: Float = 0
    private var previousSpectrum = [Float]()

    func analyze(_ buffer: AVAudioPCMBuffer) -> AudioFeatures {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return AudioFeatures()
        }

        let sampleCount = Int(buffer.frameLength)
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(sampleCount))

        let energy = AudioMath.clamp(rms * 8)
        let silent = energy < 0.04
        let rhythm = AudioMath.clamp(abs(energy - previousEnergy) * 6)
        previousEnergy = energy

        guard let spectrum = makeSpectrum(samples: samples, count: sampleCount) else {
            return AudioFeatures(energy: energy, pitchVariation: rhythm,
                                 pauseRatio: silent ? 1 : 0, speechRhythm: rhythm,
                                 isSilent: silent)
        }

        let total = max(spectrum.reduce(0, +), 0.0001)
        let weighted = spectrum.enumerated().reduce(Float(0)) {
            $0 + Float($1.offset) * $1.element
        }
        let sharpness = AudioMath.clamp((weighted / total) / Float(spectrum.count))
        let flux = spectralFlux(current: spectrum, total: total)
        previousSpectrum = spectrum

        return AudioFeatures(
            energy: energy,
            spectralSharpness: sharpness,
            spectralFlux: flux,
            pitchVariation: rhythm,
            pauseRatio: silent ? 1 : 0,
            speechRhythm: rhythm,
            isSilent: silent
        )
    }

    private func spectralFlux(current: [Float], total: Float) -> Float {
        guard previousSpectrum.count == current.count else { return 0 }
        let increase = current.enumerated().reduce(Float(0)) {
            $0 + max(0, $1.element - previousSpectrum[$1.offset])
        }
        return AudioMath.clamp(increase / total * 5)
    }

    private func makeSpectrum(samples: UnsafePointer<Float>, count: Int) -> [Float]? {
        let fftSize = min(1024, 1 << Int(log2(Double(max(2, count)))))
        guard fftSize >= 16 else { return nil }

        var window = [Float](repeating: 0, count: fftSize)
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imaginary = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        return magnitudes
    }
}
