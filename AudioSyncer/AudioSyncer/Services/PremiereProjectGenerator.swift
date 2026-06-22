import Foundation
import AVFoundation
import Compression

enum PremiereProjectGenerator {

    static func generate(
        audioMaster: MediaFile,
        cameras: [MediaFile],
        settings: ProjectSettings,
        outputURL: URL
    ) async throws {
        let timebase = Int(settings.frameRate * 100)
        let ntsc = [29.97, 23.976, 59.94].contains(settings.frameRate)
        let ticksPerFrame: Int64 = 254016000000 / Int64(round(settings.frameRate))

        let allFiles = [audioMaster] + cameras
        var clipNodes = ""
        var masterClipNodes = ""
        var multicamTrackEntries = ""

        let masterDuration = audioMaster.duration
        let masterDurationTicks = Int64(masterDuration * 254016000000)
        let masterDurationFrames = Int(masterDuration * settings.frameRate)

        for (index, file) in allFiles.enumerated() {
            let clipID = "clip-\(index + 1)"
            let masterClipID = "masterclip-\(index + 1)"
            let fileID = "file-\(index + 1)"
            let filePath = file.url.path
            let fileName = file.fileName
            let isAudio = file.role.isAudioMaster
            let offsetSeconds = file.offsetSeconds ?? 0.0
            let offsetTicks = Int64(offsetSeconds * 254016000000)
            let fileDuration = file.duration
            let fileDurationTicks = Int64(fileDuration * 254016000000)

            clipNodes += """
            <clip id="\(clipID)" premiereVersion="1">
                <masterclipid>\(masterClipID)</masterclipid>
                <name>\(escapeXML(fileName))</name>
                <duration>\(Int(fileDuration * settings.frameRate))</duration>
                <rate><timebase>\(Int(settings.frameRate))</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                <file id="\(fileID)">
                    <name>\(escapeXML(fileName))</name>
                    <pathurl>file://localhost\(escapeXML(filePath))</pathurl>
                    <duration>\(Int(fileDuration * settings.frameRate))</duration>
                    <rate><timebase>\(Int(settings.frameRate))</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                    <media>
                        \(isAudio ? "" : "<video><samplecharacteristics><width>\(settings.width)</width><height>\(settings.height)</height></samplecharacteristics></video>")
                        <audio><samplecharacteristics><samplerate>48000</samplerate><depth>16</depth></samplecharacteristics></audio>
                    </media>
                </file>
            </clip>

            """

            masterClipNodes += """
            <clip id="\(masterClipID)" premiereVersion="1">
                <name>\(escapeXML(fileName))</name>
                <duration>\(Int(fileDuration * settings.frameRate))</duration>
                <rate><timebase>\(Int(settings.frameRate))</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                <file id="\(fileID)"/>
                <ismasterclip>TRUE</ismasterclip>
            </clip>

            """

            if !isAudio {
                let startTicks = max(0, -offsetTicks)
                let endTicks = startTicks + fileDurationTicks
                let trackStart = max(0, offsetTicks)

                multicamTrackEntries += """
                <track>
                    <clipitem id="multicam-\(clipID)" premiereVersion="1">
                        <masterclipid>\(masterClipID)</masterclipid>
                        <name>\(escapeXML(fileName))</name>
                        <start>\(ticksToFrames(trackStart, fps: settings.frameRate))</start>
                        <end>\(ticksToFrames(trackStart + fileDurationTicks, fps: settings.frameRate))</end>
                        <in>\(0)</in>
                        <out>\(Int(fileDuration * settings.frameRate))</out>
                        <file id="\(fileID)"/>
                    </clipitem>
                </track>

                """
            }
        }

        let audioMasterOffset = audioMaster.offsetSeconds ?? 0.0
        let audioTrackStart = max(0, Int64(audioMasterOffset * 254016000000))

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="4">
            <project>
                <name>\(escapeXML(settings.projectName))</name>
                <children>
                    <bin>
                        <name>Media</name>
                        <children>
                            \(masterClipNodes)
                        </children>
                    </bin>

                    <sequence id="multicam-sequence" premiereVersion="1">
                        <name>Multicam Sequence</name>
                        <duration>\(masterDurationFrames)</duration>
                        <rate><timebase>\(Int(settings.frameRate))</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                        <media>
                            <video>
                                <format>
                                    <samplecharacteristics>
                                        <width>\(settings.width)</width>
                                        <height>\(settings.height)</height>
                                        <pixelaspectratio>square</pixelaspectratio>
                                        <rate><timebase>\(Int(settings.frameRate))</timebase><ntsc>\(ntsc ? "TRUE" : "FALSE")</ntsc></rate>
                                    </samplecharacteristics>
                                </format>
                                \(multicamTrackEntries)
                            </video>
                            <audio>
                                <format>
                                    <samplecharacteristics>
                                        <samplerate>48000</samplerate>
                                        <depth>16</depth>
                                    </samplecharacteristics>
                                </format>
                                <track>
                                    <clipitem id="audio-master-item" premiereVersion="1">
                                        <masterclipid>masterclip-1</masterclipid>
                                        <name>\(escapeXML(audioMaster.fileName))</name>
                                        <start>0</start>
                                        <end>\(masterDurationFrames)</end>
                                        <in>0</in>
                                        <out>\(masterDurationFrames)</out>
                                        <file id="file-1"/>
                                    </clipitem>
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

        let compressedData = try compress(data: xmlData)
        try compressedData.write(to: outputURL)
    }

    private static func ticksToFrames(_ ticks: Int64, fps: Double) -> Int {
        Int(Double(ticks) / 254016000000 * fps)
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func compress(data: Data) throws -> Data {
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count + 1024)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { (sourceBytes: UnsafeRawBufferPointer) -> Int in
            guard let baseAddress = sourceBytes.baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                data.count + 1024,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { throw GeneratorError.compressionFailed }

        // Wrap in gzip format
        var gzipData = Data()
        gzipData.append(contentsOf: [0x1f, 0x8b]) // magic
        gzipData.append(0x08) // deflate
        gzipData.append(0x00) // flags
        gzipData.append(contentsOf: [0, 0, 0, 0]) // mtime
        gzipData.append(0x00) // xfl
        gzipData.append(0xff) // OS
        gzipData.append(Data(bytes: destinationBuffer, count: compressedSize))

        // CRC32 and size
        let crc = crc32(data)
        var crcLE = crc.littleEndian
        gzipData.append(Data(bytes: &crcLE, count: 4))
        var sizeLE = UInt32(data.count & 0xFFFFFFFF).littleEndian
        gzipData.append(Data(bytes: &sizeLE, count: 4))

        return gzipData
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table = makeCRC32Table()
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func makeCRC32Table() -> [UInt32] {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
            }
            return crc
        }
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
