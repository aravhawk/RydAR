import Foundation

enum DriverMode: String {
    case adult
    case under18

    /// Trips saved before passenger mode was removed, and any leftover setting.
    static func fromStored(_ raw: String) -> DriverMode? {
        if raw == "passenger" || raw == DriverMode.adult.rawValue { return .adult }
        if raw == DriverMode.under18.rawValue { return .under18 }
        return nil
    }

    /// Rewrites a saved passenger choice to Driver. Safe to call more than once.
    static func migrateStoredSelection(defaults: UserDefaults = .standard) {
        let keys = ["rydar.driverMode", "rydar.lastDriverMode"]
        for key in keys where defaults.string(forKey: key) == "passenger" {
            defaults.set(DriverMode.adult.rawValue, forKey: key)
        }
    }
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
    case .adult:
        return true
    case .under18:
        return true
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
