import Foundation

/// A local file only: no share sheet, cloud destination, network call, or upload payload.
enum LocalTripExport {
    static func csv(_ debrief: TripScreenDebrief) -> String {
        let header = "trip_id,curve_id,road,county,surface_used,effective_mph,screening_low_mph,screening_high_mph,braking_distance_m,apparent_tilt_deg"
        let rows = debrief.passes.map { pass in
            [cell(debrief.tripID), cell(pass.curve.id), cell(pass.curve.roadName), cell(pass.curve.county),
             cell(pass.surfaceUsed.rawValue), number(pass.effectiveMPH), number(pass.range.low),
             number(pass.range.high), number(pass.brakingDistanceMeters), number(pass.apparentTiltDegrees)]
                .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func save(_ debrief: TripScreenDebrief) throws -> URL {
        let folder = try directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Do not accept a backend-provided trip ID as a filesystem path.
        var file = folder.appendingPathComponent("RydAR-\(UUID().uuidString).csv")
        try Data(csv(debrief).utf8).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
        return file
    }

    static func deleteAll() throws {
        let folder = try directory()
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    private static func directory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("RydAR Exports", isDirectory: true)
    }
    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    private static func cell(_ value: String) -> String {
        let prefix = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = prefix.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
