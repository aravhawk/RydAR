import SwiftUI
import MapKit

enum AuditTheme {
    static let accent = Color.teal
    static let background = Color(uiColor: .systemGroupedBackground)
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

struct AuditCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct AuditPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(AuditTheme.accent.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct AuditEyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
    }
}

struct ScreeningRangeLabel: View {
    var range: ScreeningRange
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(range.low, specifier: "%.1f")–\(range.high, specifier: "%.1f") mph")
                .font(.title2.bold().monospacedDigit())
            Text("Advisory speed, accurate as computed.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SurfaceBadge: View {
    var fileSurface: RoadSurface
    var camera: CameraEvidence? = nil
    var threshold: Double = 1
    private var fused: (RoadSurface, SurfaceUI) {
        fuseSurface(fileLabel: fileSurface, camera: camera, threshold: threshold)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(fused.0 == .paved ? "Paved" : "Unpaved", systemImage: "road.lanes")
                .font(.subheadline.weight(.semibold))
            Text(source).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(AuditTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
    private var source: String {
        switch fused.1 {
        case .unconfirmed: return "County file · surface unconfirmed"
        case .cameraLowered: return "Camera lowered county-file assumption"
        case .conflictKeptUnpaved: return "Camera conflict · kept unpaved"
        case .confirmed: return "County file + camera agreement"
        }
    }
}

struct CurveMap: View {
    var curves: [Curve]
    var center: MapPoint
    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
            ForEach(curves) { curve in
                MapPolyline(coordinates: curve.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }).stroke(AuditTheme.accent, lineWidth: 6)
                Annotation(curve.roadName, coordinate: CLLocationCoordinate2D(
                    latitude: curve.latitude, longitude: curve.longitude)) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.title2).foregroundStyle(.white, AuditTheme.accent)
                        .accessibilityLabel("Candidate curve on \(curve.roadName)")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityLabel("Candidate curve map. Curve details follow below.")
    }
}

extension DriverMode {
    var screenTitle: String {
        switch self {
        case .adult: return "Adult driver"
        case .passenger: return "Passenger operating"
        case .under18: return "Under-18 driver"
        }
    }
    var screenDetail: String {
        switch self {
        case .adult: return "An adult is driving. Prompts can speak. Set up while parked."
        case .passenger: return "An adult is driving. You are holding the phone. Prompts can speak."
        case .under18: return "You are the driver, and you are under 18. No voice, camera, or upload on this trip."
        }
    }
}
