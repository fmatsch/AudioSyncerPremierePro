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

        // Calculate the earliest offset to determine timeline zero point
        let allOffsets = cameras.map { $0.offsetSeconds ?? 0.0 }
        let earliestOffset = min(0, allOffsets.min() ?? 0)

        // Timeline positions: shift everything so the earliest clip starts at 0
        let masterStart = Int(abs(earliestOffset) * settings.frameRate)
        let masterDuration = frames(seconds: audioMaster.duration, fps: settings.frameRate)

        let totalDuration = calculateTotalDuration(
            audioMaster: audioMaster, cameras: cameras,
            fps: settings.frameRate, earliestOffset: earliestOffset
        )

        var videoTrackItems = ""
        var audioTrackItems = ""
        var cameraAudioTrackItems = ""

        // Audio master on audio track 1
        let masterFileURL = fileURL(audioMaster.effectiveURL.path)
        audioTrackItems += clipitem(
            id: "clipitem-audio-master",
            name: audioMaster.fileName,
            fileID: "file-master",
            fileDefinition: fileDefinition(
                id: "file-master", name: audioMaster.fileName,
                pathurl: masterFileURL,
                duration: masterDuration, timebase: timebase, ntsc: ntsc,
                width: nil, height: nil
            ),
            duration: masterDuration, timebase: timebase, ntsc: ntsc,
            start: masterStart, end: masterStart + masterDuration,
            inPoint: 0, outPoint: masterDuration,
            sourceTrack: "audio", trackIndex: 1
        )

        // Camera clips
        for (index, camera) in cameras.enumerated() {
            let offset = camera.offsetSeconds ?? 0.0
            let timelineStart = Int((offset - earliestOffset) * settings.frameRate)
            let clipDuration = frames(seconds: camera.duration, fps: settings.frameRate)
            let camFileURL = fileURL(camera.effectiveURL.path)
            let fileID = "file-cam-\(index + 1)"

            let fileDef = fileDefinition(
                id: fileID, name: camera.fileName,
                pathurl: camFileURL,
                duration: clipDuration, timebase: timebase, ntsc: ntsc,
                width: settings.width, height: settings.height
            )

            // Video track
            videoTrackItems += clipitem(
                id: "clipitem-video-\(index + 1)",
                name: camera.fileName,
                fileID: fileID,
                fileDefinition: fileDef,
                duration: clipDuration, timebase: timebase, ntsc: ntsc,
                start: timelineStart, end: timelineStart + clipDuration,
                inPoint: 0, outPoint: clipDuration,
                sourceTrack: nil, trackIndex: nil
            )

            // Camera audio track
            cameraAudioTrackItems += clipitem(
                id: "clipitem-camaudio-\(index + 1)",
                name: camera.fileName,
                fileID: fileID,
                fileDefinition: nil,
                duration: clipDuration, timebase: timebase, ntsc: ntsc,
                start: timelineStart, end: timelineStart + clipDuration,
                inPoint: 0, outPoint: clipDuration,
                sourceTrack: "audio", trackIndex: 1
            )
        }

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
                        <track>
        \(videoTrackItems)                </track>
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
        \(audioTrackItems)                </track>
                        <track>
        \(cameraAudioTrackItems)                </track>
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
        let videoMedia: String
        if let w = width, let h = height {
            videoMedia = """
                                            <video>
                                                <samplecharacteristics>
                                                    <width>\(w)</width>
                                                    <height>\(h)</height>
                                                </samplecharacteristics>
                                            </video>
            """
        } else {
            videoMedia = ""
        }

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
        \(videoMedia)                                    <audio>
                                                <samplecharacteristics>
                                                    <depth>16</depth>
                                                    <samplerate>48000</samplerate>
                                                </samplecharacteristics>
                                                <channelcount>2</channelcount>
                                            </audio>
                                        </media>
                                    </file>
        """
    }

    private static func clipitem(id: String, name: String, fileID: String,
                                  fileDefinition: String?,
                                  duration: Int, timebase: Int, ntsc: Bool,
                                  start: Int, end: Int,
                                  inPoint: Int, outPoint: Int,
                                  sourceTrack: String?, trackIndex: Int?) -> String {
        let fileRef = fileDefinition ?? "                    <file id=\"\(fileID)\"/>"
        let sourceTrackXML: String
        if let st = sourceTrack, let ti = trackIndex {
            sourceTrackXML = """
                                    <sourcetrack>
                                        <mediatype>\(st)</mediatype>
                                        <trackindex>\(ti)</trackindex>
                                    </sourcetrack>
            """
        } else {
            sourceTrackXML = ""
        }

        return """
                                <clipitem id="\(id)">
                                    <name>\(esc(name))</name>
                                    <enabled>TRUE</enabled>
                                    <duration>\(duration)</duration>
                                    <rate>
                                        <timebase>\(timebase)</timebase>
                                        <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                    </rate>
                                    <start>\(start)</start>
                                    <end>\(end)</end>
                                    <in>\(inPoint)</in>
                                    <out>\(outPoint)</out>
        \(fileRef)
        \(sourceTrackXML)                </clipitem>
        """
    }

    private static func calculateTotalDuration(audioMaster: MediaFile, cameras: [MediaFile],
                                                fps: Double, earliestOffset: Double) -> Int {
        var maxEnd = abs(earliestOffset) + audioMaster.duration
        for camera in cameras {
            let offset = camera.offsetSeconds ?? 0.0
            let end = (offset - earliestOffset) + camera.duration
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
