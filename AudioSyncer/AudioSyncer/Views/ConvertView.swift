import SwiftUI

struct ConvertView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PPTheme.spacing) {
            Label("Konvertierung", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PPTheme.textPrimary)

            Text("Konvertiert alle Dateien zu ProRes + PCM Audio für maximale Kompatibilität mit Premiere Pro (keine Plugins nötig).")
                .font(.system(size: 11))
                .foregroundColor(PPTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Quality picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Qualität")
                    .font(.system(size: 12))
                    .foregroundColor(PPTheme.textSecondary)

                ForEach(ConversionQuality.allCases) { quality in
                    qualityOption(quality)
                }
            }

            // Estimated size
            if viewModel.estimatedTotalSize > 0 || viewModel.isEstimating {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .foregroundColor(PPTheme.textSecondary)
                        .font(.system(size: 11))
                    if viewModel.isEstimating {
                        Text("Größe wird geschätzt…")
                            .font(.system(size: 11))
                            .foregroundColor(PPTheme.textSecondary)
                    } else {
                        Text("Geschätzte Gesamtgröße: \(formatBytes(viewModel.estimatedTotalSize))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(sizeColor)
                    }
                }
            }

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
            if viewModel.isConverting || viewModel.allConverted {
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
        .onAppear { Task { await viewModel.updateEstimate() } }
        .onChange(of: viewModel.conversionQuality) { _ in
            Task { await viewModel.updateEstimate() }
        }
    }

    private func qualityOption(_ quality: ConversionQuality) -> some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.conversionQuality == quality ? "largecircle.fill.circle" : "circle")
                .foregroundColor(viewModel.conversionQuality == quality ? PPTheme.accent : PPTheme.textSecondary)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text(quality.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PPTheme.textPrimary)
                Text(quality.description)
                    .font(.system(size: 10))
                    .foregroundColor(PPTheme.textSecondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.conversionQuality = quality
        }
    }

    private var sizeColor: Color {
        let gb = Double(viewModel.estimatedTotalSize) / 1_073_741_824
        if gb > 100 { return PPTheme.error }
        if gb > 50 { return PPTheme.warning }
        return PPTheme.textPrimary
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
                if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                    Text(formatBytes(size))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(PPTheme.success)
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
