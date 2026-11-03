import CryptoKit
import DeviceCheck
import Foundation
import Security

/// The body in Contracts/pass.json. Timing memory, traces, and frames stay off this payload.
struct AnonymousPassBody: Equatable, Codable {
    var curve_id: String
    var direction: String
    /// The approach speed in mph, as recorded. Not rounded to a band.
    var speed_band_mph: Double
    var hour_bucket: Int
    var app_version: String
}

enum AnonymousPass {
    /// Keeps the recorded speed. Only a non-number or a reading outside 0–150 mph is brought into range.
    static func uploadSpeed(_ mph: Double) -> Double {
        guard mph.isFinite else { return 0 }
        return min(150, max(0, mph))
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
            speed_band_mph: uploadSpeed(pass.effectiveSpeedMPH),
            hour_bucket: pass.hourBucket,
            app_version: version
        )
    }

    /// County code is an Arkansas FIPS: odd numbers from 001 through 149.
    static func isCurveID(_ id: String) -> Bool {
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 3, parts[0].allSatisfy(isDigit),
              let county = Int(parts[0]), county >= 1, county <= 149, county % 2 == 1 else { return false }
        return parts[1].count >= 1 && parts[1].count <= 7 && parts[1].allSatisfy(isDigit)
            && parts[2].count >= 1 && parts[2].count <= 7 && parts[2].allSatisfy(isDigit)
    }

    /// 0–9 only. `Character.isNumber` would also accept digits from other scripts, which the server rejects.
    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// The server's cap. A longer trip goes up as several batches, each signed by its own key.
    static let maxPassesPerBatch = 2_000
}

protocol PassSending: AnyObject {
    /// One finished trip's passes, already in random order.
    func submit(_ batch: [AnonymousPassBody])
    /// Sends batches still waiting from earlier trips.
    func retryPending()
    /// Deletes every batch still waiting on this iPhone and the signing key, so later trips
    /// cannot be linked to earlier ones.
    func discardPending()
}

extension PassSending {
    func retryPending() {}
    func discardPending() {}
}

// MARK: - Waiting batches

/// One trip's passes that have not reached the server yet.
struct PendingBatch: Codable, Equatable {
    var id: String
    var createdAt: Date
    var attempts: Int
    var passes: [AnonymousPassBody]
}

/// Batches wait here, on this iPhone only, until they are delivered, refused, too old, or tried too often.
/// The file is excluded from backups and is deleted with Reset all data or when sharing is turned off.
final class PendingPassStore {
    static let maxBatches = 20
    static let maxAttempts = 5
    static let maxAge: TimeInterval = 14 * 24 * 60 * 60

    private let url: URL?
    private let lock = NSLock()

    init(url: URL?) {
        self.url = url
    }

    static func bundled() -> PendingPassStore {
        PendingPassStore(url: try? BundledCurves.pendingUploadsURL())
    }

    /// Oldest first, with anything expired or over its attempts already dropped.
    func batches(now: Date = Date()) -> [PendingBatch] {
        lock.lock()
        defer { lock.unlock() }
        let all = readLocked()
        let kept = Self.pruned(all, now: now)
        if kept != all { writeLocked(kept) }
        return kept
    }

    func append(_ passes: [AnonymousPassBody], now: Date = Date()) {
        guard !passes.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var all = Self.pruned(readLocked(), now: now)
        all.append(PendingBatch(id: UUID().uuidString, createdAt: now, attempts: 0, passes: passes))
        if all.count > Self.maxBatches { all.removeFirst(all.count - Self.maxBatches) }
        writeLocked(all)
    }

    func remove(id: String) {
        lock.lock()
        defer { lock.unlock() }
        writeLocked(readLocked().filter { $0.id != id })
    }

