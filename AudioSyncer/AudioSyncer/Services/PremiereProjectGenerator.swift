import Foundation
import AVFoundation

enum PremiereProjectGenerator {

    static func generate(
        audioMaster: MediaFile,
        cameras: [MediaFile],
        settings: ProjectSettings,
        outputURL: URL
    ) async throws {
        let ntsc = [29.97, 23.976, 59.94].contains(settings.frameRate)
        let timebase = ntsc ? Int(round(settings.frameRate * 1000.0 / 1001.0)) : Int(settings.frameRate)

        // Negate offsets: cross-correlation offset convention is opposite to timeline position
        let allTimelineOffsets = cameras.map { -($0.offsetSeconds ?? 0.0) }
        let earliestOffset = min(0, allTimelineOffsets.min() ?? 0)

        let masterStart = frames(seconds: abs(earliestOffset), fps: settings.frameRate)
        let masterDuration = frames(seconds: audioMaster.duration, fps: settings.frameRate)

        let totalDuration = calculateTotalDuration(
            audioMaster: audioMaster, cameras: cameras,
            fps: settings.frameRate, earliestOffset: earliestOffset
        )

        NSLog("[AudioSyncer] XML Export: earliestOffset=%.4f, masterStart=%d frames (%.4fs), totalDuration=%d frames, fps=%.2f",
              earliestOffset, masterStart, Double(masterStart) / settings.frameRate, totalDuration, settings.frameRate)

        // Each camera gets its own video track + audio track
        var videoTracks = ""
        var cameraAudioTracks = ""

        for (index, camera) in cameras.enumerated() {
            let syncOffset = camera.offsetSeconds ?? 0.0
            let timelineOffset = -syncOffset
            let timelineStart = frames(seconds: timelineOffset - earliestOffset, fps: settings.frameRate)
            NSLog("[AudioSyncer] XML Export: %@ syncOffset=%.4f, timelineOffset=%.4f, timelineStart=%d frames (%.4fs)",
                  camera.fileName, syncOffset, timelineOffset, timelineStart, Double(timelineStart) / settings.frameRate)
            let clipDuration = frames(seconds: camera.duration, fps: settings.frameRate)
            let camFileURL = fileURL(camera.effectiveURL.path)
            let fileID = "file-cam-\(index + 1)"

            let fileDef = fileDefinition(
                id: fileID, name: camera.fileName,
                pathurl: camFileURL,
                duration: clipDuration, timebase: timebase, ntsc: ntsc,
                width: settings.width, height: settings.height
            )

            videoTracks += """
                            <track>
                                <clipitem id="clipitem-video-\(index + 1)">
                                    <name>\(esc(camera.fileName))</name>
                                    <enabled>TRUE</enabled>
                                    <duration>\(clipDuration)</duration>
                                    <rate>
                                        <timebase>\(timebase)</timebase>
                                        <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                    </rate>
                                    <start>\(timelineStart)</start>
                                    <end>\(timelineStart + clipDuration)</end>
                                    <in>0</in>
                                    <out>\(clipDuration)</out>
                                    \(fileDef)
                                </clipitem>
                            </track>

            """

            cameraAudioTracks += """
                            <track>
                                <clipitem id="clipitem-camaudio-\(index + 1)">
                                    <name>\(esc(camera.fileName))</name>
                                    <enabled>TRUE</enabled>
                                    <duration>\(clipDuration)</duration>
                                    <rate>
                                        <timebase>\(timebase)</timebase>
                                        <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                    </rate>
                                    <start>\(timelineStart)</start>
                                    <end>\(timelineStart + clipDuration)</end>
                                    <in>0</in>
                                    <out>\(clipDuration)</out>
                                    <file id="\(fileID)"/>
                                    <sourcetrack>
                                        <mediatype>audio</mediatype>
                                        <trackindex>1</trackindex>
                                    </sourcetrack>
                                </clipitem>
                            </track>

            """
        }

        // Audio master
        let masterFileURL = fileURL(audioMaster.effectiveURL.path)
        let masterFileDef = fileDefinition(
            id: "file-master", name: audioMaster.fileName,
            pathurl: masterFileURL,
            duration: masterDuration, timebase: timebase, ntsc: ntsc,
            width: nil, height: nil
        )

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="4">
            <sequence id="sequence-1">
                <uuid>\(UUID().uuidString)</uuid>
                <name>\(esc(settings.projectName))</name>
                <duration>\(totalDuration)</duration>
                <rate>
                    <timebase>\(timebase)</timebase>
                    <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                </rate>
                <timecode>
                    <rate>
                        <timebase>\(timebase)</timebase>
                        <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                    </rate>
                    <string>00:00:00:00</string>
                    <frame>0</frame>
                    <displayformat>NDF</displayformat>
                </timecode>
                <media>
                    <video>
                        <format>
                            <samplecharacteristics>
                                <width>\(settings.width)</width>
                                <height>\(settings.height)</height>
                                <anamorphic>FALSE</anamorphic>
                                <pixelaspectratio>square</pixelaspectratio>
                                <fielddominance>none</fielddominance>
                                <rate>
                                    <timebase>\(timebase)</timebase>
                                    <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                </rate>
                            </samplecharacteristics>
                        </format>
        \(videoTracks)
                    </video>
                    <audio>
                        <numOutputChannels>2</numOutputChannels>
                        <format>
                            <samplecharacteristics>
                                <depth>16</depth>
                                <samplerate>48000</samplerate>
                            </samplecharacteristics>
                        </format>
                        <track>
                            <clipitem id="clipitem-audio-master">
                                <name>\(esc(audioMaster.fileName))</name>
                                <enabled>TRUE</enabled>
                                <duration>\(masterDuration)</duration>
                                <rate>
                                    <timebase>\(timebase)</timebase>
                                    <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                </rate>
                                <start>\(masterStart)</start>
                                <end>\(masterStart + masterDuration)</end>
                                <in>0</in>
                                <out>\(masterDuration)</out>
                                \(masterFileDef)
                                <sourcetrack>
                                    <mediatype>audio</mediatype>
                                    <trackindex>1</trackindex>
                                </sourcetrack>
                            </clipitem>
                        </track>
        \(cameraAudioTracks)
                    </audio>
                </media>
            </sequence>
        </xmeml>
        """

        guard let xmlData = xml.data(using: .utf8) else {
            throw GeneratorError.encodingFailed
        }

        try xmlData.write(to: outputURL)
    }

    // MARK: - Helpers

    private static func fileURL(_ path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    private static func fileDefinition(id: String, name: String, pathurl: String,
                                        duration: Int, timebase: Int, ntsc: Bool,
                                        width: Int?, height: Int?) -> String {
        var mediaContent = ""
        if let w = width, let h = height {
            mediaContent += """
                                        <video>
                                            <samplecharacteristics>
                                                <width>\(w)</width>
                                                <height>\(h)</height>
                                            </samplecharacteristics>
                                        </video>

            """
        }
        mediaContent += """
                                        <audio>
                                            <samplecharacteristics>
                                                <depth>16</depth>
                                                <samplerate>48000</samplerate>
                                            </samplecharacteristics>
                                            <channelcount>2</channelcount>
                                        </audio>
        """

        return """
        <file id="\(id)">
                                        <name>\(esc(name))</name>
                                        <pathurl>\(esc(pathurl))</pathurl>
                                        <rate>
                                            <timebase>\(timebase)</timebase>
                                            <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                        </rate>
                                        <duration>\(duration)</duration>
                                        <media>
        \(mediaContent)
                                        </media>
                                    </file>
        """
    }

    private static func calculateTotalDuration(audioMaster: MediaFile, cameras: [MediaFile],
                                                fps: Double, earliestOffset: Double) -> Int {
        var maxEnd = abs(earliestOffset) + audioMaster.duration
        for camera in cameras {
            let timelineOffset = -(camera.offsetSeconds ?? 0.0)
            let end = (timelineOffset - earliestOffset) + camera.duration
            maxEnd = max(maxEnd, end)
        }
        return Int(maxEnd * fps)
    }

    private static func frames(seconds: Double, fps: Double) -> Int {
        Int(seconds * fps)
    }

    private static func esc(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

enum GeneratorError: LocalizedError {
    case encodingFailed
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "XML-Kodierung fehlgeschlagen"
        case .compressionFailed: return "Komprimierung fehlgeschlagen"
        }
    }
}
