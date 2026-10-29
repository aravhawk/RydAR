import SwiftUI

struct HomeScreen: View {
    let store: any CurveStore
    var onStart: () -> Void
    @ObservedObject var trip: TripScreenBridge
    @AppStorage("rydar.dashEnabled") private var dashEnabled = true
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""

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
                        Button(action: onStart) {
                            Label(tread?.replaceBeforeDriving == true ? "Start anyway" : "Start trip", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .rydarProminentAction()
                        .accessibilityIdentifier("startTrip")

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
}
