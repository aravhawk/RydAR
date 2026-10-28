import AVFoundation
import SwiftUI
import MapKit

enum RydarTheme {
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

/// Shared glass radii. A nested thumbnail uses the plate radius minus the inset,
/// so its corners sit on the same center as the plate instead of looking square inside it.
enum RydarShape {
    static let glassRadius: CGFloat = 34
    static let glassInset: CGFloat = 12
    static var nestedRadius: CGFloat { glassRadius - glassInset }
}

struct RydarCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RydarShape.glassInset)
            .containerShape(RoundedRectangle(cornerRadius: RydarShape.glassRadius, style: .continuous))
            .rydarGlassPlate()
    }
}

/// Sentence-case status label. Replaces the tracked all-caps eyebrow.
struct RydarEyebrow: View {
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
    @AppStorage(UnitSystem.key) private var units = UnitSystem.imperial.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(displaySpeed(mph: range.low, down: true))–\(displaySpeed(mph: range.high, down: true)) \(UnitSystem.current.speedUnit)")
                .font(.title2.bold().monospacedDigit())
            Text("Suggested speed")
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
        case .unconfirmed: return "From road records"
        case .cameraLowered: return "Camera sees gravel"
        case .conflictKeptUnpaved: return "Records say gravel; kept cautious"
        case .confirmed: return "Records and camera agree"
        }
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
        case .adult: return "Drive screen, camera, and spoken warnings."
        case .under18: return "Spoken warnings only. No screen or camera."
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

    /// Liquid Glass plate. An explicit continuous radius, because a concentric
    /// rectangle with no shaped ancestor collapses to a square.
    @ViewBuilder
    func rydarGlassPlate() -> some View {
        let shape = RoundedRectangle(cornerRadius: RydarShape.glassRadius, style: .continuous)
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .clipShape(shape)
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

/// What the live road label says. It follows the camera whether or not a curve is near.
func liveRoadLabel(camera: CameraEvidence?) -> String {
    switch camera?.label {
    case .paved: return "Paved"
    case .unpaved: return "Unpaved"
    case .cantTell, nil: return "Reading road…"
    }
}

/// Live view of the dash camera. The preview layer is the view's own layer, so the
/// rounded corner has to be set on that layer or the video stays square. Nothing is saved.
struct CameraPreviewView: UIViewRepresentable {
    var session: AVCaptureSession
    var cornerRadius: CGFloat

    func makeUIView(context: Context) -> PreviewHost {
        let host = PreviewHost()
        host.backgroundColor = .clear
        host.isOpaque = false
        host.previewLayer.videoGravity = .resizeAspectFill
        host.previewLayer.session = session
        host.cornerRadius = cornerRadius
        return host
    }

    func updateUIView(_ host: PreviewHost, context: Context) {
        if host.previewLayer.session !== session {
            host.previewLayer.session = session
        }
        host.cornerRadius = cornerRadius
    }

    final class PreviewHost: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var cornerRadius: CGFloat = 0 {
            didSet { applyShape() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyShape()
        }

        private func applyShape() {
            clipsToBounds = true
            previewLayer.masksToBounds = true
            previewLayer.cornerRadius = cornerRadius
            previewLayer.cornerCurve = .continuous
        }
    }
}

/// Camera indicator with a small live thumbnail and the current road surface.
struct DashCameraCard: View {
    var status: String
    var session: AVCaptureSession?
    var camera: CameraEvidence?
    var live: Bool
    var body: some View {
        HStack(spacing: 14) {
            if live, let session {
                CameraPreviewView(session: session, cornerRadius: RydarShape.nestedRadius)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: RydarShape.nestedRadius, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(status, systemImage: "camera")
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
                if live {
                    Label(liveRoadLabel(camera: camera), systemImage: "road.lanes")
                        .font(.title3.weight(.bold))
                        .accessibilityIdentifier("liveRoadSurface")
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A small map of where the rider is. It does not pan, zoom, or take taps.
struct DriveGlanceMap: View {
    var latitude: Double
    var longitude: Double
    @State private var position: MapCameraPosition

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        _position = State(initialValue: Self.camera(latitude: latitude, longitude: longitude))
    }

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(position: $position, interactionModes: []) {
            Annotation("You", coordinate: coordinate, anchor: .center) {
                Circle()
                    .fill(RydarTheme.accent)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls({})
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: RydarShape.glassRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your location")
        .accessibilityIdentifier("driveMap")
        .onChange(of: latitude) { _, _ in position = Self.camera(latitude: latitude, longitude: longitude) }
        .onChange(of: longitude) { _, _ in position = Self.camera(latitude: latitude, longitude: longitude) }
    }

    private static func camera(latitude: Double, longitude: Double) -> MapCameraPosition {
        .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            distance: 520
        ))
    }
}
