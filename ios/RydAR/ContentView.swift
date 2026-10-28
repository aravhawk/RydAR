import SwiftUI

@MainActor
struct ContentView: View {
    private let store: any CurveStore
    @StateObject private var trip: TripScreenBridge
    @AppStorage("rydar.onboardingComplete") private var onboarded = false
    @AppStorage("rydar.appearance") private var appearance = AppearancePreference.system.rawValue
    @AppStorage("rydar.promptStyle") private var promptStyle = PromptStyle.normal.rawValue
    @AppStorage("rydar.uploadOptIn") private var uploadOptIn = true
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""
    @State private var phase = ScreenPhase.home
    @State private var showDriverGate = false

    init(store: any CurveStore, trip: TripScreenBridge) {
        self.store = store
        _trip = StateObject(wrappedValue: trip)
    }

    var body: some View {
        NavigationStack {
            if !onboarded {
                OnboardingScreen { onboarded = true }
            } else if treadRaw.isEmpty && phase == .home {
                TreadCheckScreen { }
            } else {
                switch phase {
                case .home:
                    HomeScreen(store: store,
                               onStart: { showDriverGate = true }, trip: trip)
                case .drive:
                    DriveScreen(trip: trip) {
                        trip.finish()
                        phase = .debrief
                    }
                case .debrief:
                    DebriefScreen(trip: trip) { phase = .home }
                }
            }
        }
        .tint(RydarTheme.accent)
        .preferredColorScheme(AppearancePreference(rawValue: appearance)?.scheme)
        .sheet(isPresented: $showDriverGate) {
            DriverGateScreen { mode in
                trip.start(mode: mode, style: PromptStyle(rawValue: promptStyle) ?? .normal,
                           uploadOptIn: uploadOptIn)
                showDriverGate = false
                if trip.drive.gpsStatus != "Trip did not start" {
                    phase = .drive
                }
            }
            .tint(RydarTheme.accent)
        }
    }
}

private enum ScreenPhase { case home, drive, debrief }

