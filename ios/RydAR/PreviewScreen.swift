import SwiftUI
import MapKit
import CoreLocation

/// One precise fix so the parked map can open on the rider. The trip engine owns location once a drive starts.
final class NearbyLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    @Published private(set) var fix: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        status = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 25
        status = manager.authorizationStatus
    }

    func allow() {
        status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        if fix == nil || location.horizontalAccuracy < (fix?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
            fix = location
        }
        if location.horizontalAccuracy <= 50 {
            manager.stopUpdatingLocation()
        }
    }
}

struct PreviewScreen: View {
    let store: any CurveStore
    var isSampleStore: Bool
    @StateObject private var locator = NearbyLocator()
    @State private var curves: [Curve] = []
    @State private var counties: [CurveCounty] = []
    @State private var results: [Curve] = []
    @State private var selectedID: String?
    @State private var selected: Curve?
    @State private var query = ""
    @State private var countyName = "All of Arkansas"
    @State private var showPaved = true
    @State private var showUnpaved = true
    @State private var wide = true
    @State private var framed = false
    @State private var region = Self.arkansas
    @State private var position: MapCameraPosition = .region(Self.arkansas)
    @State private var searchTask: Task<Void, Never>?
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""

    private var tread: TreadChoice { TreadChoice(rawValue: treadRaw) ?? .unsure }

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            UserAnnotation()
            ForEach(curves) { curve in
                if curve.coordinates.count >= 2 {
                    MapPolyline(coordinates: curve.coordinates.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }).stroke(lineColor(curve), lineWidth: curve.id == selectedID ? 8 : 5)
                }
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: curve.latitude, longitude: curve.longitude), anchor: .center) {
                    Circle()
                        .fill(lineColor(curve))
                        .frame(width: curve.id == selectedID ? 16 : 12, height: curve.id == selectedID ? 16 : 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .accessibilityLabel("Curve on \(curve.roadName)")
                }
                .annotationTitles(.hidden)
                .tag(curve.id)
            }
            if let selected, selected.coordinates.count >= 2, !curves.contains(where: { $0.id == selected.id && $0.coordinates.count >= 2 }) {
                MapPolyline(coordinates: selected.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }).stroke(lineColor(selected), lineWidth: 8)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: showAll) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Reset the map")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { controls }
        .safeAreaInset(edge: .bottom, spacing: 0) { detail }
        .onAppear { locator.allow() }
        .task { counties = store.counties() }
        .onMapCameraChange(frequency: .onEnd) { context in
            region = context.region
            load(context.region)
        }
        .onChange(of: locator.fix) { _, location in
            guard let location, location.horizontalAccuracy <= 100, !framed else { return }
            framed = true
            countyName = "All of Arkansas"
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 3200,
                longitudinalMeters: 3200))
        }
        .onChange(of: selectedID) { _, id in
            guard let id else { selected = nil; return }
            let known = curves.first { $0.id == id }
            if let full = store.curve(id: id) {
                selected = full
            } else {
                selected = known
            }
        }
        .onChange(of: query) { _, text in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                results = store.searchRoads(text, limit: 24).filter(shows).prefix(8).map { $0 }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Road name", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("mapSearch")
            if query.count >= 2 && !results.isEmpty {
                ForEach(results) { curve in
                    Button { focus(curve) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(curve.roadName.isEmpty ? "Unnamed road" : curve.roadName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(curve.county) County").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                Menu {
                    Button("All of Arkansas", action: showAll)
                    ForEach(counties) { county in
                        Button(county.name) { show(county) }
                    }
                } label: {
                    Label(countyName, systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .accessibilityIdentifier("mapCounty")
                Spacer(minLength: 8)
                surfaceButton("Paved", on: showPaved, color: .teal) { showPaved.toggle(); load(region) }
                surfaceButton("Unpaved", on: showUnpaved, color: Color(red: 0.77, green: 0.48, blue: 0.17)) {
                    showUnpaved.toggle()
                    load(region)
                }
            }
            Text(statusLine).font(.caption).foregroundStyle(.secondary)
            if locator.status == .notDetermined {
                Button("Allow location", action: locator.allow)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("nearbyAllow")
            } else if locator.status == .denied || locator.status == .restricted {
                Text("Location is off. Search or pick a county.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    @ViewBuilder private var detail: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selected.roadName.isEmpty ? "Unnamed road" : selected.roadName)
                        .font(.headline)
                    Spacer()
                    Button {
                        selectedID = nil
                        self.selected = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close curve details")
                }
                Text("\(selected.county) County, \(selected.surface == .paved ? "paved" : "unpaved") road")
                    .font(.subheadline)
                Text("Radius \(selected.radiusFeet, specifier: "%.0f") ft, turning \(selected.deflectionDegrees, specifier: "%.0f") degrees")
                    .font(.subheadline)
                ScreeningRangeLabel(range: screeningRange(
                    radiusFeet: selected.radiusFeet,
                    surface: selected.surface,
                    tread: tread))
                Text("Advisory speed, accurate as computed. The intention is a prompt before the bend.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .accessibilityIdentifier("curveDetail")
        }
    }

    private var statusLine: String {
        if isSampleStore && counties.isEmpty { return "Sample roads." }
        if !showPaved && !showUnpaved { return "Both surfaces are off. Turn paved or unpaved back on." }
        if wide { return "Zoom in, choose a county, or search for a road." }
        if curves.isEmpty { return "No filed curves in this view." }
        return "\(curves.count) curves in view. Tap one for its advisory speed."
    }

    private func surfaceButton(_ title: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("surface-\(title)")
    }

    private func lineColor(_ curve: Curve) -> Color {
        curve.surface == .paved ? .teal : Color(red: 0.77, green: 0.48, blue: 0.17)
    }

    private func shows(_ curve: Curve) -> Bool {
        guard canWarn(on: curve) else { return false }
        return curve.surface == .paved ? showPaved : showUnpaved
    }

    private func load(_ region: MKCoordinateRegion) {
        guard showPaved || showUnpaved else {
            curves = []
            wide = false
            return
        }
        let span = region.span.latitudeDelta
        guard span > 0, span <= 0.9 else {
            curves = []
            wide = true
            return
        }
        wide = false
        let detailed = span <= 0.12
        curves = store.curves(
            minLatitude: region.center.latitude - region.span.latitudeDelta / 2,
            maxLatitude: region.center.latitude + region.span.latitudeDelta / 2,
            minLongitude: region.center.longitude - region.span.longitudeDelta / 2,
            maxLongitude: region.center.longitude + region.span.longitudeDelta / 2,
            limit: detailed ? 400 : 800,
            includeCoordinates: detailed
        ).filter(shows)
    }

    private func showAll() {
        countyName = "All of Arkansas"
        query = ""
        results = []
        selectedID = nil
        selected = nil
        position = .region(Self.arkansas)
    }

    private func show(_ county: CurveCounty) {
        countyName = county.name
        query = ""
        results = []
        let center = CLLocationCoordinate2D(
            latitude: (county.minLatitude + county.maxLatitude) / 2,
            longitude: (county.minLongitude + county.maxLongitude) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (county.maxLatitude - county.minLatitude) * 1.25),
            longitudeDelta: max(0.02, (county.maxLongitude - county.minLongitude) * 1.25))
        position = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func focus(_ curve: Curve) {
        query = ""
        results = []
        countyName = curve.county
        let full = store.curve(id: curve.id) ?? curve
        selected = full
        selectedID = full.id
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: full.latitude, longitude: full.longitude),
            latitudinalMeters: 1400,
            longitudinalMeters: 1400))
    }

    private static let arkansas = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.8, longitude: -92.2),
        span: MKCoordinateSpan(latitudeDelta: 4.2, longitudeDelta: 4.2))
}
