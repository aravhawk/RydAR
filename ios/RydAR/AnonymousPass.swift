import Foundation

/// The body in Contracts/pass.json. Timing memory, traces, and frames stay off this payload.
struct AnonymousPassBody: Equatable, Encodable {
    var curve_id: String
    var direction: String
    var speed_band_mph: Int
    var hour_bucket: Int
    var app_version: String
}

enum AnonymousPass {
    /// Floor of the approach speed, in 5 mph steps, clamped to the server's range.
    static func speedBand(_ mph: Double) -> Int {
        guard mph.isFinite else { return 0 }
        let steps = Int((mph / 5).rounded(.down))
        return min(150, max(0, steps * 5))
    }

    static func body(from pass: CompletedPass, appVersion: String) -> AnonymousPassBody? {
        guard isCurveID(pass.curveID) else { return nil }
        guard (1...8).contains(pass.direction.count) else { return nil }
        guard (0...23).contains(pass.hourBucket) else { return nil }
        let version = String(appVersion.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !version.isEmpty else { return nil }
        return AnonymousPassBody(
            curve_id: pass.curveID,
            direction: pass.direction,
            speed_band_mph: speedBand(pass.effectiveSpeedMPH),
            hour_bucket: pass.hourBucket,
            app_version: version
        )
    }

    /// County code is an Arkansas FIPS: odd numbers from 001 through 149.
    static func isCurveID(_ id: String) -> Bool {
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 3, parts[0].allSatisfy(\.isNumber),
              let county = Int(parts[0]), county >= 1, county <= 149, county % 2 == 1 else { return false }
        return parts[1].count >= 1 && parts[1].count <= 7 && parts[1].allSatisfy(\.isNumber)
            && parts[2].count >= 1 && parts[2].count <= 7 && parts[2].allSatisfy(\.isNumber)
    }
}

protocol PassSending: AnyObject {
    func send(_ body: AnonymousPassBody)
}

/// Posts one pass. A missing address skips the request. The drive does not wait on the response.
final class PassUpload: PassSending {
    var endpoint: URL?
    var session: URLSession

    init(endpoint: URL? = PassUpload.bundledEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    static var bundledEndpoint: URL? {
        #if targetEnvironment(simulator)
        // Simulator replays and test runs must never post synthetic passes to the live site.
        return nil
        #else
        return configuredEndpoint
        #endif
    }

    private static var configuredEndpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RydARPassEndpoint") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// Empty when the bundle has no version. `AnonymousPass.body` then returns nil and nothing is sent.
    static var appVersion: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isConfigured: Bool { endpoint != nil }

    func send(_ body: AnonymousPassBody) {
        guard let endpoint else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        guard let data = try? JSONEncoder().encode(body) else { return }
        request.httpBody = data
        session.dataTask(with: request).resume()
    }
}
