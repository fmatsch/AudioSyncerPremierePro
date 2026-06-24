import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor
class AppViewModel: ObservableObject {
    @Published var audioMaster: MediaFile?
    @Published var cameras: [MediaFile] = []
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0
    @Published var syncStatusMessage = ""
    @Published var showExportPanel = false
    @Published var alertMessage: String?
    @Published var showAlert = false
    @Published var isConverting = false
    @Published var conversionProgress: Double = 0
    @Published var conversionStatusMessage = ""
    @Published var conversionQuality: ConversionQuality = .proRes
    @Published var estimatedTotalSize: Int64 = 0
    @Published var isEstimating = false

    let settings = ProjectSettings()

    var canConvert: Bool {
        let hasFiles = audioMaster != nil || !cameras.isEmpty
        let notBusy = !isConverting && !isSyncing
        return hasFiles && notBusy
    }

    var allConverted: Bool {
        let masterOk = audioMaster?.convertStatus.isConverted ?? true
        let camerasOk = cameras.allSatisfy { $0.convertStatus.isConverted }
        return masterOk && camerasOk
    }

    var allFilesSynced: Bool {
        guard audioMaster != nil, !cameras.isEmpty else { return false }
        return cameras.contains { $0.syncStatus.isSynced }
    }

    var canSync: Bool {
        audioMaster != nil && !cameras.isEmpty && !isSyncing
    }

    func addFile(url: URL, role: MediaRole) {
        let file = MediaFile(url: url, role: role)

        if role.isAudioMaster {
            audioMaster = file
        } else {
            cameras.removeAll { $0.role == role }
            cameras.append(file)
            cameras.sort { $0.role.index < $1.role.index }
        }

        Task {
            await loadWaveform(for: file)
        }
    }

    func removeFile(role: MediaRole) {
        if role.isAudioMaster {
            audioMaster = nil
        } else {
            cameras.removeAll { $0.role == role }
        }
    }

    func nextAvailableCameraRole() -> MediaRole? {
        let usedRoles = Set(cameras.map(\.role))
        return MediaRole.cameras.first { !usedRoles.contains($0) }
    }

    private func loadWaveform(for file: MediaFile) async {
        do {
            let result = try await AudioExtractor.extractWaveformSamples(from: file.url)
            file.waveformSamples = result.samples
            file.duration = result.duration
            objectWillChange.send()
        } catch {
            print("Waveform extraction failed: \(error)")
        }
    }

    func updateEstimate() async {
        isEstimating = true
        var total: Int64 = 0

        var allFiles: [MediaFile] = []
        if let master = audioMaster { allFiles.append(master) }
        allFiles.append(contentsOf: cameras)

        for file in allFiles {
            let info = await MediaConverter.getFileInfo(url: file.url)
            if info.hasVideo {
                total += conversionQuality.estimatedFileSize(
                    durationSeconds: info.duration,
                    width: info.width, height: info.height, fps: info.fps
                )
            } else {
                // Audio: 48kHz * 24bit * 2ch
                total += Int64(info.duration * 48000 * 3 * 2)
            }
        }

        estimatedTotalSize = total
        isEstimating = false
    }

