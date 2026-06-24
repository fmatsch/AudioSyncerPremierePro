import SwiftUI

struct ConvertView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PPTheme.spacing) {
            Label("Konvertierung", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PPTheme.textPrimary)

            Text("Konvertiert alle Dateien zu ProRes 422 HQ + PCM Audio für maximale Kompatibilität mit Premiere Pro (keine Plugins nötig).")
                .font(.system(size: 11))
                .foregroundColor(PPTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isConverting {
                VStack(spacing: 6) {
                    ProgressView(value: viewModel.conversionProgress)
                        .progressViewStyle(.linear)
                        .tint(PPTheme.accent)

                    Text(viewModel.conversionStatusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(PPTheme.textSecondary)
                }
            } else if !viewModel.conversionStatusMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.allConverted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(viewModel.allConverted ? PPTheme.success : PPTheme.warning)
                        .font(.system(size: 12))
                    Text(viewModel.conversionStatusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(PPTheme.textSecondary)
                }
            }

            // Per-file status
            if viewModel.isConverting || viewModel.conversionStatusMessage.contains("konvertiert") {
                VStack(spacing: 4) {
                    if let master = viewModel.audioMaster {
                        conversionRow(file: master)
                    }
                    ForEach(viewModel.cameras) { camera in
                        conversionRow(file: camera)
                    }
                }
            }

            Button(action: {
                Task { await viewModel.startConversion() }
            }) {
                HStack {
                    Image(systemName: "film.stack")
                    Text(viewModel.allConverted ? "Erneut konvertieren" : "Für Premiere Pro konvertieren")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PPButtonStyle(isPrimary: false))
            .disabled(!viewModel.canConvert)
        }
        .padding(PPTheme.panelPadding)
        .ppPanel()
    }

    @ViewBuilder
    private func conversionRow(file: MediaFile) -> some View {
        HStack(spacing: 6) {
            switch file.convertStatus {
            case .none:
                Image(systemName: "circle")
                    .foregroundColor(PPTheme.textSecondary)
                    .font(.system(size: 9))
            case .converting(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            case .converted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(PPTheme.success)
                    .font(.system(size: 9))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(PPTheme.error)
                    .font(.system(size: 9))
            }

            Text(file.fileName)
                .font(.system(size: 10))
                .foregroundColor(PPTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if case .converted(let url) = file.convertStatus {
                Text(url.lastPathComponent)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(PPTheme.success)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
