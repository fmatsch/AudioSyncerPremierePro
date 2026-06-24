import Foundation

enum ConversionQuality: String, CaseIterable, Identifiable {
    case proResHQ = "ProRes 422 HQ"
    case proRes = "ProRes 422"
    case proResLT = "ProRes 422 LT"

    var id: String { rawValue }

    var vtProfile: String {
        switch self {
        case .proResHQ: return "3"
        case .proRes: return "2"
        case .proResLT: return "1"
        }
    }

    var swProfile: String {
        switch self {
        case .proResHQ: return "3"
        case .proRes: return "2"
        case .proResLT: return "1"
        }
    }

    var description: String {
        switch self {
        case .proResHQ: return "Beste Qualität, größte Dateien"
        case .proRes: return "Gute Qualität, moderate Größe"
        case .proResLT: return "Gute Qualität, kleinste Dateien"
        }
    }

    var fileSuffix: String {
        switch self {
        case .proResHQ: return "_ProResHQ"
        case .proRes: return "_ProRes"
        case .proResLT: return "_ProResLT"
        }
    }

    // Approximate bitrates in Mbit/s for 1080p
    func estimatedBitrateMbps(width: Int, height: Int, fps: Double) -> Double {
        let pixelCount = Double(width * height)
        let ref1080p = 1920.0 * 1080.0
        let scaleFactor = pixelCount / ref1080p
        let fpsScale = fps / 25.0

        let baseMbps: Double
        switch self {
        case .proResHQ: baseMbps = 220
        case .proRes: baseMbps = 147
        case .proResLT: baseMbps = 102
        }

        return baseMbps * scaleFactor * fpsScale
    }

    func estimatedFileSize(durationSeconds: Double, width: Int, height: Int, fps: Double) -> Int64 {
        let mbps = estimatedBitrateMbps(width: width, height: height, fps: fps)
        let bytes = (mbps * 1_000_000.0 / 8.0) * durationSeconds
        return Int64(bytes)
    }
}

enum MediaConverter {

    struct ConversionResult {
        let originalURL: URL
        let convertedURL: URL
    }

    struct FileInfo {
        let duration: Double
        let width: Int
        let height: Int
        let fps: Double
        let hasVideo: Bool
    }

    static func getFileInfo(url: URL) async -> FileInfo {
        guard let ffprobe = findFFprobe() else {
            return FileInfo(duration: 0, width: 1920, height: 1080, fps: 25, hasVideo: true)
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "quiet",
            "-show_entries", "format=duration:stream=codec_type,width,height,r_frame_rate",
            "-of", "json",
            url.path
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var duration = 0.0
                var width = 1920, height = 1080
                var fps = 25.0
                var hasVideo = false

                if let format = json["format"] as? [String: Any],
                   let durStr = format["duration"] as? String {
                    duration = Double(durStr) ?? 0
                }

                if let streams = json["streams"] as? [[String: Any]] {
                    for stream in streams {
                        if stream["codec_type"] as? String == "video" {
                            hasVideo = true
                            if let w = stream["width"] as? Int { width = w }
                            if let h = stream["height"] as? Int { height = h }
                            if let rateStr = stream["r_frame_rate"] as? String {
                                let parts = rateStr.split(separator: "/")
                                if parts.count == 2,
                                   let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                                    fps = num / den
                                }
                            }
                        }
                    }
                }

                return FileInfo(duration: duration, width: width, height: height, fps: fps, hasVideo: hasVideo)
            }
        } catch {}

        return FileInfo(duration: 0, width: 1920, height: 1080, fps: 25, hasVideo: true)
    }

    static func convert(url: URL, outputDir: URL, quality: ConversionQuality,
                         progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        guard let ffmpeg = findFFmpeg() else {
            throw ConversionError.ffmpegNotFound
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName)\(quality.fileSuffix).mov")

        try? FileManager.default.removeItem(at: outputURL)

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let info = await getFileInfo(url: url)

        if !info.hasVideo {
            let wavOutput = outputDir.appendingPathComponent("\(baseName)_PCM.wav")
            try? FileManager.default.removeItem(at: wavOutput)
            let args = [
                "-i", url.path,
                "-c:a", "pcm_s24le",
                "-ar", "48000",
                "-y",
                wavOutput.path
            ]
            return try await runFFmpeg(
                executablePath: ffmpeg, args: args,
                duration: info.duration, outputURL: wavOutput, progress: progress
            )
        }

        // Video: try hardware encoder first, fall back to software
        let useHW = await hasVideoToolbox(ffmpegPath: ffmpeg)
        if useHW {
            let hwArgs = [
                "-i", url.path,
                "-c:v", "prores_videotoolbox",
                "-profile:v", quality.vtProfile,
                "-c:a", "pcm_s24le",
                "-ar", "48000",
                "-y",
                outputURL.path
            ]
            do {
                return try await runFFmpeg(
                    executablePath: ffmpeg, args: hwArgs,
                    duration: info.duration, outputURL: outputURL, progress: progress
                )
            } catch {
                NSLog("[AudioSyncer] VideoToolbox failed for %@, falling back to software encoder", url.lastPathComponent)
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        // Software encoder fallback
        let swArgs = [
            "-i", url.path,
            "-c:v", "prores_ks",
            "-profile:v", quality.swProfile,
            "-vendor", "apl0",
            "-pix_fmt", "yuv422p10le",
            "-c:a", "pcm_s24le",
            "-ar", "48000",
            "-y",
            outputURL.path
        ]

        return try await runFFmpeg(
            executablePath: ffmpeg, args: swArgs,
            duration: info.duration, outputURL: outputURL, progress: progress
        )
    }

    private static func runFFmpeg(executablePath: String, args: [String],
                                   duration: Double, outputURL: URL,
                                   progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        let progressTask = Task.detached {
            let handle = stderrPipe.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                if let text = String(data: buffer, encoding: .utf8) {
                    if let range = text.range(of: "time=", options: .backwards) {
                        let after = text[range.upperBound...]
                        if let spaceIdx = after.firstIndex(of: " ") {
                            let timeStr = String(after[after.startIndex..<spaceIdx])
                            if let secs = parseFFmpegTime(timeStr), duration > 0 {
                                let pct = min(secs / duration, 1.0)
                                await MainActor.run { progress(pct) }
                            }
                        }
                    }
                    if buffer.count > 4096 {
                        buffer = Data(buffer.suffix(2048))
                    }
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                progressTask.cancel()

                guard proc.terminationStatus == 0 else {
                    continuation.resume(throwing: ConversionError.conversionFailed(
                        "ffmpeg Exit Code \(proc.terminationStatus)"))
                    return
                }

                let originalURL = URL(fileURLWithPath: args[args.firstIndex(of: "-i")! + 1])
                continuation.resume(returning: ConversionResult(
                    originalURL: originalURL, convertedURL: outputURL))
            }

            do {
                try process.run()
            } catch {
                progressTask.cancel()
                continuation.resume(throwing: ConversionError.conversionFailed(error.localizedDescription))
            }
        }
    }

    private static func parseFFmpegTime(_ time: String) -> Double? {
        let parts = time.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    private static func hasVideoToolbox(ffmpegPath: String) async -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-encoders"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains("prores_videotoolbox")
        } catch {
            return false
        }
    }

    static func findFFmpeg() -> String? {
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static func findFFprobe() -> String? {
        for path in ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

enum ConversionError: LocalizedError {
    case ffmpegNotFound
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound: return "ffmpeg nicht gefunden — bitte installieren (brew install ffmpeg)"
        case .conversionFailed(let msg): return "Konvertierung fehlgeschlagen: \(msg)"
        }
    }
}
