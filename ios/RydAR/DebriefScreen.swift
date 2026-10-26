import SwiftUI

struct DebriefScreen: View {
    @ObservedObject var trip: TripScreenBridge
    var onDone: () -> Void
    @AppStorage("rydar.uploadOptIn") private var uploadOptIn = true
    @State private var exportMessage: String?

    /// The Settings switch can stay on while this trip sent nothing.
    private var uploadSentence: String {
        if trip.driverMode == .under18 {
            return "Not uploaded. Under 18."
        }
        if !uploadOptIn {
            return "Uploads are off."
        }
        if trip.isConnected && !trip.uploadConfigured {
            return "Saved on this iPhone."
        }
        if trip.debrief.passes.isEmpty {
            return "Nothing to send."
        }
        if trip.debrief.passes.contains(where: anonymousPassAccepted) {
            return "Sent. No name or route."
        }
        return "Saved on this iPhone."
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
                    Text("\(trip.debrief.overRangePasses.count) curves above the range")
                        .font(.headline)
                        .foregroundStyle(AuditTheme.accentText)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if trip.debrief.overRangePasses.isEmpty {
                Section {
                    Label(trip.isConnected ? "None this trip" : "Not recorded", systemImage: "checkmark.circle")
                        .font(.headline)
                }
            }
            ForEach(trip.debrief.overRangePasses) { pass in
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text(pass.curve.roadName)
                            .font(.headline)
                        Spacer()
                        Text("+\(pass.gapAboveLowEnd, specifier: "%.1f") mph")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(AuditTheme.warningText)
                    }
                    Text("Approach \(pass.effectiveMPH, specifier: "%.0f") mph")
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
            ForEach(trip.debrief.lateContexts) { context in
                Section {
                    Label("Earlier next time", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Text(trip.driverMode == .under18 ? "No prompt. Under 18." : context.message)
                        .font(.subheadline)
                    Text("\(context.surface.rawValue.capitalized) · \(isNightHour(context.hour) ? "night" : "day")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text(uploadSentence)
                    .font(.subheadline)
                    .accessibilityIdentifier("debriefUpload")
                if trip.driverMode != .under18 {
                    Text("Published after 20.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save a copy", systemImage: "square.and.arrow.down") {
                    do {
                        _ = try LocalTripExport.save(trip.debrief)
                        exportMessage = "Saved on this iPhone."
                    } catch { exportMessage = "Export could not be saved: \(error.localizedDescription)" }
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
