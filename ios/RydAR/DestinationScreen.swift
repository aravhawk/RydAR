import MapKit
import SwiftUI

/// Parked destination search. Picking a result asks Apple Maps for a driving route,
/// then closes. The route only narrows which curves warn; Maps stays the navigator.
struct DestinationScreen: View {
    @ObservedObject var planner: RoutePlanner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if case .failed(let message) = planner.phase {
                    Text(message)
                        .foregroundStyle(RydarTheme.warningText)
                        .accessibilityIdentifier("routeError")
                }
                if planner.phase == .planning {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Finding a route…")
                    }
                }
                ForEach(Array(planner.suggestions.enumerated()), id: \.offset) { _, suggestion in
                    Button {
                        planner.choose(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $planner.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Address or place")
            .onSubmit(of: .search) { planner.chooseTypedQuery() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .onAppear { planner.prepare() }
            .onChange(of: planner.plannedCount) { _, _ in dismiss() }
        }
    }
}
