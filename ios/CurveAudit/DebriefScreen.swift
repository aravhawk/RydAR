import SwiftUI

struct DebriefScreen: View {
    @ObservedObject var trip: TripScreenBridge
    @Binding var uploadOptIn: Bool
    var onDone: () -> Void
    @State private var exportMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Parked.").font(.largeTitle.bold())
                Text("\(trip.debrief.overRangePasses.count) curves above the range")
                    .font(.headline).foregroundStyle(AuditTheme.accent)
                if trip.debrief.overRangePasses.isEmpty {
                    AuditCard {
                        Label("No over-range passes recorded", systemImage: "checkmark.circle")
                            .font(.headline)
                        Text(trip.isConnected
                             ? "Only passes saved for this trip appear here."
                             : "This UI preview did not record a trip. Connect the trip engine to review saved passes.")
                            .font(.subheadline).foregroundStyle(.secondary)
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
                if trip.debrief.lateContexts.isEmpty {
                    Text("No context has enough late approaches to move the next prompt earlier.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(trip.debrief.lateContexts) { context in
                    AuditCard {
                        Label("Earlier next time", systemImage: "clock.arrow.circlepath").font(.headline)
                        Text(context.message).font(.subheadline)
                        Text("\(context.surface.rawValue.capitalized) · \(isNightHour(context.hour) ? "night" : "day")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                AuditCard {
                    Toggle("Opt in to anonymous pass uploads", isOn: $uploadOptIn)
                        .accessibilityIdentifier("debriefUpload")
                    Text("A count for a curve. Not your route.")
                        .font(.caption).foregroundStyle(.secondary)
                    if trip.isConnected && !trip.uploadConfigured {
                        Text("Saved here. No upload address in this build.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Save export on this iPhone", systemImage: "square.and.arrow.down") {
                        do {
                            let file = try LocalTripExport.save(trip.debrief)
                            exportMessage = "Saved on this iPhone."
                        } catch { exportMessage = "Export could not be saved: \(error.localizedDescription)" }
                    }.disabled(trip.debrief.passes.isEmpty).accessibilityIdentifier("exportTrip")
                }
                Button("Done", action: onDone).buttonStyle(AuditPrimaryButton())
                    .accessibilityIdentifier("debriefDone")
            }.padding(24)
        }
        .background(AuditTheme.background)
        .navigationTitle("Trip debrief").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .onChange(of: uploadOptIn) { _, value in trip.onUploadPreference?(value) }
        .alert("Saved", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }
}
