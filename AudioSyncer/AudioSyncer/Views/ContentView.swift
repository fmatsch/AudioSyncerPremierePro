import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        HSplitView {
            // Left panel: Media list
            ScrollView {
                MediaListView(viewModel: viewModel)
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            .background(PPTheme.bgDark)

            // Right panel: Sync & Export
            VStack(spacing: PPTheme.spacing) {
                // Header
                headerView

                // Convert controls
                if viewModel.audioMaster != nil || !viewModel.cameras.isEmpty {
                    ConvertView(viewModel: viewModel)
                }

                // Sync controls
                SyncProgressView(viewModel: viewModel)

                // Sync results overview
                if viewModel.cameras.contains(where: { $0.syncStatus.isSynced }) {
                    syncResultsView
                }

                // Export
                if viewModel.allFilesSynced {
                    ExportView(viewModel: viewModel, settings: viewModel.settings)
                }

                Spacer()
            }
            .padding(PPTheme.panelPadding)
            .frame(minWidth: 400)
            .background(PPTheme.bgDark)
        }
        .background(PPTheme.bgDark)
        .alert("Fehler", isPresented: $viewModel.showAlert) {
            Button("OK") {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AudioSyncer")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(PPTheme.textPrimary)
                Text("Multicam Sync für Premiere Pro")
                    .font(.system(size: 12))
                    .foregroundColor(PPTheme.textSecondary)
            }
            Spacer()
            statusIndicator
        }
        .padding(PPTheme.panelPadding)
        .ppPanel()
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(PPTheme.textSecondary)
        }
    }

    private var statusColor: Color {
        if viewModel.allFilesSynced { return PPTheme.success }
        if viewModel.isSyncing { return PPTheme.warning }
        if viewModel.audioMaster != nil && !viewModel.cameras.isEmpty { return PPTheme.accent }
        return PPTheme.textSecondary
    }

    private var statusText: String {
        if viewModel.allFilesSynced { return "Bereit zum Export" }
        if viewModel.isSyncing { return "Synchronisiere…" }
        let masterOk = viewModel.audioMaster != nil
        let cameraCount = viewModel.cameras.count
        if !masterOk { return "Audio Master fehlt" }
        if cameraCount == 0 { return "Kameras hinzufügen" }
        return "\(cameraCount) Kamera(s) geladen"
    }

    private var syncResultsView: some View {
        VStack(alignment: .leading, spacing: PPTheme.spacing) {
            Label("Sync-Ergebnisse", systemImage: "clock.arrow.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PPTheme.textPrimary)

            ForEach(viewModel.cameras) { camera in
                if camera.syncStatus.isSynced {
                    HStack {
                        Circle()
                            .fill(PPTheme.camera)
                            .frame(width: 6, height: 6)
                        Text(camera.role.rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(PPTheme.textPrimary)
                        Spacer()
                        Text(camera.syncStatus.description)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(PPTheme.success)
                    }
                }
            }
        }
        .padding(PPTheme.panelPadding)
        .ppPanel()
    }
}
