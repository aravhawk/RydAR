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
            VStack(alignment: .leading, spacing: 22) {
                Text("Parked.").font(.largeTitle.bold())
                Text(dashEnabled ? "Dash is on." : "Co-pilot. Camera off.")
                    .foregroundStyle(.secondary)
                Text("Leave RydAR open. Alerts still speak if Maps is in front, unless the driver is under 18.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if tread?.replaceBeforeDriving == true {
                    Text("Replace the tires before this trip.")
                        .font(.headline)
                } else if tread == .low {
                    Text("Low tread. Curve ranges sit lower.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button(action: onStart) {
                    Label(tread?.replaceBeforeDriving == true ? "Start anyway" : "Start trip", systemImage: "arrow.right")
                }.buttonStyle(AuditPrimaryButton()).accessibilityIdentifier("startTrip")
                NavigationLink {
                    PreviewScreen(store: store, isSampleStore: isSampleStore)
                } label: {
                    Label("Map", systemImage: "map")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("previewRoute")
                if isSampleStore {
                    Text("Sample roads only.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .background(AuditTheme.background)
        .navigationTitle("RydAR").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsScreen(trip: trip) } label: {
                    Image(systemName: "gearshape").accessibilityLabel("Settings")
                }.accessibilityIdentifier("settings")
            }
        }
    }
}