    func recordFailure(id: String) {
        lock.lock()
        defer { lock.unlock() }
        var all = readLocked()
        if let index = all.firstIndex(where: { $0.id == id }) { all[index].attempts += 1 }
        writeLocked(all.filter { $0.attempts < Self.maxAttempts })
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func pruned(_ batches: [PendingBatch], now: Date) -> [PendingBatch] {
        batches.filter { batch in
            batch.attempts < maxAttempts
                && now.timeIntervalSince(batch.createdAt) <= maxAge
                && !batch.passes.isEmpty
        }
    }

    private func readLocked() -> [PendingBatch] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // An unreadable file is dropped rather than retried forever.
        return (try? decoder.decode([PendingBatch].self, from: data)) ?? []
    }

    private func writeLocked(_ batches: [PendingBatch]) {
        guard var url else { return }
        if batches.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(batches) else { return }
        do {
            // Readable while the phone is locked after first unlock, so a trip that ends on the
            // Lock Screen can still queue its batch.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            debugLog("Saving waiting passes failed: \(error)")
        }
    }
}

// MARK: - App Attest

/// Proves a batch comes from the genuine RydAR app on a real iPhone.
/// One Secure Enclave key per install is attested by Apple once; each trip is then signed on the
/// phone with an assertion, which needs no call to Apple. A new key is made only after Reset all
/// data, after sharing is turned off, or when iOS invalidates the key.
protocol PassSigning {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    /// Calls Apple's attestation service. Rare: once per key.
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    /// Signed on the phone. No network.
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

struct AppAttestSigner: PassSigning {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }

    /// The key is gone or unusable (a restore to another phone, a reinstall). Make a new one.
    static func isInvalidKey(_ error: Error) -> Bool {
        (error as? DCError)?.code == .invalidKey || (error as? DCError)?.code == .invalidInput
    }
}

/// This install's signing key id, and whether the server has accepted its attestation.
struct SigningKey: Codable, Equatable {
    var keyID: String
    var registered: Bool
}

protocol SigningKeyStoring: AnyObject {
    func load() -> SigningKey?
    func save(_ key: SigningKey)
    func clear()
}

/// Keychain, this device only: never in a backup, never moved to another phone.
final class KeychainSigningKeyStore: SigningKeyStoring {
    private let service = "org.rydar.app.appattest"
    private let account = "signing-key"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> SigningKey? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SigningKey.self, from: data)
    }

    func save(_ key: SigningKey) {
        guard let data = try? JSONEncoder().encode(key) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { debugLog("Saving the signing key failed: \(status)") }
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// The signed requests. Server and app must agree on these bytes exactly; see Contracts/pass.json.
enum PassWire {
    static let passPrefix = "rydar-pass-v1\n"
    static let attestPrefix = "rydar-attest-v1\n"

    struct Payload: Codable, Equatable {
        var passes: [AnonymousPassBody]
    }

    struct Registration: Encodable {
        var key_id: String
        var attestation: String
        var challenge: String
    }

    struct SignedBatch: Encodable {
        var key_id: String
        var assertion: String
        var challenge: String
        var payload: String
    }

    static func payload(_ passes: [AnonymousPassBody]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Payload(passes: passes))
    }

    /// The prefix, the server's challenge, a newline, then the exact payload bytes.
    /// The assertion covers its hash, so neither the challenge nor a single pass can be changed.
    static func clientData(challenge: String, payload: Data) -> Data {
        var data = Data((passPrefix + challenge + "\n").utf8)
        data.append(payload)
        return data
    }

    static func clientDataHash(challenge: String, payload: Data) -> Data {
        Data(SHA256.hash(data: clientData(challenge: challenge, payload: payload)))
    }

    /// What a key's one-time attestation covers.
    static func registrationHash(challenge: String) -> Data {
        Data(SHA256.hash(data: Data((attestPrefix + challenge).utf8)))
    }

    /// A challenge is short, printable ASCII. Anything else from the network is ignored.
    static func isPlausibleChallenge(_ value: String) -> Bool {
        (16...256).contains(value.utf8.count)
            && value.utf8.allSatisfy { $0 > 0x20 && $0 < 0x7F }
    }
}

// MARK: - Upload

