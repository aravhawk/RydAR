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
        return "Sent. No name or route."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Parked.").font(.largeTitle.bold())
                Text("\(trip.debrief.overRangePasses.count) curves above the range")
                    .font(.headline).foregroundStyle(AuditTheme.accent)
                if trip.debrief.overRangePasses.isEmpty {
                    AuditCard {
                        Label(trip.isConnected ? "None this trip" : "Not recorded", systemImage: "checkmark.circle")
                            .font(.headline)
                    }
                }
                ForEach(trip.debrief.overRangePasses) { pass in
                    AuditCard {
                        HStack(alignment: .firstTextBaseline) {
                            Text(pass.curve.roadName).font(.headline)
                            Spacer()
                            Text("+\(pass.gapAboveLowEnd, specifier: "%.1f") mph")
                                .font(.headline.monospacedDigit()).foregroundStyle(.orange)
                        }
                        Text("Approach \(pass.effectiveMPH, specifier: "%.0f") mph").font(.subheadline)
                        ScreeningRangeLabel(range: pass.range)
                        Text(pass.surfaceUsed.rawValue.capitalized).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !trip.timingNote.isEmpty {
                    Text(trip.timingNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("timingNote")
                }
                ForEach(trip.debrief.lateContexts) { context in
                    AuditCard {
                        Label("Earlier next time", systemImage: "clock.arrow.circlepath").font(.headline)
                        Text(trip.driverMode == .under18 ? "No prompt. Under 18." : context.message)
                            .font(.subheadline)
                        Text("\(context.surface.rawValue.capitalized) · \(isNightHour(context.hour) ? "night" : "day")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                AuditCard {
                    Text(uploadSentence)
                        .font(.subheadline)
                        .accessibilityIdentifier("debriefUpload")
                    if trip.driverMode != .under18 {
                        Text("Published after 20.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Save a copy", systemImage: "square.and.arrow.down") {
                        do {
                            _ = try LocalTripExport.save(trip.debrief)
                            exportMessage = "Saved on this iPhone."
                        } catch { exportMessage = "Export could not be saved: \(error.localizedDescription)" }
                    }.disabled(trip.debrief.passes.isEmpty).accessibilityIdentifier("exportTrip")
                }
                Button("Done", action: onDone).buttonStyle(AuditPrimaryButton())
                    .accessibilityIdentifier("debriefDone")
            }.padding(24)
        }
        .background(AuditTheme.background)
        .navigationTitle("Review").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .alert("Saved", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }
}
