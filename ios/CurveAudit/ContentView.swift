import SwiftUI

struct ContentView: View {
    private let sample = screeningRange(radiusFeet: 200, surface: .paved)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CurveAudit AR")
                .font(.title.bold())
            Text("Screening range for a 200 ft paved curve")
                .font(.headline)
            Text("\(sample.low, specifier: "%.1f")–\(sample.high, specifier: "%.1f") mph")
                .font(.title2.monospacedDigit())
            Text("Screening range — not an advisory speed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("This build is the shared shell. Location, speech, and the camera are not wired up yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
