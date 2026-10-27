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
    @State private var tread: TreadChoice?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AuditTheme.accent)
                        .accessibilityHidden(true)
                    Text("A heads-up before a tight curve.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Leave it open. Alerts speak with Maps in front.")
                        .font(.subheadline)
                    Text("“\(spokenWarning)”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Teen driver: audio warnings only. No screen use, camera, or upload.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                locationRow
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dash is on")
                        .font(.headline)
                    Text("Reads the surface. Paved can only become unpaved. Off for a teen driver.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anonymous passes are on")
                        .font(.headline)
                    Text("Curve, direction, 5 mph band, hour. No name or route.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("This is how counties learn which curves need fixing. You can turn it off in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Published after 20. Off for a teen driver.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(TreadChoice.allCases) { choice in
                    TreadChoiceButton(choice: choice, selection: $tread)
                }
                if tread?.replaceBeforeDriving == true {
                    Text("At the wear bars. Replace them.")
                        .font(.subheadline.bold())
                } else if tread == .low {
                    Text("Low tread. Ranges sit lower.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Tread")
                    .textCase(nil)
            }
        }
        .contentMargins(.bottom, 12, for: .scrollContent)
        .navigationTitle("RydAR")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 12) {
            Button {
                if let tread { TreadStore.save(tread) }
                DashPreference.isOn = true
                UserDefaults.standard.set(true, forKey: "rydar.uploadOptIn")
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .disabled(tread == nil)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("finishOnboarding")
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        if permissions.locationStatus == .notDetermined {
            Button("Allow location") {
                permissions.requestLocation()
            }
            .accessibilityIdentifier("allowLocation")
        } else if permissions.locationStatus == .denied || permissions.locationStatus == .restricted {
            Button("Turn on location in Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } else {
            Label("Location is on", systemImage: "location.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct TreadChoiceButton: View {
    var choice: TreadChoice
    @Binding var selection: TreadChoice?

    var body: some View {
        Button {
            selection = choice
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(choice.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selection == choice {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AuditTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tread-\(choice.rawValue)")
    }
}

struct TreadCheckScreen: View {
    var onContinue: () -> Void
    @State private var tread: TreadChoice?

    var body: some View {
        Form {
            Section {
                Text("About 1,000 miles since the last check.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(TreadChoice.allCases) { choice in
                    TreadChoiceButton(choice: choice, selection: $tread)
                }
                if tread?.replaceBeforeDriving == true {
                    Text("Replace them before this trip.")
                        .font(.subheadline.bold())
                }
            }
        }
        .contentMargins(.bottom, 12, for: .scrollContent)
        .navigationTitle("Check the tires")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 12) {
            Button {
                if let tread { TreadStore.save(tread) }
                onContinue()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .disabled(tread == nil)
            .padding(.horizontal, 24)
        }
    }
}

struct DriverGateScreen: View {
    var onStart: (DriverMode) -> Void
    @State private var selection: DriverMode?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach([DriverMode.adult, .under18], id: \.rawValue) { mode in
                        Button {
                            selection = mode
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(mode.screenTitle)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(mode.screenDetail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: selection == mode ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection == mode ? AuditTheme.accent : Color.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("driver-\(mode.rawValue)")
                        .accessibilityAddTraits(selection == mode ? .isSelected : [])
                    }
                } header: {
                    Text("Set up while parked")
                        .textCase(nil)
                } footer: {
                    if #unavailable(iOS 26) {
                        Text("This trip only.")
                    }
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.horizontal, 4, for: .scrollContent)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .navigationTitle("Who's driving?")
            .navigationBarTitleDisplayMode(.large)
            .rydarNavigationSubtitle("This trip only.")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 12) {
                Button {
                    if let selection { onStart(selection) }
                } label: {
                    Text("Start this trip")
                        .frame(maxWidth: .infinity)
                }
                .rydarProminentAction()
                .disabled(selection == nil)
                .padding(.horizontal, 28)
                .padding(.bottom, 4)
                .accessibilityIdentifier("confirmDriver")
            }
        }
    }
}
