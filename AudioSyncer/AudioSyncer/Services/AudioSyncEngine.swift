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

        var masterPadded = [Float](repeating: 0, count: fftLength)
        var cameraPadded = [Float](repeating: 0, count: fftLength)
        masterPadded.replaceSubrange(0..<master.count, with: master)
        cameraPadded.replaceSubrange(0..<camera.count, with: camera)

        let log2n = vDSP_Length(log2(Double(fftLength)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return SyncResult(offsetSeconds: 0, confidence: 0)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfN = fftLength / 2

        var masterReal = [Float](repeating: 0, count: halfN)
        var masterImag = [Float](repeating: 0, count: halfN)
        var cameraReal = [Float](repeating: 0, count: halfN)
        var cameraImag = [Float](repeating: 0, count: halfN)

        masterPadded.withUnsafeMutableBufferPointer { masterBuf in
            masterReal.withUnsafeMutableBufferPointer { realBuf in
                masterImag.withUnsafeMutableBufferPointer { imagBuf in
                    var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    masterBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { ptr in
                        vDSP_ctoz(ptr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
        }

        cameraPadded.withUnsafeMutableBufferPointer { cameraBuf in
            cameraReal.withUnsafeMutableBufferPointer { realBuf in
                cameraImag.withUnsafeMutableBufferPointer { imagBuf in
                    var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    cameraBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { ptr in
                        vDSP_ctoz(ptr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
        }

        // Cross-correlation: IFFT(FFT(master) * conj(FFT(camera)))
        var corrReal = [Float](repeating: 0, count: halfN)
        var corrImag = [Float](repeating: 0, count: halfN)

        for i in 0..<halfN {
            let ar = masterReal[i], ai = masterImag[i]
            let br = cameraReal[i], bi = -cameraImag[i] // conjugate
            corrReal[i] = ar * br - ai * bi
            corrImag[i] = ar * bi + ai * br
        }

        var corrSplit = DSPSplitComplex(
            realp: &corrReal,
            imagp: &corrImag
        )
        vDSP_fft_zrip(fftSetup, &corrSplit, 1, log2n, FFTDirection(kFFTDirection_Inverse))

        var result = [Float](repeating: 0, count: fftLength)
        result.withUnsafeMutableBufferPointer { resultBuf in
            var split = DSPSplitComplex(realp: corrReal.withUnsafeMutableBufferPointer { $0.baseAddress! },
                                         imagp: corrImag.withUnsafeMutableBufferPointer { $0.baseAddress! })
            vDSP_ztoc(&split, 1, resultBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { $0 }, 2, vDSP_Length(halfN))
        }

        // Normalize
        var scale = Float(1.0 / Float(fftLength))
        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(fftLength))

        // Find peak
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(result, 1, &maxVal, &maxIdx, vDSP_Length(fftLength))

        // Compute confidence as ratio of peak to mean
        var mean: Float = 0
        vDSP_meamgv(result, 1, &mean, vDSP_Length(fftLength))
        let confidence = mean > 0 ? min(maxVal / mean / 10.0, 1.0) : 0

        var offsetSamples = Int(maxIdx)
        if offsetSamples > fftLength / 2 {
            offsetSamples -= fftLength
        }

        let offsetSeconds = Double(offsetSamples) / sampleRate

        return SyncResult(offsetSeconds: offsetSeconds, confidence: confidence)
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
