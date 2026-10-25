import SwiftUI

struct DebriefScreen: View {
    @ObservedObject var trip: TripScreenBridge
    @Binding var uploadOptIn: Bool
    var onDone: () -> Void
    @State private var exportMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AuditEyebrow(text: "Parked / This trip")
                Text("A look back.\nAn earlier heads-up.").font(.largeTitle.bold())
                Text("\(trip.debrief.overRangePasses.count) over-range curve passes")
                    .font(.headline).foregroundStyle(AuditTheme.accent)
                Text("Largest gap above the low end first. This is screening, not an advisory speed.")
                    .font(.subheadline).foregroundStyle(.secondary)
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
                        Text("Gap above screening low end").font(.caption).foregroundStyle(.secondary)
                        Text("Approach · \(pass.effectiveMPH, specifier: "%.1f") mph").font(.subheadline)
                        ScreeningRangeLabel(range: pass.range)
                        Text("Surface used · \(pass.surfaceUsed.rawValue)").font(.subheadline)
                        Text("Braking onset · \(measurement(pass.brakingDistanceMeters, unit: "m before curve"))")
                            .font(.subheadline)
                        Text("Apparent lateral tilt · \(measurement(pass.apparentTiltDegrees, unit: "°"))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Curve \(pass.curve.id)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                AuditEyebrow(text: "Personal timing memory / On this phone")
                if trip.debrief.lateContexts.isEmpty {
                    Text("No context has enough late approaches to move the next prompt earlier.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(trip.debrief.lateContexts) { context in
                    AuditCard {
                        Label("Earlier next time", systemImage: "clock.arrow.circlepath").font(.headline)
                        Text(context.message).font(.subheadline)
                        Text("\(context.surface.rawValue.capitalized) · radius \(radiusBand(feet: context.representativeRadiusFeet)) ft · \(isNightHour(context.hour) ? "night" : "day")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Timing changes. The screening range stays the same.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                AuditCard {
                    Toggle("Opt in to anonymous pass uploads", isOn: $uploadOptIn)
                        .accessibilityIdentifier("debriefUpload")
                    Text("Off by default. Only curve ID, direction, a 5-mph speed band, hour bucket, app version, and optional lateral-acceleration band. No accounts or traces. Timing memory stays here.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !trip.isConnected {
                        Text("Preference saved. Upload service is not connected in this UI preview.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Save export on this iPhone", systemImage: "square.and.arrow.down") {
                        do {
                            let file = try LocalTripExport.save(trip.debrief)
                            exportMessage = "Saved on this iPhone in CurveAudit Exports: \(file.lastPathComponent). This file is excluded from device backups."
                        } catch { exportMessage = "Export could not be saved: \(error.localizedDescription)" }
                    }.disabled(trip.debrief.passes.isEmpty).accessibilityIdentifier("exportTrip")
                    Text("Export stays on device. It does not upload or open a share sheet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Done", action: onDone).buttonStyle(AuditPrimaryButton())
                    .accessibilityIdentifier("debriefDone")
            }.padding(24)
        }
        .background(AuditTheme.background)
        .navigationTitle("Trip debrief").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .onChange(of: uploadOptIn) { _, value in trip.onUploadPreference?(value) }
        .alert("Local export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }

    private func measurement(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "Not recorded" }
        return String(format: "%.1f %@", value, unit)
    }
}
