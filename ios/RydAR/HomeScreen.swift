import SwiftUI

struct HomeScreen: View {
    let store: any CurveStore
    var isSampleStore: Bool
    var onStart: () -> Void
    @ObservedObject var trip: TripScreenBridge
    @AppStorage("rydar.dashEnabled") private var dashEnabled = true
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""

    private var tread: TreadChoice? { TreadChoice(rawValue: treadRaw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parked.")
                        .font(.largeTitle.bold())
                    Text(dashEnabled ? "Dash is on." : "Co-pilot. Camera off.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Alerts speak with Maps in front. Not for an under-18 driver.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !trip.timingNote.isEmpty {
                        Text(trip.timingNote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("timingNote")
                    }
                    if tread?.replaceBeforeDriving == true {
                        Text("Replace the tires before this trip.")
                            .font(.headline)
                    } else if tread == .low {
                        Text("Low tread. Ranges sit lower.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                RydarGlassGroup(spacing: 12) {
                    VStack(spacing: 12) {
                        Button(action: onStart) {
                            Label(tread?.replaceBeforeDriving == true ? "Start anyway" : "Start trip", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .rydarProminentAction()
                        .accessibilityIdentifier("startTrip")

                        NavigationLink {
                            PreviewScreen(store: store, isSampleStore: isSampleStore)
                        } label: {
                            Label("Map", systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .rydarGlassAction()
                        .navigationLinkIndicatorVisibility(.hidden)
                        .accessibilityIdentifier("previewRoute")
                    }
                }

                if isSampleStore {
                    Text("Sample roads only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("RydAR")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
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
}
