import AVFoundation
import Accelerate

struct AudioExtractionResult {
    let samples: [Float]
    let sampleRate: Double
    let duration: Double
}

enum AudioExtractor {

    static let targetSampleRate: Double = 8000

    private static let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
        AVSampleRateKey: targetSampleRate,
        AVNumberOfChannelsKey: 1
    ]

    static func extract(from url: URL, maxDuration: Double = 60.0) async throws -> AudioExtractionResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds
        let maxSamples = Int(min(duration, maxDuration) * targetSampleRate)

        // Try track-based extraction first, fall back to audio mix
        let samples: [Float]
        do {
            samples = try await extractViaTrack(asset: asset, maxSamples: maxSamples)
        } catch {
            samples = try await extractViaAudioMix(asset: asset, maxSamples: maxSamples)
        }

        guard !samples.isEmpty else {
            throw AudioExtractorError.readingFailed("Keine Audio-Samples gelesen — Datei hat möglicherweise keine kompatible Audiospur")
        }

        return AudioExtractionResult(
            samples: Array(samples.prefix(maxSamples)),
            sampleRate: targetSampleRate,
            duration: duration
        )
    }

    static func extractWaveformSamples(from url: URL, targetCount: Int = 200) async throws -> (samples: [Float], duration: Double) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds

        var allSamples = [Float]()

        // Try track-based, then audio mix
        if let trackSamples = try? await extractViaTrack(asset: asset, maxSamples: nil), !trackSamples.isEmpty {
            allSamples = trackSamples
        } else if let mixSamples = try? await extractViaAudioMix(asset: asset, maxSamples: nil), !mixSamples.isEmpty {
            allSamples = mixSamples
        }

        guard !allSamples.isEmpty else { return ([], duration) }

        let samplesPerBin = max(1, allSamples.count / targetCount)
        var waveform = [Float]()
        waveform.reserveCapacity(targetCount)

        for i in stride(from: 0, to: allSamples.count, by: samplesPerBin) {
            let end = min(i + samplesPerBin, allSamples.count)
            let slice = allSamples[i..<end]
            let rms = sqrt(slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count))
            waveform.append(rms)
        }

        return (waveform, duration)
    }

    // MARK: - Track-based extraction (works for most formats)

    private static func extractViaTrack(asset: AVURLAsset, maxSamples: Int?) async throws -> [Float] {
        let audioTrack = try await findAudioTrack(in: asset)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        return try readSamples(from: reader, output: output, maxSamples: maxSamples)
    }

    // MARK: - AudioMix extraction (fallback — handles more codecs by mixing all audio)

    private static func extractViaAudioMix(asset: AVURLAsset, maxSamples: Int?) async throws -> [Float] {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        // Also try audible characteristic tracks
        var tracks = audioTracks
        if tracks.isEmpty {
            tracks = try await asset.loadTracks(withMediaCharacteristic: .audible)
        }
        // Last resort: check all tracks
        if tracks.isEmpty {
            let allTracks = try await asset.load(.tracks)
            tracks = allTracks.filter { $0.mediaType == .audio }
        }

        guard !tracks.isEmpty else {
            throw AudioExtractorError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let mixOutput = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: outputSettings)
        mixOutput.alwaysCopiesSampleData = false
        reader.add(mixOutput)

        return try readSamples(from: reader, output: mixOutput, maxSamples: maxSamples)
    }

    // MARK: - Shared sample reading

    private static func readSamples(from reader: AVAssetReader, output: AVAssetReaderOutput, maxSamples: Int?) throws -> [Float] {
        var allSamples = [Float]()
        if let max = maxSamples {
            allSamples.reserveCapacity(max)
        }

        guard reader.startReading() else {
            let msg = reader.error?.localizedDescription ?? "Unbekannter Fehler"
            throw AudioExtractorError.readingFailed(msg)
        }

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if status == kCMBlockBufferNoErr, let dataPointer = dataPointer, length > 0 {
                let floatCount = length / MemoryLayout<Float>.size
                let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: floatCount)
                allSamples.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: floatCount))
            }

            if let max = maxSamples, allSamples.count >= max { break }
        }

        if reader.status == .failed {
            let msg = reader.error?.localizedDescription ?? "Lesen fehlgeschlagen"
            throw AudioExtractorError.readingFailed(msg)
        }

        reader.cancelReading()
        return allSamples
    }

    // MARK: - Track discovery

    private static func findAudioTrack(in asset: AVURLAsset) async throws -> AVAssetTrack {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let track = audioTracks.first { return track }

        let allTracks = try await asset.load(.tracks)
        for track in allTracks {
            if track.mediaType == .audio { return track }
        }

        let charTracks = try await asset.loadTracks(withMediaCharacteristic: .audible)
        if let track = charTracks.first { return track }

        throw AudioExtractorError.noAudioTrack
    }
}

enum AudioExtractorError: LocalizedError {
    case noAudioTrack
    case readingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "Keine Audio-Spur gefunden"
        case .readingFailed(let msg): return "Audio-Lesen fehlgeschlagen: \(msg)"
        }
    }
}
