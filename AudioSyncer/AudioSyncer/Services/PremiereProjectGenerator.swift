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

        let allOffsets = cameras.map { $0.offsetSeconds ?? 0.0 }
        let earliestOffset = min(0, allOffsets.min() ?? 0)

        let masterStart = frames(seconds: abs(earliestOffset), fps: settings.frameRate)
        let masterDuration = frames(seconds: audioMaster.duration, fps: settings.frameRate)

        let totalDuration = calculateTotalDuration(
            audioMaster: audioMaster, cameras: cameras,
            fps: settings.frameRate, earliestOffset: earliestOffset
        )

        // Build multiclip angles for each camera
        var angles = ""
        for (index, camera) in cameras.enumerated() {
            let offset = camera.offsetSeconds ?? 0.0
            let clipStart = frames(seconds: offset - earliestOffset, fps: settings.frameRate)
            let clipDuration = frames(seconds: camera.duration, fps: settings.frameRate)
            let camFileURL = fileURL(camera.effectiveURL.path)
            let fileID = "file-cam-\(index + 1)"

            let fileDef = fileDefinition(
                id: fileID, name: camera.fileName,
                pathurl: camFileURL,
                duration: clipDuration, timebase: timebase, ntsc: ntsc,
                width: settings.width, height: settings.height
            )
            let fileRef = "<file id=\"\(fileID)\"/>"

            angles += """
                                        <angle>
                                            <name>\(esc(camera.role.rawValue))</name>
                                            <clip id="clip-angle-\(index + 1)">
                                                <name>\(esc(camera.role.rawValue))</name>
                                                <duration>\(totalDuration)</duration>
                                                <rate>
                                                    <timebase>\(timebase)</timebase>
                                                    <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                                </rate>
                                                <media>
                                                    <video>
                                                        <track>
                                                            <clipitem id="clipitem-angle\(index + 1)-v">
                                                                <name>\(esc(camera.fileName))</name>
                                                                <enabled>TRUE</enabled>
                                                                <duration>\(clipDuration)</duration>
                                                                <rate>
                                                                    <timebase>\(timebase)</timebase>
                                                                    <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                                                </rate>
                                                                <start>\(clipStart)</start>
                                                                <end>\(clipStart + clipDuration)</end>
                                                                <in>0</in>
                                                                <out>\(clipDuration)</out>
                                                                \(fileDef)
                                                            </clipitem>
                                                        </track>
                                                    </video>
                                                    <audio>
                                                        <track>
                                                            <clipitem id="clipitem-angle\(index + 1)-a">
                                                                <name>\(esc(camera.fileName))</name>
                                                                <enabled>TRUE</enabled>
                                                                <duration>\(clipDuration)</duration>
                                                                <rate>
                                                                    <timebase>\(timebase)</timebase>
                                                                    <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                                                </rate>
                                                                <start>\(clipStart)</start>
                                                                <end>\(clipStart + clipDuration)</end>
                                                                <in>0</in>
                                                                <out>\(clipDuration)</out>
                                                                \(fileRef)
                                                                <sourcetrack>
                                                                    <mediatype>audio</mediatype>
                                                                    <trackindex>1</trackindex>
                                                                </sourcetrack>
                                                            </clipitem>
                                                        </track>
                                                    </audio>
                                                </media>
                                            </clip>
                                        </angle>

            """
        }

        // Audio master angle
        let masterFileURL = fileURL(audioMaster.effectiveURL.path)
        let masterFileDef = fileDefinition(
            id: "file-master", name: audioMaster.fileName,
            pathurl: masterFileURL,
            duration: masterDuration, timebase: timebase, ntsc: ntsc,
            width: nil, height: nil
        )

        angles += """
                                        <angle>
                                            <name>Audio Master</name>
                                            <clip id="clip-angle-master">
                                                <name>Audio Master</name>
                                                <duration>\(totalDuration)</duration>
                                                <rate>
                                                    <timebase>\(timebase)</timebase>
                                                    <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                                </rate>
                                                <media>
                                                    <audio>
                                                        <track>
                                                            <clipitem id="clipitem-angle-master-a">
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
                                                    </audio>
                                                </media>
                                            </clip>
                                        </angle>
        """

        // Sequence audio tracks reference the multiclip
        var audioTracks = ""
        for ch in 1...2 {
            audioTracks += """
                                <track>
                                    <clipitem id="clipitem-seq-a\(ch)">
                                        <name>\(esc(settings.projectName))</name>
                                        <enabled>TRUE</enabled>
                                        <duration>\(totalDuration)</duration>
                                        <rate>
                                            <timebase>\(timebase)</timebase>
                                            <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                        </rate>
                                        <start>0</start>
                                        <end>\(totalDuration)</end>
                                        <in>0</in>
                                        <out>\(totalDuration)</out>
                                        <multiclip id="multiclip-1"/>
                                        <sourcetrack>
                                            <mediatype>audio</mediatype>
                                            <trackindex>\(ch)</trackindex>
                                        </sourcetrack>
                                    </clipitem>
                                </track>

            """
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
                            <clipitem id="clipitem-seq-v">
                                <name>\(esc(settings.projectName))</name>
                                <enabled>TRUE</enabled>
                                <duration>\(totalDuration)</duration>
                                <rate>
                                    <timebase>\(timebase)</timebase>
                                    <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                </rate>
                                <start>0</start>
                                <end>\(totalDuration)</end>
                                <in>0</in>
                                <out>\(totalDuration)</out>
                                <multiclip id="multiclip-1" collapse="TRUE">
                                    <name>\(esc(settings.projectName)) Multicam</name>
                                    <duration>\(totalDuration)</duration>
                                    <rate>
                                        <timebase>\(timebase)</timebase>
                                        <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                                    </rate>
        \(angles)
                                </multiclip>
                            </clipitem>
                        </track>
                    </video>
                    <audio>
                        <numOutputChannels>2</numOutputChannels>
                        <format>
                            <samplecharacteristics>
                                <depth>16</depth>
                                <samplerate>48000</samplerate>
                            </samplecharacteristics>
                        </format>
        \(audioTracks)
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
        var media = ""
        if let w = width, let h = height {
            media += """
                <video>
                    <samplecharacteristics>
                        <width>\(w)</width>
                        <height>\(h)</height>
                    </samplecharacteristics>
                </video>

            """
        }
        media += """
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
                \(media)
            </media>
        </file>
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