/// Queues each finished trip on this iPhone, then sends it signed with App Attest.
/// Nothing unsigned is ever sent. A missing address or an unsupported device sends nothing.
/// The drive never waits on the network.
final class PassUpload: PassSending {
    enum Outcome: Equatable {
        /// Stored by the server. Remove it here.
        case delivered
        /// The server will never accept it. Remove it here.
        case refused
        /// Network, Apple, or server trouble. Keep it for the next try.
        case retryLater
        /// The server does not know this key. Register a new one, then try again.
        case unknownKey
    }

    var endpoint: URL?
    var challengeEndpoint: URL?
    var attestEndpoint: URL?
    var session: URLSession
    let store: PendingPassStore
    let signer: PassSigning
    let keys: SigningKeyStoring

    private let stateLock = NSLock()
    private var flushing = false
    /// Raised by discardPending so a send already in flight does not deliver a discarded batch
    /// or keep a key that was meant to be forgotten.
    private var generation = 0

    init(
        endpoint: URL? = PassUpload.bundledEndpoint,
        challengeEndpoint: URL? = PassUpload.bundledChallengeEndpoint,
        attestEndpoint: URL? = PassUpload.bundledAttestEndpoint,
        session: URLSession = PassUpload.privateSession,
        store: PendingPassStore = .bundled(),
        signer: PassSigning = AppAttestSigner(),
        keys: SigningKeyStoring = KeychainSigningKeyStore()
    ) {
        self.endpoint = endpoint
        self.challengeEndpoint = challengeEndpoint
        self.attestEndpoint = attestEndpoint
        self.session = session
        self.store = store
        self.signer = signer
        self.keys = keys
    }

    /// No cookies, no cache, no credentials, nothing written to disk. Redirects are refused,
    /// so a pass only ever reaches the bundled host.
    static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    static var bundledEndpoint: URL? { configured("RydARPassEndpoint") }
    static var bundledChallengeEndpoint: URL? { configured("RydARChallengeEndpoint") }
    static var bundledAttestEndpoint: URL? { configured("RydARAttestEndpoint") }

    private static func configured(_ key: String) -> URL? {
        #if targetEnvironment(simulator)
        // Simulator replays and test runs must never post synthetic passes to the live site.
        return nil
        #else
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return secureEndpoint(trimmed)
        #endif
    }

