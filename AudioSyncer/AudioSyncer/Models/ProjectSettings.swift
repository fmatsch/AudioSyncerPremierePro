import Foundation

class ProjectSettings: ObservableObject {
    @Published var projectName: String = "Multicam Project"
    @Published var frameRate: Double = 25.0
    @Published var width: Int = 1920
    @Published var height: Int = 1080
    @Published var openAfterExport: Bool = true

    static let supportedFrameRates: [Double] = [23.976, 24, 25, 29.97, 30, 50, 59.94, 60]
}
