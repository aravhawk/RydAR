import SwiftUI

struct DebriefScreen: View {
    @ObservedObject var trip: TripScreenBridge
    @AppStorage(UnitSystem.key) private var units = UnitSystem.imperial.rawValue
    var onDone: () -> Void
    @AppStorage("rydar.uploadOptIn") private var uploadOptIn = true
    @State private var exportMessage: String?

    /// The Settings switch can stay on while this trip sent nothing.
    private var uploadSentence: String {
        if trip.driverMode == .under18 {
            return "Nothing uploaded (teen driver)."
        }
        if !uploadOptIn {
            return "Uploads are off."
        }
        if trip.isConnected && !trip.uploadConfigured {
            return "Saved on this iPhone."
        }
        if trip.debrief.passes.isEmpty {
            return "No curves to share."
        }
        if trip.debrief.passes.contains(where: anonymousPassAccepted) {
            return "Shared anonymously."
        }
        return "Saved on this iPhone."
    }

    private var overSummary: String {
        let count = trip.debrief.overRangePasses.count
        return count == 1 ? "1 curve over the suggested speed" : "\(count) curves over the suggested speed"
    }

    /// Same acceptance rule as the uploader: `AnonymousPass.body` returns nil for a rejected pass.
    private func anonymousPassAccepted(_ pass: TripCurvePass) -> Bool {
        let completed = CompletedPass(
            curveID: pass.curve.id,
            direction: pass.direction,
            effectiveSpeedMPH: pass.effectiveMPH,
            vLoMPH: pass.range.low,
            vHiMPH: pass.range.high,
            spoke: false,
            hourBucket: pass.hourBucket,
            late: false,
            surfaceUsed: pass.surfaceUsed,
            radiusBand: "",
            lookAheadMeters: 0,
            contextKey: ""
        )
        return AnonymousPass.body(from: completed, appVersion: PassUpload.appVersion) != nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parked.")
                        .font(.largeTitle.bold())
                    Text(overSummary)
                        .font(.headline)
                        .foregroundStyle(RydarTheme.accentText)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if trip.debrief.overRangePasses.isEmpty {
                Section {
                    Label(trip.isConnected ? "None this trip" : "Nothing recorded", systemImage: "checkmark.circle")
                        .font(.headline)
                }
            }
            ForEach(trip.debrief.overRangePasses) { pass in
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text(pass.curve.roadName)
                            .font(.headline)
                        Spacer()
                        Text("+\(pass.gapAboveLowEnd * (UnitSystem.current == .imperial ? 1 : kilometersPerMile), specifier: "%.1f") \(UnitSystem.current.speedUnit)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(RydarTheme.warningText)
                    }
                    Text("You went \(speedText(mph: pass.effectiveMPH))")
                        .font(.subheadline)
                    ScreeningRangeLabel(range: pass.range)
                    Text(pass.surfaceUsed.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !trip.timingNote.isEmpty {
                Section {
                    Text(trip.timingNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("timingNote")
                }
            }
            ForEach(trip.debrief.earlierPromptCards) { card in
                Section {
                    Label("Warnings will come earlier", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Text(card.message)
                        .font(.subheadline)
                    Text(card.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text(uploadSentence)
                    .font(.subheadline)
                    .accessibilityIdentifier("debriefUpload")
                if trip.driverMode != .under18 {
                    Text("Shown publicly after 20 passes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save a copy", systemImage: "square.and.arrow.down") {
                    do {
                        _ = try LocalTripExport.save(trip.debrief)
                        exportMessage = "Saved on this iPhone."
                    } catch { exportMessage = "Couldn't save a copy: \(error.localizedDescription)" }
                }
                .disabled(trip.debrief.passes.isEmpty)
                .accessibilityIdentifier("exportTrip")
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 8, for: .scrollContent)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom, spacing: 12) {
            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .rydarProminentAction()
            .padding(.horizontal, 24)
            .accessibilityIdentifier("debriefDone")
        }
        .alert("Save a copy", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }
}
