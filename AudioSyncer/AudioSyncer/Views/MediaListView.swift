import SwiftUI

struct MediaListView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PPTheme.spacing) {
            Label("Medien", systemImage: "film")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PPTheme.textPrimary)
                .padding(.bottom, 4)

            // Audio Master slot
            MediaDropZone(
                role: .audioMaster,
                file: viewModel.audioMaster,
                onDrop: { url in viewModel.addFile(url: url, role: .audioMaster) },
                onRemove: { viewModel.removeFile(role: .audioMaster) }
            )

            Divider().background(PPTheme.border)

            // Camera slots
            ForEach(MediaRole.cameras, id: \.self) { role in
                let file = viewModel.cameras.first { $0.role == role }
                let isActive = file != nil || viewModel.cameras.count < 6

                if isActive || viewModel.cameras.contains(where: { $0.role == role }) {
                    MediaDropZone(
                        role: role,
                        file: file,
                        onDrop: { url in viewModel.addFile(url: url, role: role) },
                        onRemove: { viewModel.removeFile(role: role) }
                    )
                }
            }

            Spacer()

            // Quick add button
            if viewModel.cameras.count < 6 {
                Button(action: openMultiFilePicker) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Dateien hinzufügen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PPButtonStyle())
            }
        }
        .padding(PPTheme.panelPadding)
    }

    private func openMultiFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .audio, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Audio-Master und/oder Kamera-Dateien auswählen"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            if viewModel.audioMaster == nil && isLikelyAudioFile(url) {
                viewModel.addFile(url: url, role: .audioMaster)
            } else if let role = viewModel.nextAvailableCameraRole() {
                viewModel.addFile(url: url, role: role)
            }
        }
    }

    private func isLikelyAudioFile(_ url: URL) -> Bool {
        let audioExts = ["wav", "mp3", "aac", "m4a", "aif", "aiff", "flac"]
        return audioExts.contains(url.pathExtension.lowercased())
    }
}
