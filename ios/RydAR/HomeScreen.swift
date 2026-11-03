import SwiftUI
import UIKit

struct HomeScreen: View {
    let store: any CurveStore
    var onStart: () -> Void
    @ObservedObject var trip: TripScreenBridge
    @AppStorage("rydar.dashEnabled") private var dashEnabled = true
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""
    @StateObject private var readiness = TripReadinessMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    private var tread: TreadChoice? { TreadChoice(rawValue: treadRaw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parked.")
                        .font(.largeTitle.bold())
                    Text(dashEnabled ? "Camera check is on." : "Camera check is off.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("cameraStatus")
                    Text(dashEnabled
                         ? "Mount the phone with the camera facing the road, or turn it off."
                         : "Turn it on only with the phone mounted and the camera facing the road.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !trip.timingNote.isEmpty {
                        Text(trip.timingNote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("timingNote")
                    }
                    if !readiness.readiness.explanation.isEmpty {
                        Text(readiness.readiness.explanation)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(readiness.readiness == .outsideArkansas ? Color.primary : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("tripReadiness")
                    }
                    if tread?.replaceBeforeDriving == true {
                        Text("Replace your tires before driving.")
                            .font(.headline)
                    } else if tread == .low {
                        Text("Low tread. Speed advice is lower.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                RydarGlassGroup(spacing: 12) {
                    VStack(spacing: 12) {
                        tripAction

                        NavigationLink {
                            MapScreen(store: store)
                        } label: {
                            Label("Map", systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .rydarGlassAction()
                        .navigationLinkIndicatorVisibility(.hidden)
                        .accessibilityIdentifier("openMap")
                    }
                }

            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { readiness.refresh() }
        .onDisappear { readiness.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { readiness.refresh() } else { readiness.stop() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("RydAR")
                    .font(.body.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsScreen(trip: trip) } label: {
                    Image(systemName: "gearshape")
                        .symbolRenderingMode(.monochrome)
                        .accessibilityLabel("Settings")
                }
                .accessibilityIdentifier("settings")
            }
        }
    }

    /// Start trip when a trip can run here. Otherwise the one step that unblocks it.
    @ViewBuilder
    private var tripAction: some View {
        switch readiness.readiness {
        case .ready:
            Button(action: onStart) {
                Label(tread?.replaceBeforeDriving == true ? "Start anyway" : "Start trip", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .accessibilityIdentifier("startTrip")
        case .needsPermission:
            Button { readiness.requestPermission() } label: {
                Label("Allow location", systemImage: "location")
                    .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .accessibilityIdentifier("allowTripLocation")
        case .locationOff, .needsPrecise:
            Button(action: openSettings) {
                Label(readiness.readiness == .needsPrecise ? "Turn on Precise Location" : "Turn on location in Settings",
                      systemImage: "location.slash")
                    .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .accessibilityIdentifier("openLocationSettings")
        case .locating:
            Button(action: {}) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Start trip")
                }
                .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .disabled(true)
            .accessibilityLabel("Start trip, finding your location")
            .accessibilityIdentifier("startTrip")
        case .outsideArkansas:
            Button(action: {}) {
                Label("Start trip", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .disabled(true)
            .accessibilityHint("RydAR covers Arkansas roads. More states are coming soon.")
            .accessibilityIdentifier("startTrip")
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
