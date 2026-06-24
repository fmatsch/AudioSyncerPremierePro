import Foundation

enum MediaConverter {

    struct ConversionResult {
        let originalURL: URL
        let convertedURL: URL
    }

    static func convert(url: URL, outputDir: URL,
                         progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        guard let ffmpeg = findFFmpeg() else {
            throw ConversionError.ffmpegNotFound
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName)_ProRes.mov")

        // Remove existing output file
        try? FileManager.default.removeItem(at: outputURL)

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Get duration for progress tracking
        let duration = await getDuration(url: url)

        // Determine if file has video
        let hasVideo = await fileHasVideo(url: url)

        var args: [String]
        if hasVideo {
            args = [
                "-i", url.path,
                "-c:v", "prores_ks",
                "-profile:v", "3",           // ProRes 422 HQ
                "-vendor", "apl0",
                "-pix_fmt", "yuv422p10le",
                "-c:a", "pcm_s24le",          // 24-bit PCM audio
                "-ar", "48000",
                "-y",
                outputURL.path
            ]
        } else {
            // Audio-only: convert to WAV
            let wavOutput = outputDir.appendingPathComponent("\(baseName)_PCM.wav")
            try? FileManager.default.removeItem(at: wavOutput)
            args = [
                "-i", url.path,
                "-c:a", "pcm_s24le",
                "-ar", "48000",
                "-y",
                wavOutput.path
            ]
            return try await runFFmpeg(
                executablePath: ffmpeg, args: args,
                duration: duration, outputURL: wavOutput, progress: progress
            )
        }

        return try await runFFmpeg(
            executablePath: ffmpeg, args: args,
            duration: duration, outputURL: outputURL, progress: progress
        )
    }

    private static func runFFmpeg(executablePath: String, args: [String],
                                   duration: Double, outputURL: URL,
                                   progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice

        // Capture stderr to parse progress
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        // Parse ffmpeg progress output on background thread
        let progressTask = Task.detached {
            let handle = stderrPipe.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                if let text = String(data: buffer, encoding: .utf8) {
                    // Parse time= from ffmpeg output
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
                    // Keep only last 4KB to avoid memory growth
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
        // Format: HH:MM:SS.ms
        let parts = time.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    private static func getDuration(url: URL) async -> Double {
        guard let ffprobe = findFFprobe() else { return 0 }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "quiet",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let dur = Double(str) {
                return dur
            }
        } catch {}
        return 0
    }

    private static func fileHasVideo(url: URL) async -> Bool {
        guard let ffprobe = findFFprobe() else {
            let ext = url.pathExtension.lowercased()
            return ["mp4", "mov", "m4v", "avi", "mxf", "insv", "mkv"].contains(ext)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "quiet",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_type",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return str == "video"
        } catch {}
        return false
    }

    private static func findFFmpeg() -> String? {
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private static func findFFprobe() -> String? {
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
