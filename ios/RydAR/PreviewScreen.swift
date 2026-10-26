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

/// Keeps a search or county frame at road or state scale. A continent-sized span becomes the state cap.
enum MapFraming {
    static let minimumDistance: CLLocationDistance = 300
    /// Wide enough for all of Arkansas, short of a continent camera.
    static let maximumDistance: CLLocationDistance = 2_500_000
    /// Top-down distance for the web map's ±0.01° frame, about two kilometers of road.
    static let roadCameraDistance: CLLocationDistance = 4_200

    struct Box: Equatable {
        var minLatitude: Double
        var maxLatitude: Double
        var minLongitude: Double
        var maxLongitude: Double
    }

    static func usable(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && latitude >= 32 && latitude <= 38
            && longitude >= -96 && longitude <= -88
    }

    static func focusCoordinate(_ curve: Curve) -> CLLocationCoordinate2D? {
        if usable(latitude: curve.latitude, longitude: curve.longitude) {
            return CLLocationCoordinate2D(latitude: curve.latitude, longitude: curve.longitude)
        }
        let latitude = (curve.minLatitude + curve.maxLatitude) / 2
        let longitude = (curve.minLongitude + curve.maxLongitude) / 2
        let latSpan = curve.maxLatitude - curve.minLatitude
        let lonSpan = curve.maxLongitude - curve.minLongitude
        guard usable(latitude: latitude, longitude: longitude),
              latSpan > 0, lonSpan > 0, latSpan < 0.2, lonSpan < 0.2 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func cameraDistance(
        latitudeDelta: Double,
        longitudeDelta: Double,
        latitude: Double,
        clamp: ClosedRange<CLLocationDistance>
    ) -> CLLocationDistance {
        let clampedLatitude = min(max(latitude, -60), 60)
        let latMeters = max(latitudeDelta, 0.002) * 111_320
        let lonMeters = max(longitudeDelta, 0.002) * 111_320 * max(0.25, cos(clampedLatitude * .pi / 180))
        let ground = max(latMeters, lonMeters)
        let raw = ground / (2 * tan(15 * .pi / 180))
        guard raw.isFinite else { return clamp.lowerBound }
        return min(max(raw, clamp.lowerBound), clamp.upperBound)
    }

    static func box(_ region: MKCoordinateRegion) -> Box {
        Box(
            minLatitude: region.center.latitude - region.span.latitudeDelta / 2,
            maxLatitude: region.center.latitude + region.span.latitudeDelta / 2,
            minLongitude: region.center.longitude - region.span.longitudeDelta / 2,
            maxLongitude: region.center.longitude + region.span.longitudeDelta / 2)
    }

    static func similar(_ previous: MKCoordinateRegion, _ next: MKCoordinateRegion) -> Bool {
        let span = max(next.span.latitudeDelta, 0.000_01)
        let latShift = abs(previous.center.latitude - next.center.latitude) / span
        let lonShift = abs(previous.center.longitude - next.center.longitude) / max(next.span.longitudeDelta, 0.000_01)
        let zoom = abs(previous.span.latitudeDelta - next.span.latitudeDelta) / span
        return latShift < 0.34 && lonShift < 0.34 && zoom < 0.25
    }

    static func coordinates(_ points: [MapPoint]) -> [CLLocationCoordinate2D] {
        points.compactMap { point in
            guard usable(latitude: point.latitude, longitude: point.longitude) else { return nil }
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
    }
}

struct PreviewScreen: View {
    let store: any CurveStore
    var isSampleStore: Bool
    @StateObject private var locator = NearbyLocator()
    @State private var curves: [Curve] = []
    @State private var counties: [CurveCounty] = []
    @State private var selected: Curve?
    @State private var countyName = "All of Arkansas"
    @State private var showPaved = true
    @State private var showUnpaved = true
    @State private var wide = true
    @State private var framed = false
    @State private var region = Self.arkansas
    @State private var position: MapCameraPosition = .region(Self.arkansas)
    @State private var searchGeneration = 0
    @State private var loadToken = 0
    @State private var cameraToken = 0
    @State private var lastLoaded: MKCoordinateRegion?
    @State private var roadCamera: MapCamera?
    @State private var roadHoldUntil: Date?
    @State private var roadFixes = 0
    @AppStorage(TreadStore.choiceKey) private var treadRaw = ""

    private var tread: TreadChoice { TreadChoice(rawValue: treadRaw) ?? .unsure }

    var body: some View {
        // No selection binding. MapKit frames a missing selection as the default
        // North America camera and writes that camera back over later pinches.
        Map(
            position: $position,
            bounds: MapCameraBounds(
                minimumDistance: MapFraming.minimumDistance,
                maximumDistance: MapFraming.maximumDistance)
        ) {
            UserAnnotation()
            ForEach(curves) { curve in
                curveLayers(curve)
            }
            if let selected, !curves.contains(where: { $0.id == selected.id }) {
                curveLayers(selected)
            }
        }
        .mapStyle(.standard(elevation: .automatic))
        .mapControls {
            if #available(iOS 26, *) {
                MapScaleView(alignment: .leading)
            } else {
                MapScaleView(anchorEdge: .leading)
            }
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
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
        .safeAreaInset(edge: .top, spacing: 8) {
            PreviewMapControls(
                store: store,
                counties: counties,
                countyName: $countyName,
                showPaved: $showPaved,
                showUnpaved: $showUnpaved,
                searchGeneration: searchGeneration,
                statusLine: statusLine,
                locatorStatus: locator.status,
                onPick: pick,
                onCounty: show,
                onShowAll: showAll,
                onAllowLocation: locator.allow)
        }
        .sheet(item: $selected) { curve in
            NavigationStack {
                CurveDetailSheet(curve: curve, tread: tread)
            }
            .presentationDetents([.height(300), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .onAppear { locator.allow() }
        .task { await loadCatalog() }
        .onMapCameraChange(frequency: .onEnd) { context in
            adopt(context.region)
        }
        .onChange(of: locator.fix) { _, location in
            guard let location, location.horizontalAccuracy <= 100, !framed else { return }
            let coordinate = location.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate),
                  coordinate.latitude.isFinite,
                  abs(coordinate.latitude) > 0.01 || abs(coordinate.longitude) > 0.01 else { return }
            framed = true
            countyName = "All of Arkansas"
            move(to: .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 3200,
                longitudinalMeters: 3200)))
        }
        .onChange(of: showPaved) { _, _ in
            scheduleLoad(region, force: true)
        }
        .onChange(of: showUnpaved) { _, _ in
            scheduleLoad(region, force: true)
        }
    }

    private var statusLine: String {
        if isSampleStore && counties.isEmpty { return "Sample roads." }
        if !showPaved && !showUnpaved { return "Turn a surface back on." }
        if wide { return "Zoom in, or search." }
        if curves.isEmpty { return "No curves here." }
        return "\(curves.count) curves"
    }

    @MapContentBuilder
    private func curveLayers(_ curve: Curve) -> some MapContent {
        let line = MapFraming.coordinates(curve.coordinates)
        if line.count >= 2 {
            MapPolyline(coordinates: line)
                .stroke(lineColor(curve), style: curveStroke(selected: curve.id == selected?.id))
        }
        if let center = MapFraming.focusCoordinate(curve) {
            Annotation("", coordinate: center, anchor: .center) {
                curveDot(curve)
            }
            .annotationTitles(.hidden)
        }
    }

    private func curveDot(_ curve: Curve) -> some View {
        let chosen = curve.id == selected?.id
        return Button {
            pick(curve)
        } label: {
            Circle()
                .fill(lineColor(curve))
                .frame(width: chosen ? 14 : 10, height: chosen ? 14 : 10)
                .overlay {
                    Circle().strokeBorder(.white, lineWidth: chosen ? 2.5 : 1.5)
                }
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Curve on \(curve.roadName)")
    }

    private func curveStroke(selected: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: selected ? 8 : 5, lineCap: .round, lineJoin: .round)
    }

    private func lineColor(_ curve: Curve) -> Color {
        curve.surface == .paved ? .teal : Color(red: 0.77, green: 0.48, blue: 0.17)
    }

    private func loadCatalog() async {
        let store = store
        let loaded = await Task.detached(priority: .userInitiated) {
            store.counties()
        }.value
        guard !Task.isCancelled else { return }
        counties = loaded
        await Task.detached(priority: .utility) {
            (store as? SQLiteCurveStore)?.warmSearchIndex()
        }.value
    }

    private func adopt(_ next: MKCoordinateRegion) {
        cameraToken &+= 1
        let token = cameraToken
        let span = next.span.latitudeDelta
        guard span.isFinite, span > 0, span < 20,
              next.center.latitude.isFinite, next.center.longitude.isFinite else { return }
        if let until = roadHoldUntil, Date() >= until {
            roadCamera = nil
            roadHoldUntil = nil
        }
        if let camera = roadCamera, span > 1.2, roadFixes < 2 {
            roadFixes += 1
            Task { @MainActor in
                guard token == cameraToken else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    position = .camera(camera)
                }
            }
            return
        }
        Task { @MainActor in
            guard token == cameraToken else { return }
            region = next
            scheduleLoad(next, force: false)
        }
    }

    private func scheduleLoad(_ region: MKCoordinateRegion, force: Bool) {
        let span = region.span.latitudeDelta
        guard span.isFinite, span > 0,
              region.center.latitude.isFinite,
              region.center.longitude.isFinite else { return }
        guard showPaved || showUnpaved else {
            curves = []
            wide = false
            lastLoaded = nil
            return
        }
        guard span <= 0.9 else {
            if !curves.isEmpty { curves = [] }
            wide = true
            lastLoaded = nil
            return
        }
        if !force, let lastLoaded, MapFraming.similar(lastLoaded, region) {
            wide = false
            return
        }
        wide = false
        loadToken &+= 1
        let token = loadToken
        let detailed = span <= 0.12
        let box = MapFraming.box(region)
        let paved = showPaved
        let unpaved = showUnpaved
        let store = store
        let limit = detailed ? 400 : 800
        Task.detached(priority: .userInitiated) {
            let found = store.curves(
                minLatitude: box.minLatitude,
                maxLatitude: box.maxLatitude,
                minLongitude: box.minLongitude,
                maxLongitude: box.maxLongitude,
                limit: limit,
                includeCoordinates: detailed
            ).filter { curve in
                guard canWarn(on: curve) else { return false }
                return curve.surface == .paved ? paved : unpaved
            }
            await MainActor.run {
                guard token == loadToken else { return }
                curves = found
                lastLoaded = region
                wide = false
            }
        }
    }

    private func showAll() {
        searchGeneration += 1
        countyName = "All of Arkansas"
        selected = nil
        move(to: .region(Self.arkansas))
    }

    private func show(_ county: CurveCounty) {
        searchGeneration += 1
        framed = true
        countyName = county.name
        let center = CLLocationCoordinate2D(
            latitude: (county.minLatitude + county.maxLatitude) / 2,
            longitude: (county.minLongitude + county.maxLongitude) / 2)
        let latDelta = (county.maxLatitude - county.minLatitude) * 1.25
        let lonDelta = (county.maxLongitude - county.minLongitude) * 1.25
        guard latDelta.isFinite, lonDelta.isFinite, latDelta > 0, lonDelta > 0,
              latDelta < 8, lonDelta < 8, CLLocationCoordinate2DIsValid(center) else {
            showAll()
            return
        }
        let countyRegion = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.02, latDelta),
                longitudeDelta: max(0.02, lonDelta)))
        move(to: .region(countyRegion))
    }

    private func pick(_ curve: Curve) {
        let full = store.curve(id: curve.id) ?? curve
        guard let center = MapFraming.focusCoordinate(full) else { return }
        framed = true
        countyName = full.county
        if let index = curves.firstIndex(where: { $0.id == full.id }) {
            if full.coordinates.count >= 2 { curves[index] = full }
        } else {
            curves.insert(full, at: 0)
        }
        selected = full
        let camera = MapCamera(
            centerCoordinate: center,
            distance: MapFraming.roadCameraDistance,
            heading: 0,
            pitch: 0)
        move(to: .camera(camera), holding: camera)
    }

    private func move(to next: MapCameraPosition, holding camera: MapCamera? = nil) {
        loadToken &+= 1
        if let camera {
            roadCamera = camera
            roadFixes = 0
            roadHoldUntil = Date().addingTimeInterval(0.7)
        } else {
            roadCamera = nil
            roadHoldUntil = nil
        }
        withAnimation(.smooth(duration: 0.45)) {
            position = next
        }
    }

    private static let arkansas = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.8, longitude: -92.2),
        span: MKCoordinateSpan(latitudeDelta: 4.2, longitudeDelta: 4.2))
}

