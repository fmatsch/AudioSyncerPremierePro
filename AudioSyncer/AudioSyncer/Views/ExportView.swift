import SwiftUI

struct ExportView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: ProjectSettings

    var body: some View {
        VStack(alignment: .leading, spacing: PPTheme.spacing) {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PPTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Projektname")
                        .font(.system(size: 12))
                        .foregroundColor(PPTheme.textSecondary)
                        .frame(width: 100, alignment: .leading)
                    TextField("", text: $settings.projectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(PPTheme.textPrimary)
                        .padding(6)
                        .background(PPTheme.bgInput)
                        .cornerRadius(4)
                }

                HStack {
                    Text("Framerate")
                        .font(.system(size: 12))
                        .foregroundColor(PPTheme.textSecondary)
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $settings.frameRate) {
                        ForEach(ProjectSettings.supportedFrameRates, id: \.self) { rate in
                            Text(formatFrameRate(rate)).tag(rate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                HStack {
                    Text("Auflösung")
                        .font(.system(size: 12))
                        .foregroundColor(PPTheme.textSecondary)
                        .frame(width: 100, alignment: .leading)
                    Text("\(settings.width) x \(settings.height)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(PPTheme.textPrimary)
                }

                Toggle(isOn: $settings.openAfterExport) {
                    Text("Nach Export in Premiere Pro öffnen")
                        .font(.system(size: 12))
                        .foregroundColor(PPTheme.textSecondary)
                }
                .toggleStyle(.checkbox)
            }

            Divider().background(PPTheme.border)

            Button(action: {
                Task { await viewModel.exportProject() }
            }) {
                HStack {
                    Image(systemName: "film.stack")
                    Text("Premiere Pro Projekt erstellen")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PPButtonStyle(isPrimary: true))
            .disabled(!viewModel.allFilesSynced)
        }
        .padding(PPTheme.panelPadding)
        .ppPanel()
    }

    private func formatFrameRate(_ rate: Double) -> String {
        if rate == Double(Int(rate)) {
            return "\(Int(rate)) fps"
        }
        return String(format: "%.3f fps", rate)
    }
}
