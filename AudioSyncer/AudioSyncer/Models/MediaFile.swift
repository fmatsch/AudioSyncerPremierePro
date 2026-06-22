import Foundation
import AVFoundation

enum MediaRole: String, CaseIterable, Identifiable {
    case audioMaster = "Audio Master"
    case camera1 = "Kamera 1"
    case camera2 = "Kamera 2"
    case camera3 = "Kamera 3"
    case camera4 = "Kamera 4"
    case camera5 = "Kamera 5"
    case camera6 = "Kamera 6"

    var id: String { rawValue }

    var isAudioMaster: Bool { self == .audioMaster }

    var index: Int {
        switch self {
        case .audioMaster: return 0
        case .camera1: return 1
        case .camera2: return 2
        case .camera3: return 3
        case .camera4: return 4
        case .camera5: return 5
        case .camera6: return 6
        }
    }

    static var cameras: [MediaRole] {
        [.camera1, .camera2, .camera3, .camera4, .camera5, .camera6]
    }
}

enum SyncStatus: Equatable {
    case pending
    case extractingAudio
    case syncing
    case synced(offsetSeconds: Double)
    case failed(String)

    var description: String {
        switch self {
        case .pending: return "Bereit"
        case .extractingAudio: return "Audio wird extrahiert…"
        case .syncing: return "Synchronisiere…"
        case .synced(let offset):
            let sign = offset >= 0 ? "+" : ""
            return String(format: "Synced (%@%.3fs)", sign, offset)
        case .failed(let msg): return "Fehler: \(msg)"
        }
    }

    var isSynced: Bool {
        if case .synced = self { return true }
        return false
    }
}

class MediaFile: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let role: MediaRole
    @Published var syncStatus: SyncStatus = .pending
    @Published var waveformSamples: [Float] = []
    @Published var duration: Double = 0

    var fileName: String { url.lastPathComponent }

    var hasVideo: Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mxf"].contains(ext)
    }

    var offsetSeconds: Double? {
        if case .synced(let offset) = syncStatus { return offset }
        return nil
    }

    init(url: URL, role: MediaRole) {
        self.url = url
        self.role = role
    }
}