private struct PreviewMapControls: View {
    let store: any CurveStore
    let counties: [CurveCounty]
    @Binding var countyName: String
    @Binding var showPaved: Bool
    @Binding var showUnpaved: Bool
    var searchGeneration: Int
    var statusLine: String
    var locatorStatus: CLAuthorizationStatus
    var onPick: (Curve) -> Void
    var onCounty: (CurveCounty) -> Void
    var onShowAll: () -> Void
    var onAllowLocation: () -> Void

    @State private var query = ""
    @State private var results: [Curve] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @Namespace private var mapGlass

    var body: some View {
        liquidGlassGroup {
            VStack(alignment: .leading, spacing: 14) {
                searchCard
                if query.count >= 2 && !results.isEmpty {
                    searchResults
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
                countyMenu
                HStack(spacing: 8) {
                    surfaceButton("Paved", on: showPaved, color: .teal) {
                        showPaved.toggle()
                    }
                    surfaceButton("Unpaved", on: showUnpaved, color: Color(red: 0.77, green: 0.48, blue: 0.17)) {
                        showUnpaved.toggle()
                    }
                }
                if locatorStatus == .notDetermined {
                    Button("Allow location", action: onAllowLocation)
                        .liquidGlassButton(prominent: true)
                        .mapGlassID("location", in: mapGlass)
                        .accessibilityIdentifier("nearbyAllow")
                }
            }
            .animation(.smooth(duration: 0.32), value: results.count)
            .animation(.smooth(duration: 0.32), value: locatorStatus.rawValue)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: showPaved) { _, _ in scheduleSearch() }
        .onChange(of: showUnpaved) { _, _ in scheduleSearch() }
        .onChange(of: searchGeneration) { _, _ in clearSearch() }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Road name", text: $query)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit {
                        if let first = results.first { choose(first) }
                    }
                    .accessibilityIdentifier("mapSearch")
                if !query.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear road search")
                }
            }
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            if locatorStatus == .denied || locatorStatus == .restricted {
                Text("Location is off. Search or pick a county.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
        .mapGlassID("search", in: mapGlass)
    }

    private var searchResults: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(results) { curve in
                    Button { choose(curve) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(curve.roadName.isEmpty ? "Unnamed road" : curve.roadName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(curve.county) County")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if curve.id != results.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .mapGlassID("results", in: mapGlass)
    }

    private var countyMenu: some View {
        Menu {
            Button("All of Arkansas", systemImage: "map", action: onShowAll)
            ForEach(counties) { county in
                Button(county.name, systemImage: "mappin.and.ellipse") { onCounty(county) }
            }
        } label: {
            Label(countyName, systemImage: "map")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .liquidGlassButton()
        .mapGlassID("county", in: mapGlass)
        .accessibilityIdentifier("mapCounty")
    }

    private func surfaceButton(_ title: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: on ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.semibold))
        }
        .liquidGlassButton(tint: on ? color : nil)
        .mapGlassID("surface-\(title)", in: mapGlass)
        .accessibilityIdentifier("surface-\(title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func liquidGlassGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 10, content: content)
        } else {
            content()
        }
    }

    private func choose(_ curve: Curve) {
        clearSearch()
        onPick(curve)
    }

    private func clearSearch() {
        searchTask?.cancel()
        query = ""
        results = []
        searchFocused = false
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        let paved = showPaved
        let unpaved = showUnpaved
        let store = store
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                store.searchRoads(trimmed, limit: 8, includePaved: paved, includeUnpaved: unpaved)
            }.value
            guard !Task.isCancelled else { return }
            results = found
        }
    }
}

private struct CurveDetailSheet: View {
    var curve: Curve
    var tread: TreadChoice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(curve.county) County")
                    .font(.title3.weight(.semibold))
                Label(curve.surface == .paved ? "Paved road" : "Unpaved road", systemImage: "road.lanes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Radius \(curve.radiusFeet, specifier: "%.0f") ft · \(curve.deflectionDegrees, specifier: "%.0f")°")
                    .font(.subheadline)
                ScreeningRangeLabel(range: screeningRange(
                    radiusFeet: curve.radiusFeet,
                    surface: curve.surface,
                    tread: tread))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(curve.roadName.isEmpty ? "Unnamed road" : curve.roadName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                MapCloseButton(action: dismiss.callAsFunction)
            }
        }
        .accessibilityIdentifier("curveDetail")
    }
}

private struct MapCloseButton: View {
    var action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: .close, action: action) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close curve details")
        } else {
            Button(action: action) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close curve details")
        }
    }
}

private extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func liquidGlassButton(tint: Color? = nil, prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else if let tint {
                self.buttonStyle(.glass(.regular.tint(tint)))
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
                .tint(tint)
        }
    }

    @ViewBuilder
    func mapGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
