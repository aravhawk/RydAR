import SwiftUI
import CoreLocation
import UIKit

/// Requests authorization only. The trip engine owns all location updates.
@MainActor
final class ScreenPermissions: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        locationStatus = manager.authorizationStatus
    }
    func requestLocation() { manager.requestWhenInUseAuthorization() }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in locationStatus = status }
    }
    var locationDescription: String {
        switch locationStatus {
        case .authorizedAlways: return "Location allowed · Always"
        case .authorizedWhenInUse: return "Location allowed · While Using"
        case .denied, .restricted: return "Location unavailable · preview still works"
        default: return "Location While Using · for approaching curves"
        }
    }
}

struct OnboardingScreen: View {
    var onContinue: () -> Void
    @StateObject private var permissions = ScreenPermissions()
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 56)).foregroundStyle(AuditTheme.accent)
                    .accessibilityHidden(true)
                AuditEyebrow(text: "CurveAudit AR / Welcome")
                Text("Know the curve.\nUnderstand the range.")
                    .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                Text("A screening tool for Benton and Washington county roads. Screening is not driving advice or an advisory speed. Follow posted signs and road conditions.")
                    .foregroundStyle(.secondary)
                AuditCard {
                    Label("Permissions, with a purpose", systemImage: "hand.raised")
                        .font(.headline)
                    Text(permissions.locationDescription).font(.subheadline)
                    if permissions.locationStatus == .notDetermined {
                        Button("Allow location while using", action: permissions.requestLocation)
                            .buttonStyle(.bordered).accessibilityIdentifier("allowLocation")
                    } else if permissions.locationStatus == .denied {
                        Button("Open iPhone Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    Text("Always location is optional. Motion is requested when trip recording is connected. Camera permission is only for Dash mode; no frames are saved. No microphone is needed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                AuditCard {
                    Label("Who's driving? Every trip.", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Text("Nothing is pre-selected. Adult driver and Passenger operating can use sound. Under-18 driver has preview before moving and debrief after parking, with no in-drive sound, camera, or upload.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Label("No account. Trips stay on this iPhone.", systemImage: "iphone.gen3")
                    .font(.subheadline)
                Button("Continue", action: onContinue)
                    .buttonStyle(AuditPrimaryButton()).accessibilityIdentifier("finishOnboarding")
            }.padding(24)
        }
        .background(AuditTheme.background)
    }
}

struct DriverGateScreen: View {
    var onStart: (DriverMode) -> Void
    @State private var selection: DriverMode?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AuditEyebrow(text: "Set up while parked")
                    Text("Who's driving?").font(.largeTitle.bold())
                    Text("Choose for this trip. Your choice is never saved as a default.")
                        .foregroundStyle(.secondary)
                    ForEach([DriverMode.adult, .passenger, .under18], id: \.rawValue) { mode in
                        Button {
                            selection = mode
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: selection == mode ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(AuditTheme.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(mode.screenTitle).font(.headline)
                                    Text(mode.screenDetail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selection == mode ? AuditTheme.accent : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("driver-\(mode.rawValue)")
                        .accessibilityAddTraits(selection == mode ? .isSelected : [])
                    }
                    Button("Start this trip") {
                        if let selection { onStart(selection) }
                    }
                    .buttonStyle(AuditPrimaryButton()).disabled(selection == nil)
                    .opacity(selection == nil ? 0.45 : 1)
                    .accessibilityIdentifier("confirmDriver")
                }.padding(24)
            }
            .background(AuditTheme.background)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
