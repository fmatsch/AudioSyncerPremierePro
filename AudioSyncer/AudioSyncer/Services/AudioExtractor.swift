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

        // Try AVFoundation first (fast, native)
        if let result = try? await extractViaAVFoundation(url: url, maxDuration: maxDuration) {
            return result
        }

        // Fallback: use ffmpeg to convert to temp WAV, then read that
        return try await extractViaFFmpeg(url: url, maxDuration: maxDuration)
    }

    static func extractWaveformSamples(from url: URL, targetCount: Int = 200) async throws -> (samples: [Float], duration: Double) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Try AVFoundation first
        if let result = try? await extractViaAVFoundation(url: url, maxDuration: .infinity) {
            return (downsampleToWaveform(result.samples, targetCount: targetCount), result.duration)
        }

        // Fallback: ffmpeg
        if let result = try? await extractViaFFmpeg(url: url, maxDuration: .infinity) {
            return (downsampleToWaveform(result.samples, targetCount: targetCount), result.duration)
        }

        // Last resort: get duration only
        let duration = await getDuration(url: url)
        return ([], duration)
    }

    // MARK: - AVFoundation extraction

    private static func extractViaAVFoundation(url: URL, maxDuration: Double) async throws -> AudioExtractionResult {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds
        let maxSamples = maxDuration.isFinite ? Int(min(duration, maxDuration) * targetSampleRate) : nil

        // Try track-based, then audio mix
        var samples = [Float]()
        if let s = try? await extractViaTrack(asset: asset, maxSamples: maxSamples), !s.isEmpty {
            samples = s
        } else if let s = try? await extractViaAudioMix(asset: asset, maxSamples: maxSamples), !s.isEmpty {
            samples = s
        }

        guard !samples.isEmpty else {
            throw AudioExtractorError.readingFailed("AVFoundation konnte kein Audio lesen")
        }

        if let max = maxSamples, samples.count > max {
            samples = Array(samples.prefix(max))
        }

        return AudioExtractionResult(samples: samples, sampleRate: targetSampleRate, duration: duration)
    }

    // MARK: - ffmpeg fallback (handles damaged files, exotic codecs)

    private static func extractViaFFmpeg(url: URL, maxDuration: Double) async throws -> AudioExtractionResult {
        let ffmpegPath = findFFmpeg()
        guard let ffmpeg = ffmpegPath else {
            throw AudioExtractorError.readingFailed("ffmpeg nicht gefunden — wird für diese Datei benötigt")
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempWav = tempDir.appendingPathComponent("audiosyncer_\(UUID().uuidString).wav")

        defer { try? FileManager.default.removeItem(at: tempWav) }

        // Use ffmpeg to extract audio as PCM WAV
        var args = [
            "-i", url.path,
            "-vn",                          // no video
            "-acodec", "pcm_f32le",         // 32-bit float PCM
            "-ar", "8000",                  // 8kHz sample rate
            "-ac", "1",                     // mono
        ]
        if maxDuration.isFinite {
            args += ["-t", String(maxDuration)]
        }
        args += [
            "-y",                           // overwrite
            tempWav.path
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                guard proc.terminationStatus == 0 else {
                    continuation.resume(throwing: AudioExtractorError.readingFailed(
                        "ffmpeg konnte kein Audio extrahieren (Exit Code \(proc.terminationStatus))"))
                    return
                }

                // Read the WAV file
                Task {
                    do {
                        let result = try await readWavFile(at: tempWav)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AudioExtractorError.readingFailed("ffmpeg konnte nicht gestartet werden: \(error.localizedDescription)"))
            }
        }
    }

    private static func readWavFile(at url: URL) async throws -> AudioExtractionResult {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let audioTrack = try await findAudioTrack(in: asset)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let samples = try readSamples(from: reader, output: output, maxSamples: nil)

        guard !samples.isEmpty else {
            throw AudioExtractorError.readingFailed("Keine Samples in konvertierter WAV-Datei")
        }

        return AudioExtractionResult(samples: samples, sampleRate: targetSampleRate, duration: duration)
    }

    private static func findFFmpeg() -> String? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try which
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path = path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func getDuration(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.duration).seconds) ?? 0
    }

    // MARK: - Track-based extraction

    private static func extractViaTrack(asset: AVURLAsset, maxSamples: Int?) async throws -> [Float] {
        let audioTrack = try await findAudioTrack(in: asset)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        return try readSamples(from: reader, output: output, maxSamples: maxSamples)
    }

    // MARK: - AudioMix extraction

    private static func extractViaAudioMix(asset: AVURLAsset, maxSamples: Int?) async throws -> [Float] {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        var tracks = audioTracks
        if tracks.isEmpty {
            tracks = try await asset.loadTracks(withMediaCharacteristic: .audible)
        }
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

    // MARK: - Shared

    private static func readSamples(from reader: AVAssetReader, output: AVAssetReaderOutput, maxSamples: Int?) throws -> [Float] {
        var allSamples = [Float]()
        if let max = maxSamples { allSamples.reserveCapacity(max) }

        guard reader.startReading() else {
            throw AudioExtractorError.readingFailed(reader.error?.localizedDescription ?? "Unbekannter Fehler")
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
            throw AudioExtractorError.readingFailed(reader.error?.localizedDescription ?? "Lesen fehlgeschlagen")
        }

        reader.cancelReading()
        return allSamples
    }

    private static func downsampleToWaveform(_ samples: [Float], targetCount: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }

        let samplesPerBin = max(1, samples.count / targetCount)
        var waveform = [Float]()
        waveform.reserveCapacity(targetCount)

        for i in stride(from: 0, to: samples.count, by: samplesPerBin) {
            let end = min(i + samplesPerBin, samples.count)
            let slice = samples[i..<end]
            let rms = sqrt(slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count))
            waveform.append(rms)
        }

        return waveform
    }

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
