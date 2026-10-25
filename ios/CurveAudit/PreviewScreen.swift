import SwiftUI

struct PreviewScreen: View {
    let store: any CurveStore
    let county: String
    var isSampleStore: Bool
    @State private var road: PreviewRoad
    @State private var curves: [Curve] = []

    init(store: any CurveStore, county: String, isSampleStore: Bool) {
        self.store = store
        self.county = county
        self.isSampleStore = isSampleStore
        _road = State(initialValue: county == "Washington" ? .grove : .oldWire)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Parked preview", systemImage: "parkingsign.circle.fill")
                    .font(.subheadline.bold()).foregroundStyle(AuditTheme.accent)
                Text("Read the road ahead.").font(.largeTitle.bold())
                Text("Choose a road segment to inspect its candidate curves. This is a screening preview, not turn-by-turn navigation.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Road segment", selection: $road) {
                    ForEach(PreviewRoad.allCases.filter { $0.county == county }) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("previewRoad")
                CurveMap(curves: curves, center: road.center).id(road)
                AuditEyebrow(text: "\(curves.count) candidate curves / \(county)")
                if curves.isEmpty {
                    ContentUnavailableView("No curves in this segment", systemImage: "map",
                                           description: Text("Choose another road segment."))
                }
                ForEach(curves) { curve in
                    AuditCard {
                        Text(curve.roadName).font(.headline)
                        Text("Curve \(curve.id)").font(.caption).foregroundStyle(.secondary)
                        ScreeningRangeLabel(range: screeningRange(
                            radiusFeet: curve.radiusFeet,
                            surface: fuseSurface(fileLabel: curve.surface, camera: nil, threshold: 1).0))
                        SurfaceBadge(fileSurface: curve.surface)
                        Text(curve.qualityFlags.isEmpty
                             ? "Geometry candidate · road match not assessed while parked"
                             : "Geometry quality flagged · not eligible for driving prompts")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(isSampleStore
                     ? "Five-row UI fixture · copied from the bundled database. Surface source: Arkansas GIS Office road file."
                     : "Surface source: Arkansas GIS Office road file. Map tiles may require a connection; curve details are bundled.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
        .background(AuditTheme.background)
        .navigationTitle("Preview route").navigationBarTitleDisplayMode(.inline)
        .task(id: road) {
            // Query a bounded area only when a segment opens or changes, never at app launch.
            curves = store.curves(nearLatitude: road.center.latitude, longitude: road.center.longitude,
                                  radiusMeters: 2_000)
                .filter { $0.county == county && $0.roadName == road.rawValue }
                .sorted { $0.id < $1.id }
        }
    }
}