    /// Only an https address with a host. Anything else turns uploads off rather than sending in the clear.
    static func secureEndpoint(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// Empty when the bundle has no version. `AnonymousPass.body` then returns nil and nothing is sent.
    static var appVersion: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isConfigured: Bool {
        endpoint != nil && challengeEndpoint != nil && attestEndpoint != nil && signer.isSupported
    }

    func submit(_ batch: [AnonymousPassBody]) {
        guard isConfigured, !batch.isEmpty else { return }
        var start = 0
        while start < batch.count {
            let end = min(batch.count, start + AnonymousPass.maxPassesPerBatch)
            store.append(Array(batch[start..<end]))
            start = end
        }
        retryPending()
    }

    func retryPending() {
        guard isConfigured else { return }
        stateLock.lock()
        guard !flushing else {
            stateLock.unlock()
            return
        }
        flushing = true
        let started = generation
        stateLock.unlock()
        Task.detached(priority: .utility) { [self] in
            await self.flush(generation: started)
            self.stateLock.lock()
            self.flushing = false
            self.stateLock.unlock()
        }
    }

    func discardPending() {
        stateLock.lock()
        generation += 1
        stateLock.unlock()
        store.removeAll()
        keys.clear()
    }

    private func stillCurrent(_ started: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == started
    }

    /// Oldest first. Stops at the first batch that has to wait, so a dead network does not
    /// use up every batch's attempts at once.
    func flush(generation started: Int) async {
        for batch in store.batches() {
            guard stillCurrent(started) else { return }
            var outcome = await send(batch, generation: started)
            if outcome == .unknownKey {
                // The server dropped the key (unused for months) or never had it. One new key, one more try.
                keys.clear()
                outcome = await send(batch, generation: started)
                if outcome == .unknownKey { outcome = .retryLater }
            }
            guard stillCurrent(started) else { return }
            switch outcome {
            case .delivered, .refused:
                store.remove(id: batch.id)
            case .retryLater, .unknownKey:
                store.recordFailure(id: batch.id)
                return
            }
        }
    }

    func send(_ batch: PendingBatch, generation started: Int) async -> Outcome {
        guard let endpoint, let challengeEndpoint else { return .retryLater }
        guard let keyID = await registeredKey(generation: started) else { return .retryLater }
        guard let challenge = await fetchChallenge(from: challengeEndpoint) else { return .retryLater }
        guard let payload = try? PassWire.payload(batch.passes) else { return .refused }
        let hash = PassWire.clientDataHash(challenge: challenge, payload: payload)
        let assertion: Data
        do {
            assertion = try await signer.generateAssertion(keyID, clientDataHash: hash)
        } catch {
            debugLog("App Attest assertion failed: \(error)")
            if AppAttestSigner.isInvalidKey(error) { keys.clear() }
            return .retryLater
        }
        let body = PassWire.SignedBatch(
            key_id: keyID,
            assertion: assertion.base64EncodedString(),
            challenge: challenge,
            payload: payload.base64EncodedString()
        )
        guard let data = try? JSONEncoder().encode(body) else { return .refused }
        return Self.outcome(status: await post(data, to: endpoint))
    }

    /// The key this install signs with, registered with the server. Makes and registers one if
    /// needed: the only time Apple's attestation service is called.
    func registeredKey(generation started: Int) async -> String? {
        if let key = keys.load(), key.registered { return key.keyID }
        guard let attestEndpoint, let challengeEndpoint else { return nil }
        let keyID: String
        if let pending = keys.load() {
            keyID = pending.keyID
        } else {
            guard let fresh = try? await signer.generateKey(), stillCurrent(started) else { return nil }
            keyID = fresh
            keys.save(SigningKey(keyID: keyID, registered: false))
        }
        guard let challenge = await fetchChallenge(from: challengeEndpoint) else { return nil }
        let attestation: Data
        do {
            attestation = try await signer.attestKey(keyID, clientDataHash: PassWire.registrationHash(challenge: challenge))
        } catch {
            debugLog("App Attest attestation failed: \(error)")
            // Apple busy: keep the key and try later. Anything else: this key is spent, make a new one next time.
            if (error as? DCError)?.code != .serverUnavailable { keys.clear() }
            return nil
        }
        let body = PassWire.Registration(
            key_id: keyID,
            attestation: attestation.base64EncodedString(),
            challenge: challenge
        )
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        let status = await post(data, to: attestEndpoint)
        guard stillCurrent(started) else {
            keys.clear()
            return nil
        }
        switch status {
        case .some(200..<300):
            keys.save(SigningKey(keyID: keyID, registered: true))
            return keyID
        case .some(400), .some(401):
            // The server refused this attestation. A key can be attested only once, so start over.
            keys.clear()
            return nil
        default:
            return nil
        }
    }

    /// 2xx is stored. 400, 413, and 422 mean the batch itself is wrong and will never be accepted.
    /// 403 means the server does not know the key. Everything else is tried again later.
    static func outcome(status: Int?) -> Outcome {
        guard let status else { return .retryLater }
        if (200..<300).contains(status) { return .delivered }
        if status == 400 || status == 413 || status == 422 { return .refused }
        if status == 403 { return .unknownKey }
        return .retryLater
    }

    private func post(_ body: Data, to url: URL) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpBody = body
        guard let reply = try? await session.data(for: request) else { return nil }
        return (reply.1 as? HTTPURLResponse)?.statusCode
    }

    private func fetchChallenge(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        struct Reply: Decodable { var challenge: String }
        guard let reply = try? await session.data(for: request),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200,
              reply.0.count <= 4_096,
              let decoded = try? JSONDecoder().decode(Reply.self, from: reply.0),
              PassWire.isPlausibleChallenge(decoded.challenge) else { return nil }
        return decoded.challenge
    }
}

/// Refuses every redirect. The pass endpoint answers directly or not at all.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