    func startConversion() async {
        let panel = NSOpenPanel()
        panel.title = "Zielordner für konvertierte Dateien wählen"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let outputDir = panel.url else { return }

        isConverting = true
        conversionProgress = 0

        var allFiles: [MediaFile] = []
        if let master = audioMaster { allFiles.append(master) }
        allFiles.append(contentsOf: cameras)

        let total = allFiles.count
        let quality = conversionQuality

        for (index, file) in allFiles.enumerated() {
            file.convertStatus = .converting(progress: 0)
            objectWillChange.send()
            conversionStatusMessage = "\(file.fileName) konvertieren…"

            do {
                let result = try await MediaConverter.convert(
                    url: file.url, outputDir: outputDir, quality: quality
                ) { pct in
                    file.convertStatus = .converting(progress: pct)
                    self.conversionProgress = (Double(index) + pct) / Double(total)
                    self.objectWillChange.send()
                }
                file.convertStatus = .converted(result.convertedURL)
            } catch {
                file.convertStatus = .failed(error.localizedDescription)
            }

            conversionProgress = Double(index + 1) / Double(total)
            objectWillChange.send()
        }

        let convertedCount = allFiles.filter { $0.convertStatus.isConverted }.count
        let failedCount = allFiles.filter { if case .failed = $0.convertStatus { return true }; return false }.count

        if failedCount > 0 {
            conversionStatusMessage = "\(convertedCount) konvertiert, \(failedCount) fehlgeschlagen"
        } else {
            conversionStatusMessage = "Alle Dateien konvertiert (\(quality.rawValue))"
        }

        isConverting = false
    }

    func startSync() async {
        guard let master = audioMaster, !cameras.isEmpty else { return }

        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "Audio vom Master extrahieren…"

        do {
            let masterAudio = try await AudioExtractor.extract(from: master.url)

            for (index, camera) in cameras.enumerated() {
                camera.syncStatus = .extractingAudio
                objectWillChange.send()
                syncStatusMessage = "Audio von \(camera.role.rawValue) extrahieren…"

                do {
                    let cameraAudio = try await AudioExtractor.extract(from: camera.url)

                    camera.syncStatus = .syncing
                    objectWillChange.send()
                    syncStatusMessage = "\(camera.role.rawValue) synchronisieren…"

                    let result = await Task.detached(priority: .userInitiated) {
                        AudioSyncEngine.findOffset(
                            master: masterAudio.samples,
                            camera: cameraAudio.samples,
                            sampleRate: masterAudio.sampleRate
                        )
                    }.value

                    camera.syncStatus = .synced(offsetSeconds: result.offsetSeconds)
                } catch {
                    camera.syncStatus = .failed(error.localizedDescription)
                }

                syncProgress = Double(index + 1) / Double(cameras.count)
                objectWillChange.send()
            }

            let syncedCount = cameras.filter { $0.syncStatus.isSynced }.count
            let failedCount = cameras.filter { if case .failed = $0.syncStatus { return true }; return false }.count

            if failedCount > 0 {
                syncStatusMessage = "\(syncedCount) synced, \(failedCount) fehlgeschlagen"
            } else {
                syncStatusMessage = "Synchronisation abgeschlossen"
            }

            await detectVideoProperties()

        } catch {
            syncStatusMessage = "Fehler: \(error.localizedDescription)"
            objectWillChange.send()
        }

        isSyncing = false
    }

    private func detectVideoProperties() async {
        guard let firstCamera = cameras.first else { return }
        let asset = AVURLAsset(url: firstCamera.url)
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let size = try? await track.load(.naturalSize)
            if let size = size {
                settings.width = Int(size.width)
                settings.height = Int(size.height)
            }
            let rate = try? await track.load(.nominalFrameRate)
            if let rate = rate, rate > 0 {
                let closest = ProjectSettings.supportedFrameRates.min(by: {
                    abs($0 - Double(rate)) < abs($1 - Double(rate))
                })
                if let closest = closest {
                    settings.frameRate = closest
                }
            }
        }
    }

    func exportProject() async {
        guard let master = audioMaster else { return }

        let panel = NSSavePanel()
        panel.title = "Premiere Pro Projekt speichern"
        panel.nameFieldStringValue = "\(settings.projectName).xml"
        panel.allowedContentTypes = [.xml]
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            let syncedCameras = cameras.filter { $0.syncStatus.isSynced }
            try await PremiereProjectGenerator.generate(
                audioMaster: master,
                cameras: syncedCameras,
                settings: settings,
                outputURL: url
            )

            if settings.openAfterExport {
                NSWorkspace.shared.open(url)
            }
        } catch {
            alertMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
            showAlert = true
        }
    }
}
