import SwiftUI
import UniformTypeIdentifiers

struct MediaDropZone: View {
    let role: MediaRole
    let file: MediaFile?
    let onDrop: (URL) -> Void
    let onRemove: () -> Void

    @State private var isTargeted = false

    private var roleColor: Color {
        role.isAudioMaster ? PPTheme.audioMaster : PPTheme.camera
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(roleColor)
                    .frame(width: 8, height: 8)
                Text(role.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PPTheme.textPrimary)
                Spacer()
                if file != nil {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(PPTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let file = file {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.fileName)
                        .font(.system(size: 11))
                        .foregroundColor(PPTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !file.waveformSamples.isEmpty {
                        WaveformView(samples: file.waveformSamples, color: roleColor, height: 36)
                    }

                    HStack {
                        if file.duration > 0 {
                            Text(formatDuration(file.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(PPTheme.textSecondary)
                        }
                        Spacer()
                        syncBadge(file.syncStatus)
                    }
                }
            } else {
                dropArea
            }
        }
        .padding(PPTheme.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: PPTheme.cornerRadius)
                .fill(isTargeted ? roleColor.opacity(0.15) : PPTheme.bgInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PPTheme.cornerRadius)
                .stroke(isTargeted ? roleColor : PPTheme.border, lineWidth: isTargeted ? 2 : 1)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var dropArea: some View {
        VStack(spacing: 4) {
            Image(systemName: role.isAudioMaster ? "waveform" : "video")
                .font(.system(size: 20))
                .foregroundColor(PPTheme.textSecondary)
            Text("Datei hierher ziehen")
                .font(.system(size: 11))
                .foregroundColor(PPTheme.textSecondary)
            Text("oder klicken zum Auswählen")
                .font(.system(size: 10))
                .foregroundColor(PPTheme.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .contentShape(Rectangle())
        .onTapGesture {
            openFilePicker()
        }
    }

    @ViewBuilder
    private func syncBadge(_ status: SyncStatus) -> some View {
        switch status {
        case .pending:
            EmptyView()
        case .extractingAudio, .syncing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(status.description)
                    .font(.system(size: 10))
                    .foregroundColor(PPTheme.warning)
            }
        case .synced:
            Text(status.description)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(PPTheme.success)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PPTheme.success.opacity(0.15))
                .cornerRadius(3)
        case .failed:
            Text(status.description)
                .font(.system(size: 10))
                .foregroundColor(PPTheme.error)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                onDrop(url)
            }
        }
        return true
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .audio, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url {
            onDrop(url)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, ms)
    }
}
