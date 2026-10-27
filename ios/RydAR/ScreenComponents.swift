import SwiftUI
import MapKit

enum AuditTheme {
    static let accent = Color.teal
    /// Text on a light background. System teal and orange are under 3:1 there.
    static let accentText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemTeal
            : UIColor(red: 0.0, green: 0.40, blue: 0.48, alpha: 1)
    })
    static let warningText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0.72, green: 0.28, blue: 0.0, alpha: 1)
    })
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
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .rydarGroupedPlate()
    }
}

/// Sentence-case status label. Replaces the tracked all-caps eyebrow.
struct AuditEyebrow: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

struct ScreeningRangeLabel: View {
    var range: ScreeningRange
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(range.low, specifier: "%.1f")–\(range.high, specifier: "%.1f") mph")
                .font(.title2.bold().monospacedDigit())
            Text("Advisory")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 2) {
            Label(fused.0 == .paved ? "Paved" : "Unpaved", systemImage: "road.lanes")
                .font(.subheadline.weight(.semibold))
            Text(source)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .rydarGlassChip()
        .accessibilityElement(children: .combine)
    }
    private var source: String {
        switch fused.1 {
        case .unconfirmed: return "County file"
        case .cameraLowered: return "Camera: unpaved"
        case .conflictKeptUnpaved: return "Kept unpaved"
        case .confirmed: return "County file and camera"
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
                        .accessibilityLabel("Curve on \(curve.roadName)")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 230)
        .rydarClipPlate()
        .accessibilityLabel("Curve map. Details follow below.")
    }
}

extension DriverMode {
    var screenTitle: String {
        switch self {
        case .adult: return "Driver"
        case .under18: return "Teen driver"
        }
    }
    var screenDetail: String {
        switch self {
        case .adult: return "Full warnings and speech."
        case .under18: return "Audio warnings only. No screen use, camera, or upload."
        }
    }
}

extension View {
    /// Primary call to action. Capsule glass on iOS 26, bordered capsule before that.
    @ViewBuilder
    func rydarProminentAction() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
        } else {
            self.buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
        }
    }

    /// Secondary control. Regular glass on iOS 26, bordered capsule before that.
    @ViewBuilder
    func rydarGlassAction() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        } else {
            self.buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        }
    }

    @ViewBuilder
    func rydarGlassChip() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func rydarGroupedPlate() -> some View {
        if #available(iOS 26, *) {
            self.background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: ConcentricRectangle())
        } else {
            self.background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    func rydarClipPlate() -> some View {
        if #available(iOS 26, *) {
            self.clipShape(ConcentricRectangle())
        } else {
            self.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder
    func rydarNavigationSubtitle(_ subtitle: String) -> some View {
        if #available(iOS 26, *) {
            self.navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}

/// Blends nearby glass controls. One control is unchanged.
struct RydarGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
