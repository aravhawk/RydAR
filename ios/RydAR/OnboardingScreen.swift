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
                        .foregroundStyle(RydarTheme.accent)
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
                    Text("Keep RydAR open while you drive. It vibrates twice, then speaks over Maps and music.")
                        .font(.subheadline)
                    Text("For example: “\(spokenWarningExample)”")
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
                    Text("Camera check is on")
                        .font(.headline)
                    Text("Mount the phone with the camera facing the road, or turn it off in Settings. It spots gravel on roads listed as paved.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sharing anonymous curve data")
                        .font(.headline)
                    Text("Sends the curve, direction, speed, and hour. Never your name or route. Turn it off in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(TreadChoice.allCases) { choice in
                    TreadChoiceButton(choice: choice, selection: $tread)
                }
                if tread?.replaceBeforeDriving == true {
                    Text("Your tires are worn out. Replace them.")
                        .font(.subheadline.bold())
                } else if tread == .low {
                    Text("Low tread. Speed advice will be lower.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Tire tread")
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
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
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
                        .foregroundStyle(RydarTheme.accent)
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
                Text("It's been about 1,000 miles. How do your tires look?")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(TreadChoice.allCases) { choice in
                    TreadChoiceButton(choice: choice, selection: $tread)
                }
                if tread?.replaceBeforeDriving == true {
                    Text("Replace them before driving.")
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
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
    }
}

struct DriverGateScreen: View {
    var onStart: (DriverMode) -> Void
    @State private var selection: DriverMode?
    /// The sheet is exactly as tall as its content. iPhone sheets size by detent, so the
    /// content's own height is measured and used as the detent.
    @State private var contentHeight: CGFloat = 360

    private let choices: [DriverMode] = [.adult, .under18]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Who's driving?")
                    .font(.title2.bold())
                Text("This trip only.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.element.rawValue) { index, mode in
                    choiceRow(mode)
                    if index < choices.count - 1 {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )

            Button {
                if let selection { onStart(selection) }
            } label: {
                Text("Start this trip")
                    .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .disabled(selection == nil)
            .accessibilityIdentifier("confirmDriver")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SheetHeightKey.self) { contentHeight = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RydarTheme.background.ignoresSafeArea())
        .presentationDetents([.height(contentHeight + bottomInset)])
        .presentationDragIndicator(.visible)
        .presentationBackground(RydarTheme.background)
    }

    /// The detent height includes the home-indicator area, which the content does not use.
    private var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }

    private func choiceRow(_ mode: DriverMode) -> some View {
        let chosen = selection == mode
        return Button {
            selection = mode
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.screenTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(mode.screenDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen ? RydarTheme.accent : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("driver-\(mode.rawValue)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
