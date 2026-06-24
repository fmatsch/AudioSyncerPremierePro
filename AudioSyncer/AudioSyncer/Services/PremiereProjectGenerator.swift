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
        let masterDurationFrames = Int(audioMaster.duration * settings.frameRate)

        var fileDefinitions = ""
        var masterClipNodes = ""
        var videoTrackItems = ""
        var audioTrackItems = ""

        // Audio Master file + masterclip
        fileDefinitions += fileNode(id: "file-1", name: audioMaster.fileName, path: audioMaster.url.path,
                                     duration: frameDuration(audioMaster.duration, fps: settings.frameRate),
                                     timebase: timebase, ntsc: ntsc, width: nil, height: nil)

        masterClipNodes += masterClipNode(id: "masterclip-1", fileRef: "file-1", name: audioMaster.fileName,
                                           duration: frameDuration(audioMaster.duration, fps: settings.frameRate),
                                           timebase: timebase, ntsc: ntsc, hasVideo: false, hasAudio: true)

        // Audio master on audio track
        audioTrackItems += """
                                <clipitem id="clipitem-audio-1">
                                    <masterclipid>masterclip-1</masterclipid>
                                    <name>\(esc(audioMaster.fileName))</name>
                                    <enabled>TRUE</enabled>
                                    <duration>\(frameDuration(audioMaster.duration, fps: settings.frameRate))</duration>
                                    <rate><timebase>\(timebase)</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                                    <start>0</start>
                                    <end>\(masterDurationFrames)</end>
                                    <in>0</in>
                                    <out>\(frameDuration(audioMaster.duration, fps: settings.frameRate))</out>
                                    <file id="file-1"/>
                                    <sourcetrack><mediatype>audio</mediatype><trackindex>1</trackindex></sourcetrack>
                                </clipitem>

        """

        // Camera files
        for (index, camera) in cameras.enumerated() {
            let fileID = "file-\(index + 2)"
            let mcID = "masterclip-\(index + 2)"
            let clipItemID = "clipitem-cam-\(index + 1)"
            let audioClipItemID = "clipitem-camaudio-\(index + 1)"
            let offsetSeconds = camera.offsetSeconds ?? 0.0
            let startFrame = max(0, Int(offsetSeconds * settings.frameRate))
            let clipDurationFrames = frameDuration(camera.duration, fps: settings.frameRate)
            let endFrame = startFrame + clipDurationFrames

            fileDefinitions += fileNode(id: fileID, name: camera.fileName, path: camera.url.path,
                                         duration: clipDurationFrames,
                                         timebase: timebase, ntsc: ntsc,
                                         width: settings.width, height: settings.height)

            masterClipNodes += masterClipNode(id: mcID, fileRef: fileID, name: camera.fileName,
                                               duration: clipDurationFrames,
                                               timebase: timebase, ntsc: ntsc, hasVideo: true, hasAudio: true)

            videoTrackItems += """
                                <clipitem id="\(clipItemID)">
                                    <masterclipid>\(mcID)</masterclipid>
                                    <name>\(esc(camera.fileName))</name>
                                    <enabled>TRUE</enabled>
                                    <duration>\(clipDurationFrames)</duration>
                                    <rate><timebase>\(timebase)</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                                    <start>\(startFrame)</start>
                                    <end>\(endFrame)</end>
                                    <in>0</in>
                                    <out>\(clipDurationFrames)</out>
                                    <file id="\(fileID)"/>
                                </clipitem>

            """

            audioTrackItems += """
                                <clipitem id="\(audioClipItemID)">
                                    <masterclipid>\(mcID)</masterclipid>
                                    <name>\(esc(camera.fileName))</name>
                                    <enabled>TRUE</enabled>
                                    <duration>\(clipDurationFrames)</duration>
                                    <rate><timebase>\(timebase)</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                                    <start>\(startFrame)</start>
                                    <end>\(endFrame)</end>
                                    <in>0</in>
                                    <out>\(clipDurationFrames)</out>
                                    <file id="\(fileID)"/>
                                    <sourcetrack><mediatype>audio</mediatype><trackindex>1</trackindex></sourcetrack>
                                </clipitem>

            """
        }

        let totalDurationFrames = calculateTotalDuration(audioMaster: audioMaster, cameras: cameras, fps: settings.frameRate)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="4">
            <project>
                <name>\(esc(settings.projectName))</name>
                <children>
                    <bin>
                        <name>Media</name>
                        <children>
        \(masterClipNodes)
                        </children>
                    </bin>
                    <sequence id="sequence-1">
                        <uuid>\(UUID().uuidString)</uuid>
                        <name>Multicam Edit</name>
                        <duration>\(totalDurationFrames)</duration>
                        <rate>
                            <timebase>\(timebase)</timebase>
                            <ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc>
                        </rate>
                        <timecode>
                            <rate><timebase>\(timebase)</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
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
                                        <rate><timebase>\(timebase)</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                                        <codec>
                                            <name>Apple ProRes 422</name>
                                            <appspecificdata>
                                                <appname>Final Cut Pro</appname>
                                                <appmanufacturer>Apple Inc.</appmanufacturer>
                                                <data>
                                                    <qtcodec>
                                                        <codecname>Apple ProRes 422</codecname>
                                                        <codectypecode>apcn</codectypecode>
                                                    </qtcodec>
                                                </data>
                                            </appspecificdata>
                                        </codec>
                                    </samplecharacteristics>
                                </format>
                                <track>
        \(videoTrackItems)
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
                                <track>
        \(audioTrackItems)
                                </track>
                            </audio>
                        </media>
                    </sequence>
                </children>
            </project>
        </xmeml>
        """

        guard let xmlData = xml.data(using: .utf8) else {
            throw GeneratorError.encodingFailed
        }

        try xmlData.write(to: outputURL)
    }

    private static func fileNode(id: String, name: String, path: String, duration: Int,
                                  timebase: Int, ntsc: Bool, width: Int?, height: Int?) -> String {
        let pathURL = "file://localhost" + esc(path).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            .replacingOccurrences(of: "%2F", with: "/")
        let videoMedia = width != nil ? """
                                <video>
                                    <samplecharacteristics>
                                        <width>\(width!)</width>
                                        <height>\(height!)</height>
                                    </samplecharacteristics>
                                </video>
        """ : ""

        return """
                        <clip id="\(id)-clip" frameBlend="FALSE">
                            <name>\(esc(name))</name>
                            <duration>\(duration)</duration>
                            <rate><timebase>\(timebase)</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                            <file id="\(id)">
                                <name>\(esc(name))</name>
                                <pathurl>\(pathURL)</pathurl>
                                <rate><timebase>\(timebase)</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                                <duration>\(duration)</duration>
                                <media>
        \(videoMedia)
                                    <audio>
                                        <samplecharacteristics>
                                            <depth>16</depth>
                                            <samplerate>48000</samplerate>
                                        </samplecharacteristics>
                                        <channelcount>2</channelcount>
                                    </audio>
                                </media>
                            </file>
                        </clip>

        """
    }

    private static func masterClipNode(id: String, fileRef: String, name: String, duration: Int,
                                        timebase: Int, ntsc: Bool, hasVideo: Bool, hasAudio: Bool) -> String {
        return """
                        <clip id="\(id)" frameBlend="FALSE">
                            <uuid>\(UUID().uuidString)</uuid>
                            <masterclipid>\(id)</masterclipid>
                            <name>\(esc(name))</name>
                            <duration>\(duration)</duration>
                            <rate><timebase>\(timebase)</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                            <ismasterclip>TRUE</ismasterclip>
                            <file id="\(fileRef)"/>
                        </clip>

        """
    }

    private static func calculateTotalDuration(audioMaster: MediaFile, cameras: [MediaFile], fps: Double) -> Int {
        var maxEnd = audioMaster.duration
        for camera in cameras {
            let offset = camera.offsetSeconds ?? 0.0
            let end = offset + camera.duration
            maxEnd = max(maxEnd, end)
        }
        return Int(maxEnd * fps)
    }

    private static func frameDuration(_ seconds: Double, fps: Double) -> Int {
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
