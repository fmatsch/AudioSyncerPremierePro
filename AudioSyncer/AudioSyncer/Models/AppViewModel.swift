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

    let settings = ProjectSettings()

    var allFilesSynced: Bool {
        guard audioMaster != nil, !cameras.isEmpty else { return false }
        return cameras.allSatisfy { $0.syncStatus.isSynced }
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
                syncProgress = Double(index + 1) / Double(cameras.count)
                objectWillChange.send()
            }

            syncStatusMessage = "Synchronisation abgeschlossen"

            // Auto-detect resolution from first camera
            await detectVideoProperties()

        } catch {
            syncStatusMessage = "Fehler: \(error.localizedDescription)"
            for camera in cameras where !camera.syncStatus.isSynced {
                camera.syncStatus = .failed(error.localizedDescription)
            }
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
        panel.nameFieldStringValue = "\(settings.projectName).prproj"
        panel.allowedContentTypes = [UTType(filenameExtension: "prproj") ?? .data]
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            try await PremiereProjectGenerator.generate(
                audioMaster: master,
                cameras: cameras,
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
