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

struct RydarCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .rydarGroupedPlate()
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
        case .adult: return "Spoken warnings and the drive screen."
        case .under18: return "Spoken warnings only. No screen, camera, or uploads."
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

/// What the live road label says. It follows the camera whether or not a curve is near.
func liveRoadLabel(camera: CameraEvidence?) -> String {
    switch camera?.label {
    case .paved: return "Paved"
    case .unpaved: return "Unpaved"
    case .cantTell, nil: return "Reading road…"
    }
}

/// Square live view of the dash camera. It only displays frames; nothing is saved.
struct CameraPreviewView: UIViewRepresentable {
    var session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewHost {
        let host = PreviewHost()
        host.previewLayer.videoGravity = .resizeAspectFill
        host.previewLayer.session = session
        return host
    }

    func updateUIView(_ host: PreviewHost, context: Context) {
        if host.previewLayer.session !== session {
            host.previewLayer.session = session
        }
    }

    final class PreviewHost: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
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
                CameraPreviewView(session: session)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
