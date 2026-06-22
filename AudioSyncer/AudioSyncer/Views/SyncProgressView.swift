import SwiftUI

struct SyncProgressView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PPTheme.spacing) {
            Label("Synchronisation", systemImage: "waveform.path.ecg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PPTheme.textPrimary)

            if viewModel.isSyncing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: viewModel.syncProgress)
                        .progressViewStyle(.linear)
                        .tint(PPTheme.accent)

                    Text(viewModel.syncStatusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(PPTheme.textSecondary)
                }
            } else {
                Button(action: {
                    Task { await viewModel.startSync() }
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Synchronisation starten")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PPButtonStyle(isPrimary: true))
                .disabled(!viewModel.canSync)

                if !viewModel.syncStatusMessage.isEmpty {
                    Text(viewModel.syncStatusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(
                            viewModel.allFilesSynced ? PPTheme.success : PPTheme.textSecondary
                        )
                }
            }
        }
        .padding(PPTheme.panelPadding)
        .ppPanel()
    }
}
