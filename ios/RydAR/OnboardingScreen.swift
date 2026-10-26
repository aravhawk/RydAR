import SwiftUI
import AVFoundation
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
    @State private var tread: TreadChoice?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 52)).foregroundStyle(AuditTheme.accent)
                    .accessibilityHidden(true)
                Text("RydAR").font(.largeTitle.bold())
                Text("A heads-up before a tight curve. Follow the signs.")
                    .foregroundStyle(.secondary)
                AuditCard {
                    Text("How a trip works").font(.headline)
                    Text("Park, choose who is driving, and start. Leave RydAR open. Alerts still speak if Maps is in front, unless the driver is under 18.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("The phone speaks only “\(spokenWarning)” and taps at the same moment. That happens when a filed curve is ahead and the cautious speed is above the advisory speed computed for it. The number is accurate as computed. A neighborhood corner the road file does not keep, or a speed under that range, stays quiet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if permissions.locationStatus == .notDetermined {
                    Button("Allow location", action: permissions.requestLocation)
                        .buttonStyle(.bordered).accessibilityIdentifier("allowLocation")
                } else if permissions.locationStatus == .denied {
                    Button("Turn on location in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else {
                    Label("Location is on", systemImage: "location.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                AuditCard {
                    Text("Dash is on").font(.headline)
                    Text("Dash uses the camera to look at the road surface during a trip. It can only treat a paved road as unpaved. It does not measure ice or a friction number. experimental — validated on public datasets only, not on Arkansas roads.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Turn Dash off in Settings if you do not want the camera. An under-18 driver never gets the camera.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                AuditCard {
                    Text("Anonymous passes are on").font(.headline)
                    Text("A pass is the curve, the direction, a 5 mph band, and the hour. No name and no route. A road department sees a count only after 20 passes in more than one hour. That count is how those curves show up beyond this phone.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("It stays on unless you turn it off in Settings. An under-18 driver does not send passes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("How much tread is on the tires?").font(.title3.bold())
                TreadChoices(selection: $tread)
                if tread?.replaceBeforeDriving == true {
                    Text("Those tires are at the wear bars. Replace them before driving.")
                        .font(.subheadline.bold())
                } else if tread == .low {
                    Text("Low tread. The range on a curve will sit lower.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Continue") {
                    if let tread { TreadStore.save(tread) }
                    DashPreference.isOn = true
                    UserDefaults.standard.set(true, forKey: "rydar.uploadOptIn")
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        Task { @MainActor in onContinue() }
                    }
                }
                .buttonStyle(AuditPrimaryButton())
                .disabled(tread == nil)
                .opacity(tread == nil ? 0.45 : 1)
                .accessibilityIdentifier("finishOnboarding")
            }.padding(24)
        }
        .background(AuditTheme.background)
    }
}

struct TreadChoices: View {
    @Binding var selection: TreadChoice?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(TreadChoice.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.rawValue).font(.headline)
                            Text(choice.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection == choice {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AuditTheme.accent)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tread-\(choice.rawValue)")
            }
        }
    }
}

struct TreadCheckScreen: View {
    var onContinue: () -> Void
    @State private var tread: TreadChoice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Check the tires").font(.largeTitle.bold())
                Text("About 1,000 miles since the last answer. Use a gauge, or the wear bars.")
                    .foregroundStyle(.secondary)
                TreadChoices(selection: $tread)
                if tread?.replaceBeforeDriving == true {
                    Text("Replace them before this trip.")
                        .font(.subheadline.bold())
                }
                Button("Save") {
                    if let tread { TreadStore.save(tread) }
                    onContinue()
                }
                .buttonStyle(AuditPrimaryButton())
                .disabled(tread == nil)
                .opacity(tread == nil ? 0.45 : 1)
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
