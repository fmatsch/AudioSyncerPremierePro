import Foundation
import Accelerate

struct SyncResult {
    let offsetSeconds: Double
    let confidence: Float
}

enum AudioSyncEngine {

    static func findOffset(master: [Float], camera: [Float], sampleRate: Double) -> SyncResult {
        let n = master.count + camera.count - 1
        let fftLength = nextPowerOf2(n)
        let halfN = fftLength / 2

        let log2n = vDSP_Length(log2(Double(fftLength)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return SyncResult(offsetSeconds: 0, confidence: 0)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Pad signals
        var masterPadded = [Float](repeating: 0, count: fftLength)
        var cameraPadded = [Float](repeating: 0, count: fftLength)
        for i in 0..<master.count { masterPadded[i] = master[i] }
        for i in 0..<camera.count { cameraPadded[i] = camera[i] }

        // FFT of master
        var masterReal = [Float](repeating: 0, count: halfN)
        var masterImag = [Float](repeating: 0, count: halfN)
        performFFT(setup: fftSetup, input: &masterPadded, real: &masterReal, imag: &masterImag,
                   halfN: halfN, log2n: log2n, direction: FFTDirection(kFFTDirection_Forward))

        // FFT of camera
        var cameraReal = [Float](repeating: 0, count: halfN)
        var cameraImag = [Float](repeating: 0, count: halfN)
        performFFT(setup: fftSetup, input: &cameraPadded, real: &cameraReal, imag: &cameraImag,
                   halfN: halfN, log2n: log2n, direction: FFTDirection(kFFTDirection_Forward))

        // Cross-correlation in frequency domain: FFT(master) * conj(FFT(camera))
        var corrReal = [Float](repeating: 0, count: halfN)
        var corrImag = [Float](repeating: 0, count: halfN)
        // vDSP packs DC in real[0] and Nyquist in imag[0] — handle separately
        corrReal[0] = masterReal[0] * cameraReal[0]
        corrImag[0] = masterImag[0] * cameraImag[0]
        for i in 1..<halfN {
            let ar = masterReal[i], ai = masterImag[i]
            let br = cameraReal[i], bi = cameraImag[i]
            corrReal[i] = ar * br + ai * bi
            corrImag[i] = ai * br - ar * bi
        }

        // Inverse FFT
        var corrSplit = DSPSplitComplex(realp: &corrReal, imagp: &corrImag)
        vDSP_fft_zrip(fftSetup, &corrSplit, 1, log2n, FFTDirection(kFFTDirection_Inverse))

        // Convert split complex back to interleaved real signal
        var result = [Float](repeating: 0, count: fftLength)
        corrSplit = DSPSplitComplex(realp: &corrReal, imagp: &corrImag)
        result.withUnsafeMutableBufferPointer { resultBuf in
            resultBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                vDSP_ztoc(&corrSplit, 1, complexPtr, 2, vDSP_Length(halfN))
            }
        }

        // Scale by 1/fftLength (vDSP convention)
        var scale = 1.0 / Float(fftLength)
        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(fftLength))

        // Take absolute values for peak finding
        var absResult = [Float](repeating: 0, count: fftLength)
        vDSP_vabs(result, 1, &absResult, 1, vDSP_Length(fftLength))

        // Find peak
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(absResult, 1, &maxVal, &maxIdx, vDSP_Length(fftLength))

        // Confidence: ratio of peak to mean absolute value
        var meanAbs: Float = 0
        vDSP_meamgv(result, 1, &meanAbs, vDSP_Length(fftLength))
        let confidence = meanAbs > 0 ? min(maxVal / meanAbs / 10.0, 1.0) : 0

        // Convert sample offset to seconds
        var offsetSamples = Int(maxIdx)
        if offsetSamples > fftLength / 2 {
            offsetSamples -= fftLength
        }
        let offsetSeconds = Double(offsetSamples) / sampleRate

        NSLog("[AudioSyncer] Sync: fftLength=%d, peak at index %d (offset %.4fs), maxVal=%.6f, confidence=%.4f",
              fftLength, Int(maxIdx), offsetSeconds, maxVal, confidence)

        return SyncResult(offsetSeconds: offsetSeconds, confidence: confidence)
    }

    private static func performFFT(setup: FFTSetup, input: inout [Float],
                                    real: inout [Float], imag: inout [Float],
                                    halfN: Int, log2n: vDSP_Length, direction: FFTDirection) {
        input.withUnsafeMutableBufferPointer { inputBuf in
            inputBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                var split = DSPSplitComplex(realp: &real, imagp: &imag)
                vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfN))
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(direction))
            }
        }
    }

    private static func nextPowerOf2(_ n: Int) -> Int {
        var v = n - 1
        v |= v >> 1
        v |= v >> 2
        v |= v >> 4
        v |= v >> 8
        v |= v >> 16
        return v + 1
    }
}
