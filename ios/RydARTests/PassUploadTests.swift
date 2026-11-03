import CryptoKit
import DeviceCheck
import XCTest
@testable import RydAR

final class PassUploadTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-\(UUID().uuidString).json")
        StubProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        StubProtocol.reset()
    }

    func testStoreKeepsBatchesUntilRemovedAndDropsOldOrOverTriedOnes() {
        let store = PendingPassStore(url: storeURL)
        let now = Date()
        store.append([pass("007-2-3")], now: now.addingTimeInterval(-15 * 24 * 3600))
        store.append([pass("143-9-1")], now: now)
        let kept = store.batches(now: now)
        XCTAssertEqual(kept.map { $0.passes[0].curve_id }, ["143-9-1"], "a batch older than 14 days is dropped")
        for _ in 0..<PendingPassStore.maxAttempts { store.recordFailure(id: kept[0].id) }
        XCTAssertTrue(store.batches(now: now).isEmpty, "a batch is dropped after its last attempt")
        store.append([pass("119-4-8")], now: now)
        store.removeAll()
        XCTAssertTrue(store.batches(now: now).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testStoreCapsTheNumberOfWaitingBatches() {
        let store = PendingPassStore(url: storeURL)
        for index in 0..<(PendingPassStore.maxBatches + 5) {
            store.append([pass("007-2-\(index + 1)")])
        }
        let kept = store.batches()
        XCTAssertEqual(kept.count, PendingPassStore.maxBatches)
        XCTAssertEqual(kept.first?.passes[0].curve_id, "007-2-6", "the oldest are dropped first")
    }

    func testOnlyAnHTTPSEndpointIsUsed() {
        XCTAssertEqual(PassUpload.secureEndpoint("https://rydar.org/api/pass")?.absoluteString, "https://rydar.org/api/pass")
        XCTAssertNil(PassUpload.secureEndpoint("http://rydar.org/api/pass"))
        XCTAssertNil(PassUpload.secureEndpoint("ftp://rydar.org/api/pass"))
        XCTAssertNil(PassUpload.secureEndpoint("https://user:secret@rydar.org/api/pass"))
        XCTAssertNil(PassUpload.secureEndpoint("rydar.org/api/pass"))
        XCTAssertNil(PassUpload.secureEndpoint(""))
    }

    func testUploadSessionKeepsNothing() {
        let configuration = PassUpload.privateSession.configuration
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
    }

    func testStatusCodesDecideWhetherToRetry() {
        XCTAssertEqual(PassUpload.outcome(status: 200), .delivered)
        XCTAssertEqual(PassUpload.outcome(status: 400), .refused)
        XCTAssertEqual(PassUpload.outcome(status: 413), .refused)
        XCTAssertEqual(PassUpload.outcome(status: 403), .unknownKey)
        XCTAssertEqual(PassUpload.outcome(status: 401), .retryLater)
        XCTAssertEqual(PassUpload.outcome(status: 409), .retryLater)
        XCTAssertEqual(PassUpload.outcome(status: 503), .retryLater)
        XCTAssertEqual(PassUpload.outcome(status: nil), .retryLater)
    }

    func testTheFirstTripRegistersAKeyThenSignsTheExactPayload() async throws {
        let signer = FakeSigner()
        let keys = MemoryKeys()
        let upload = makeUpload(signer: signer, keys: keys)
        StubProtocol.respond = Self.server()
        upload.store.append([pass("007-2-3"), pass("143-9-1")])
        await upload.flush(generation: 0)

        XCTAssertTrue(upload.store.batches().isEmpty, "a delivered batch leaves the phone")
        XCTAssertEqual(signer.attested, ["key-1"], "Apple attests the key once")
        XCTAssertEqual(keys.load(), SigningKey(keyID: "key-1", registered: true))
        XCTAssertEqual(StubProtocol.posts.map(\.path), ["/api/attest", "/api/pass"])

        let registration = try json(StubProtocol.posts[0].body)
        XCTAssertEqual(registration["key_id"], "key-1")
        XCTAssertEqual(signer.attestHashes, [Data(SHA256.hash(data: Data("rydar-attest-v1\n\(Self.challenge)".utf8)))])

        let batch = try json(StubProtocol.posts[1].body)
        XCTAssertEqual(batch["key_id"], "key-1")
        XCTAssertEqual(batch["challenge"], Self.challenge)
        XCTAssertEqual(batch["assertion"], Data("assertion-1".utf8).base64EncodedString())
        let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(batch["payload"])))
        let decoded = try JSONDecoder().decode(PassWire.Payload.self, from: payload)
        XCTAssertEqual(decoded.passes.map(\.curve_id), ["007-2-3", "143-9-1"])
        var signed = Data("rydar-pass-v1\n\(Self.challenge)\n".utf8)
        signed.append(payload)
        XCTAssertEqual(signer.assertHashes, [Data(SHA256.hash(data: signed))])
    }

    func testLaterTripsReuseTheKeyWithoutCallingApple() async {
        let signer = FakeSigner()
        let upload = makeUpload(signer: signer, keys: MemoryKeys())
        StubProtocol.respond = Self.server()
        upload.store.append([pass("007-2-3")])
        upload.store.append([pass("143-9-1")])
        await upload.flush(generation: 0)
        upload.store.append([pass("119-4-8")])
        await upload.flush(generation: 0)
        XCTAssertEqual(signer.generated, 1)
        XCTAssertEqual(signer.attested.count, 1)
        XCTAssertEqual(signer.assertHashes.count, 3)
        XCTAssertEqual(StubProtocol.posts.map(\.path), ["/api/attest", "/api/pass", "/api/pass", "/api/pass"])
    }

    func testDiscardingForgetsTheKeySoTheNextTripCannotBeLinked() async {
        let signer = FakeSigner()
        let keys = MemoryKeys()
        let upload = makeUpload(signer: signer, keys: keys)
        StubProtocol.respond = Self.server()
        upload.store.append([pass("007-2-3")])
        await upload.flush(generation: 0)
        upload.discardPending()
        XCTAssertNil(keys.load())
        upload.store.append([pass("143-9-1")])
        await upload.flush(generation: 1)
        XCTAssertEqual(signer.attested, ["key-1", "key-2"])
    }

    func testAKeyTheServerForgotIsReplacedAndTheBatchStillGoes() async {
        let signer = FakeSigner()
        let keys = MemoryKeys()
        keys.save(SigningKey(keyID: "old-key", registered: true))
        let upload = makeUpload(signer: signer, keys: keys)
        var forgot = true
        StubProtocol.respond = { request in
            if request.url?.path == "/api/pass", forgot {
                forgot = false
                return (403, Data())
            }
            return Self.server()(request)
        }
        upload.store.append([pass("007-2-3")])
        await upload.flush(generation: 0)
        XCTAssertTrue(upload.store.batches().isEmpty)
        XCTAssertEqual(keys.load(), SigningKey(keyID: "key-1", registered: true))
    }

    func testAnInvalidKeyIsDroppedAndTheBatchWaits() async {
        let signer = FakeSigner()
        signer.assertionError = DCError(.invalidKey)
        let keys = MemoryKeys()
        keys.save(SigningKey(keyID: "restored-key", registered: true))
        let upload = makeUpload(signer: signer, keys: keys)
        StubProtocol.respond = Self.server()
        upload.store.append([pass("007-2-3")])
        await upload.flush(generation: 0)
        XCTAssertNil(keys.load(), "a key iOS calls invalid is never reused")
        XCTAssertEqual(upload.store.batches().first?.attempts, 1)
    }

    func testABusyAttestationServiceKeepsTheKeyForLater() async {
        let signer = FakeSigner()
        signer.attestError = DCError(.serverUnavailable)
        let keys = MemoryKeys()
        let upload = makeUpload(signer: signer, keys: keys)
        StubProtocol.respond = Self.server()
        upload.store.append([pass("007-2-3")])
        await upload.flush(generation: 0)
        XCTAssertEqual(keys.load(), SigningKey(keyID: "key-1", registered: false))
        XCTAssertEqual(upload.store.batches().count, 1)
        signer.attestError = nil
        await upload.flush(generation: 0)
        XCTAssertEqual(signer.generated, 1, "the same key is attested once Apple answers")
        XCTAssertTrue(upload.store.batches().isEmpty)
    }

    func testServerTroubleKeepsTheBatchAndARefusalDropsIt() async {
        let upload = makeUpload(signer: FakeSigner(), keys: MemoryKeys())
        StubProtocol.respond = { request in
            request.url?.path == "/api/pass" ? (503, Data()) : Self.server()(request)
        }
        upload.store.append([pass("007-2-3")])
        await upload.flush(generation: 0)
        XCTAssertEqual(upload.store.batches().first?.attempts, 1)

        StubProtocol.respond = { request in
            request.url?.path == "/api/pass" ? (400, Data()) : Self.server()(request)
        }
        await upload.flush(generation: 0)
        XCTAssertTrue(upload.store.batches().isEmpty)
    }

    func testNoChallengeMeansNothingIsSigned() async {
        let signer = FakeSigner()
        let upload = makeUpload(signer: signer, keys: MemoryKeys())
        StubProtocol.respond = { _ in (503, Data()) }
        upload.store.append([pass("007-2-3")])
        await upload.flush(generation: 0)
        XCTAssertTrue(signer.attested.isEmpty)
        XCTAssertTrue(signer.assertHashes.isEmpty)
        XCTAssertEqual(upload.store.batches().count, 1)
    }

    func testAnUnsupportedDeviceSendsNothing() {
        let signer = FakeSigner()
        signer.supported = false
        let upload = makeUpload(signer: signer, keys: MemoryKeys())
        XCTAssertFalse(upload.isConfigured)
        upload.submit([pass("007-2-3")])
        XCTAssertTrue(upload.store.batches().isEmpty)
    }

    func testDiscardStopsAFlushThatHasNotStarted() async {
        let signer = FakeSigner()
        let upload = makeUpload(signer: signer, keys: MemoryKeys())
        upload.store.append([pass("007-2-3")])
        upload.discardPending()
        await upload.flush(generation: 0)
        XCTAssertTrue(signer.assertHashes.isEmpty)
        XCTAssertTrue(upload.store.batches().isEmpty)
    }

    private static let challenge = "v1.1700000000.abcdefghijklmnop.signature"

    private static func server() -> (URLRequest) -> (Int, Data) {
        { request in
            switch request.url?.path {
            case "/api/challenge": return (200, Data(#"{"challenge":"\#(challenge)"}"#.utf8))
            case "/api/attest": return (200, Data(#"{"registered":true}"#.utf8))
            default: return (200, Data(#"{"stored":1}"#.utf8))
            }
        }
    }

    private func json(_ data: Data) throws -> [String: String] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    private func makeUpload(signer: FakeSigner, keys: MemoryKeys) -> PassUpload {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return PassUpload(
            endpoint: URL(string: "https://rydar.test/api/pass"),
            challengeEndpoint: URL(string: "https://rydar.test/api/challenge"),
            attestEndpoint: URL(string: "https://rydar.test/api/attest"),
            session: URLSession(configuration: configuration),
            store: PendingPassStore(url: storeURL),
            signer: signer,
            keys: keys
        )
    }

    private func pass(_ id: String) -> AnonymousPassBody {
        AnonymousPassBody(curve_id: id, direction: "N", speed_band_mph: 31.5, hour_bucket: 9, app_version: "1.0.0")
    }
}

private final class FakeSigner: PassSigning {
    var supported = true
    var generated = 0
    var attested: [String] = []
    var attestHashes: [Data] = []
    var assertHashes: [Data] = []
    var attestError: Error?
    var assertionError: Error?
    var isSupported: Bool { supported }

    func generateKey() async throws -> String {
        generated += 1
        return "key-\(generated)"
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        if let attestError { throw attestError }
        attested.append(keyID)
        attestHashes.append(clientDataHash)
        return Data("attestation-\(attested.count)".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        if let assertionError { throw assertionError }
        assertHashes.append(clientDataHash)
        return Data("assertion-\(assertHashes.count)".utf8)
    }
}

private final class MemoryKeys: SigningKeyStoring {
    private var key: SigningKey?
    func load() -> SigningKey? { key }
    func save(_ key: SigningKey) { self.key = key }
    func clear() { key = nil }
}

private final class StubProtocol: URLProtocol {
    static var respond: (URLRequest) -> (Int, Data) = { _ in (500, Data()) }
    static var posts: [(path: String, body: Data)] = []

    static func reset() {
        respond = { _ in (500, Data()) }
        posts = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.httpMethod == "POST", let body = request.httpBody ?? request.httpBodyStream.map(Self.read) {
            Self.posts.append((request.url?.path ?? "", body))
        }
        let (status, data) = Self.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
