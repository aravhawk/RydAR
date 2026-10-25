import SwiftUI

@MainActor
struct ContentView: View {
    private let store: any CurveStore
    private let isSampleStore: Bool
    @StateObject private var trip: TripScreenBridge
    @AppStorage("rydar.onboardingComplete") private var onboarded = false
    @AppStorage("rydar.promptStyle") private var promptStyle = PromptStyle.normal.rawValue
    @AppStorage("rydar.uploadOptIn") private var uploadOptIn = false
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""
    @State private var phase = ScreenPhase.home
    @State private var showDriverGate = false

    init(store: any CurveStore = PreviewCurves(), trip: TripScreenBridge? = nil) {
        self.store = store
        isSampleStore = store is PreviewCurves
        _trip = StateObject(wrappedValue: trip ?? TripScreenBridge())
    }

    var body: some View {
        NavigationStack {
            if !onboarded {
                OnboardingScreen { onboarded = true }
            } else if treadRaw.isEmpty {
                TreadCheckScreen { }
            } else {
                switch phase {
                case .home:
                    HomeScreen(store: store, isSampleStore: isSampleStore,
                               onStart: { showDriverGate = true }, trip: trip)
                case .drive:
                    DriveScreen(trip: trip) {
                        trip.finish()
                        phase = .debrief
                    }
                case .debrief:
                    DebriefScreen(trip: trip, uploadOptIn: $uploadOptIn) { phase = .home }
                }
            }
        }
        .tint(AuditTheme.accent)
        .sheet(isPresented: $showDriverGate) {
            DriverGateScreen { mode in
                trip.start(mode: mode, style: PromptStyle(rawValue: promptStyle) ?? .normal,
                           uploadOptIn: uploadOptIn)
                showDriverGate = false
                phase = .drive
            }
        }
    }
}

private enum ScreenPhase { case home, drive, debrief }

#Preview { ContentView() }
