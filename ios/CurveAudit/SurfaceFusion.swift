import Foundation

enum DriverMode: String {
    case adult
    case passenger
    case under18
}

enum CameraLabel {
    case paved
    case unpaved
    case cantTell
}

enum SurfaceUI: Equatable {
    case unconfirmed
    case cameraLowered
    case conflictKeptUnpaved
    case confirmed
}

struct CameraEvidence {
    let label: CameraLabel
    let confidence: Double
    let age: TimeInterval
    let onMatchedRoadROI: Bool
    let persistent: Bool
}

func allowsInDriveSound(_ mode: DriverMode) -> Bool {
    switch mode {
    case .adult, .passenger:
        return true
    case .under18:
        return false
    }
}

func fuseSurface(fileLabel: RoadSurface?, camera: CameraEvidence?, threshold: Double) -> (RoadSurface, SurfaceUI) {
    let base = fileLabel ?? .unpaved
    guard let camera,
          camera.age <= 1,
          camera.onMatchedRoadROI,
          camera.persistent,
          camera.confidence >= threshold
    else {
        return (base, .unconfirmed)
    }
    switch (base, camera.label) {
    case (.paved, .unpaved):
        return (.unpaved, .cameraLowered)
    case (.unpaved, .paved):
        return (.unpaved, .conflictKeptUnpaved)
    case (_, .cantTell):
        return (base, .unconfirmed)
    default:
        return (base, .confirmed)
    }
}
