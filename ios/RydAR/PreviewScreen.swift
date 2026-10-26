import SwiftUI

struct PreviewScreen: View {
    let store: any CurveStore
    var isSampleStore: Bool
    @State private var road: PreviewRoad = .oldWire
    @State private var curves: [Curve] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Parked preview", systemImage: "parkingsign.circle.fill")
                    .font(.subheadline.bold()).foregroundStyle(AuditTheme.accent)
                Text("Read the road ahead.").font(.largeTitle.bold())
                Text("Parked. Advisory speeds for this road.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Road", selection: $road) {
                    ForEach(PreviewRoad.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("previewRoad")
                CurveMap(curves: curves, center: road.center).id(road)
                Text("\(curves.count) curves").font(.subheadline).foregroundStyle(.secondary)
                if curves.isEmpty {
                    ContentUnavailableView("No curves in this segment", systemImage: "map",
                                           description: Text("Choose another road segment."))
                }
                ForEach(curves) { curve in
                    AuditCard {
                        Text(curve.roadName).font(.headline)
                        ScreeningRangeLabel(range: screeningRange(
                            radiusFeet: curve.radiusFeet,
                            surface: fuseSurface(fileLabel: curve.surface, camera: nil, threshold: 1).0,
                            tread: TreadStore.choice ?? .unsure))
                        SurfaceBadge(fileSurface: curve.surface)
                        if !curve.qualityFlags.isEmpty {
                            Text("Skipped while driving.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if isSampleStore {
                    Text("Sample roads.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .background(AuditTheme.background)
        .navigationTitle("Preview route").navigationBarTitleDisplayMode(.inline)
        .task(id: road) {
            // Query a bounded area only when a segment opens or changes, never at app launch.
            curves = store.curves(nearLatitude: road.center.latitude, longitude: road.center.longitude,
                                  radiusMeters: 2_000)
                .filter { $0.county == road.county && $0.roadName == road.rawValue }
                .sorted { $0.id < $1.id }
        }
    }
}
