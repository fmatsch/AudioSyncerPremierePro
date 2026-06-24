import AVFoundation
import Accelerate

struct AudioExtractionResult {
    let samples: [Float]
    let sampleRate: Double
    let duration: Double
}

enum AudioExtractor {

    static let targetSampleRate: Double = 8000

    static func extract(from url: URL, maxDuration: Double = 60.0) async throws -> AudioExtractionResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        let audioTrack = try await findAudioTrack(in: asset)

        let duration = try await asset.load(.duration).seconds
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let maxSamples = Int(min(duration, maxDuration) * targetSampleRate)
        var allSamples = [Float]()
        allSamples.reserveCapacity(maxSamples)

        guard reader.startReading() else {
            throw AudioExtractorError.readingFailed(reader.error?.localizedDescription ?? "Unbekannter Fehler beim Starten")
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
                let buffer = UnsafeBufferPointer(start: floatPointer, count: floatCount)
                allSamples.append(contentsOf: buffer)
            }

            if allSamples.count >= maxSamples { break }
        }

        if reader.status == .failed {
            throw AudioExtractorError.readingFailed(reader.error?.localizedDescription ?? "Lesen fehlgeschlagen")
        }

        reader.cancelReading()

        if allSamples.count > maxSamples {
            allSamples = Array(allSamples.prefix(maxSamples))
        }

        guard !allSamples.isEmpty else {
            throw AudioExtractorError.readingFailed("Keine Audio-Samples gelesen")
        }

        return AudioExtractionResult(
            samples: allSamples,
            sampleRate: targetSampleRate,
            duration: duration
        )
    }

    static func extractWaveformSamples(from url: URL, targetCount: Int = 200) async throws -> (samples: [Float], duration: Double) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds

        let audioTrack: AVAssetTrack
        do {
            audioTrack = try await findAudioTrack(in: asset)
        } catch {
            return ([], duration)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 8000,
            AVNumberOfChannelsKey: 1
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        var allSamples = [Float]()

        guard reader.startReading() else { return ([], duration) }

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
        }
        reader.cancelReading()

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

    private static func findAudioTrack(in asset: AVURLAsset) async throws -> AVAssetTrack {
        // Try dedicated audio tracks first
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let track = audioTracks.first { return track }

        // Some containers embed audio differently — check all tracks
        let allTracks = try await asset.load(.tracks)
        for track in allTracks {
            if track.mediaType == .audio { return track }
        }

        // Try loading via audio characteristics
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
