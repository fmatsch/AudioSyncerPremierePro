import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    var color: Color = PPTheme.accent
    var height: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let midY = geometry.size.height / 2
            let maxSample = samples.max() ?? 1.0
            let normalizer = maxSample > 0 ? maxSample : 1.0

            Path { path in
                guard !samples.isEmpty else { return }
                let barWidth = max(1, width / CGFloat(samples.count))

                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) / CGFloat(samples.count) * width
                    let barHeight = CGFloat(sample / normalizer) * midY * 0.9
                    path.move(to: CGPoint(x: x, y: midY - barHeight))
                    path.addLine(to: CGPoint(x: x, y: midY + barHeight))
                }
            }
            .stroke(color, lineWidth: max(1, width / CGFloat(max(samples.count, 1))))
        }
        .frame(height: height)
    }
}

struct WaveformPlaceholder: View {
    var height: CGFloat = 50

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(PPTheme.bgInput)
            .frame(height: height)
            .overlay(
                Text("Keine Datei geladen")
                    .font(.system(size: 11))
                    .foregroundColor(PPTheme.textSecondary)
            )
    }
}
