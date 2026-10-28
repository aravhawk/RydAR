import SwiftUI

struct HomeScreen: View {
    let store: any CurveStore
    var onStart: () -> Void
    @ObservedObject var trip: TripScreenBridge
    @ObservedObject var planner: RoutePlanner
    @State private var showDestination = false
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
                    Text("Alerts speak with Maps in front. Teen driver uses audio only.")
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

                routeCard

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
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showDestination) {
            DestinationScreen(planner: planner)
                .tint(RydarTheme.accent)
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

    private var routeCard: some View {
        RydarCard {
            if let route = planner.route {
                Label(route.name, systemImage: "location.north.line")
                    .font(.headline)
                Text("\(route.summary) · warns only for curves on this route")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("routeSummary")
                HStack {
                    Button("Change") { showDestination = true }
                    Spacer()
                    Button("Clear", role: .destructive) { planner.clear() }
                        .accessibilityIdentifier("clearRoute")
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Button {
                    planner.prepare()
                    showDestination = true
                } label: {
                    Label("Where to? (optional)", systemImage: "magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chooseDestination")
                Text("Pick a destination to hear only the curves on your route. Without one, RydAR warns about every curve ahead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
