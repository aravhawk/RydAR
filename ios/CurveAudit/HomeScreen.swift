import SwiftUI

struct HomeScreen: View {
    let store: any CurveStore
    var isSampleStore: Bool
    @Binding var county: String
    var onStart: () -> Void
    @ObservedObject var trip: TripScreenBridge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AuditEyebrow(text: "Northwest Arkansas")
                Text("A little context\nbefore the bend.")
                    .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                Text("Curve screening, built from Arkansas road geometry. Available in Benton and Washington.")
                    .foregroundStyle(.secondary)
                Picker("County", selection: $county) {
                    Text("Benton").tag("Benton")
                    Text("Washington").tag("Washington")
                }.pickerStyle(.segmented).accessibilityIdentifier("countyPicker")
                AuditCard {
                    HStack {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 36)).foregroundStyle(AuditTheme.accent)
                        Spacer()
                        Text("\(county)\nCounty").font(.headline).multilineTextAlignment(.trailing)
                    }
                    Text("Ready when you're parked.").font(.title2.bold())
                    Text("Choose who's driving before each trip. Co-pilot uses the county-file surface; camera is off.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(action: onStart) {
                        Label("Start trip", systemImage: "arrow.right")
                    }.buttonStyle(AuditPrimaryButton()).accessibilityIdentifier("startTrip")
                    NavigationLink {
                        PreviewScreen(store: store, county: county, isSampleStore: isSampleStore)
                    } label: {
                        Label("Preview route", systemImage: "map")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }.accessibilityIdentifier("previewRoute")
                }
                Label("No account · no curve download after install", systemImage: "iphone.gen3")
                    .font(.footnote).foregroundStyle(.secondary)
                if isSampleStore {
                    Text("UI preview · five sample curves. Live trip recording is not connected.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .background(AuditTheme.background)
        .navigationTitle("CurveAudit AR").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsScreen(trip: trip) } label: {
                    Image(systemName: "gearshape").accessibilityLabel("Settings")
                }.accessibilityIdentifier("settings")
            }
        }
    }
}
