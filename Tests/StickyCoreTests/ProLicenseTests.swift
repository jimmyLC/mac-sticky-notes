import CryptoKit
import XCTest
@testable import StickyCore

// Receipts below were signed by payments/src/crypto.mjs (the Worker's own signing code) with a
// throw-away key, so these tests also prove the Worker and the app agree on the format.
private enum Vector {
    static let publicKey = "BL4pPWBKJHhC7digVT2pWqyMc0Iq/HKpcOGZNBV26g0GUCt1jcgUMalRXjo0xK3imeKGg84R78pMN4H6oW/O5Lc="
    static let good = "eyJ2ZXJzaW9uIjoxLCJwcm9kdWN0IjoiaWRlYW1lbW8tcHJvLWxpZmV0aW1lIiwiZW52aXJvbm1lbnQiOiJwcm9kdWN0aW9uIiwibGljZW5zZUlkIjoiSTEyMzQ1Njc4OTAxMjM0NTY3ODkiLCJlbWFpbCI6ImJ1eWVyQGV4YW1wbGUuY29tIiwiaXNzdWVkQXQiOjE3OTMwMDAwMDAsImxpZmV0aW1lIjp0cnVlfQ.nNcuI3YV7WUHvWQYQ5vKRWeOpIV3sJnBCxKTm2PeonYjfJ2Vrdsl4OGe0PW9f9qNwPIr6fM1DYnA-8nqclGm1A"
    static let staging = "eyJ2ZXJzaW9uIjoxLCJwcm9kdWN0IjoiaWRlYW1lbW8tcHJvLWxpZmV0aW1lIiwiZW52aXJvbm1lbnQiOiJzdGFnaW5nIiwibGljZW5zZUlkIjoiSTEyMzQ1Njc4OTAxMjM0NTY3ODkiLCJlbWFpbCI6ImJ1eWVyQGV4YW1wbGUuY29tIiwiaXNzdWVkQXQiOjE3OTMwMDAwMDAsImxpZmV0aW1lIjp0cnVlfQ.ZgbiwYWQ0kUjvw1iVU3N6N6_NgzIBlZ3YfgiL8uCGM-_jgxm4kQuVoiRRBhiUbnEu8J_IAkDQH4fDAGLbVFv8A"
    static let wrongProduct = "eyJ2ZXJzaW9uIjoxLCJwcm9kdWN0IjoibWFjbXA0LXByby1saWZldGltZSIsImVudmlyb25tZW50IjoicHJvZHVjdGlvbiIsImxpY2Vuc2VJZCI6IkkxMjM0NTY3ODkwMTIzNDU2Nzg5IiwiZW1haWwiOiJidXllckBleGFtcGxlLmNvbSIsImlzc3VlZEF0IjoxNzkzMDAwMDAwLCJsaWZldGltZSI6dHJ1ZX0.y5NLO-TjAhzdrEGL6aFtdBhKNz5xTg-FaIQiCHnQ_a9lY9W7My5iOgsXf4HkhWOoXnjDoccRB0Miek-awAb4zw"
    static let email = "buyer@example.com"
    static let issuedAt = 1793000000
    static let now = Date(timeIntervalSince1970: 1793000100)

    static let configuration = ProConfiguration(
        enabled: true, apiBaseURL: "https://pay.example.com", environment: "production", publicKey: publicKey
    )
}

final class LicenseTokenTests: XCTestCase {
    func testWorkerSignedReceiptVerifies() throws {
        let claims = try verifyLicenseToken(Vector.good, email: Vector.email, configuration: Vector.configuration, now: Vector.now)
        XCTAssertEqual(claims.product, "ideamemo-pro-lifetime")
        XCTAssertEqual(claims.licenseId, "I1234567890123456789")
        XCTAssertEqual(claims.issuedAt, Vector.issuedAt)
        XCTAssertTrue(claims.lifetime)
    }

    func testEmailIsComparedAfterNormalizing() throws {
        _ = try verifyLicenseToken(Vector.good, email: "  Buyer@Example.COM ", configuration: Vector.configuration, now: Vector.now)
    }

    func testRejectsTheWrongBuyer() {
        XCTAssertThrowsError(try verifyLicenseToken(Vector.good, email: "other@example.com", configuration: Vector.configuration, now: Vector.now))
    }

    func testRejectsTamperedReceipts() {
        let parts = Vector.good.split(separator: ".").map(String.init)
        var signature = Array(parts[1])
        signature[5] = signature[5] == "A" ? "B" : "A"
        let tamperedSignature = parts[0] + "." + String(signature)
        XCTAssertThrowsError(try verifyLicenseToken(tamperedSignature, email: Vector.email, configuration: Vector.configuration, now: Vector.now))

        var payload = Array(parts[0])
        payload[10] = payload[10] == "A" ? "B" : "A"
        let tamperedPayload = String(payload) + "." + parts[1]
        XCTAssertThrowsError(try verifyLicenseToken(tamperedPayload, email: Vector.email, configuration: Vector.configuration, now: Vector.now))

        XCTAssertThrowsError(try verifyLicenseToken("garbage", email: Vector.email, configuration: Vector.configuration, now: Vector.now))
        XCTAssertThrowsError(try verifyLicenseToken("a.b", email: Vector.email, configuration: Vector.configuration, now: Vector.now))
    }

    func testRejectsAnotherProductEnvironmentOrKey() throws {
        XCTAssertThrowsError(try verifyLicenseToken(Vector.wrongProduct, email: Vector.email, configuration: Vector.configuration, now: Vector.now))
        XCTAssertThrowsError(try verifyLicenseToken(Vector.staging, email: Vector.email, configuration: Vector.configuration, now: Vector.now))

        let otherKey = P256.Signing.PrivateKey().publicKey.x963Representation.base64EncodedString()
        let other = ProConfiguration(enabled: true, apiBaseURL: "https://pay.example.com", environment: "production", publicKey: otherKey)
        XCTAssertThrowsError(try verifyLicenseToken(Vector.good, email: Vector.email, configuration: other, now: Vector.now))
    }

    func testRejectsReceiptsIssuedInTheFuture() {
        let early = Date(timeIntervalSince1970: Double(Vector.issuedAt) - 3600)
        XCTAssertThrowsError(try verifyLicenseToken(Vector.good, email: Vector.email, configuration: Vector.configuration, now: early))
    }

    func testConfigurationMustBeCompleteAndSafe() {
        let key = Vector.publicKey
        func config(enabled: Bool = true, url: String = "https://pay.example.com", env: String = "production", key: String = key) -> ProConfiguration {
            ProConfiguration(enabled: enabled, apiBaseURL: url, environment: env, publicKey: key)
        }
        XCTAssertNotNil(config().baseURL)
        XCTAssertNil(config(enabled: false).baseURL)
        XCTAssertNil(config(url: "http://pay.example.com").baseURL)
        XCTAssertNil(config(url: "https://pay.example.com:8443").baseURL)
        XCTAssertNil(config(url: "https://pay.example.com/path").baseURL)
        XCTAssertNil(config(url: "https://user:pw@pay.example.com").baseURL)
        XCTAssertNil(config(url: "https://pay.invalid").baseURL)
        XCTAssertNil(config(env: "staging").baseURL)
        XCTAssertNil(config(key: "").baseURL)
        XCTAssertNil(config(key: "AAAA").baseURL)
    }

    func testBase64URLRoundTrip() {
        XCTAssertEqual(decodeBase64URL("aGk"), Data("hi".utf8))
        XCTAssertEqual(decodeBase64URL("-_8"), Data([0xFB, 0xFF]))
    }

    func testLanguageFollowsTheSystem() {
        XCTAssertEqual(licenseLanguage(preferred: ["zh-Hant-TW", "en"]), "zh-Hant")
        XCTAssertEqual(licenseLanguage(preferred: ["en-US"]), "en")
        XCTAssertEqual(licenseLanguage(preferred: []), "en")
    }
}

// MARK: Store

private final class MemoryVault: LicenseVault {
    var data: Data?
    var failWrites = false
    func read() throws -> Data? { data }
    func write(_ newValue: Data) throws {
        if failWrites { throw LicenseError.storage }
        data = newValue
    }
    func clear() throws { data = nil }
}

private final class StubServer: URLProtocol {
    /// (method, path) -> (status, JSON object). Requests are recorded for assertions.
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: Any]))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            recorded.httpBody = data
        }
        Self.requests.append(recorded)
        let (status, object) = Self.handler?(recorded) ?? (500, ["error": "no_handler"])
        let body = try! JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ProLicenseStoreTests: XCTestCase {
    private let orderId = "I1234567890123456789"
    private var vault = MemoryVault()

    override func setUp() {
        vault = MemoryVault()
        StubServer.requests = []
        StubServer.handler = nil
    }

    private func makeStore(configuration: ProConfiguration? = Vector.configuration) -> ProLicenseStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        return ProLicenseStore(
            configuration: configuration, vault: vault, session: URLSession(configuration: config),
            deviceID: "device-aaaaaaaaaaaaaaaaaaaaaa", now: { Vector.now }
        )
    }

    private func save(_ record: LicenseRecord) { vault.data = try! JSONEncoder().encode(record) }
    private func savedRecord() -> LicenseRecord? { vault.data.flatMap { try? JSONDecoder().decode(LicenseRecord.self, from: $0) } }

    private func paid(email: String = Vector.email, token: String = Vector.good) -> [String: Any] {
        ["status": "paid", "email": email, "serial": "IDM-AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD-EEEEEEEE", "licenseToken": token]
    }

    private func serve(config checkoutEnabled: Bool = true, order: @escaping (URLRequest) -> (Int, [String: Any])? = { _ in nil },
                       status: @escaping (URLRequest) -> [String: Any] = { _ in ["status": "pending"] },
                       activate: @escaping (URLRequest) -> (Int, [String: Any]) = { _ in (200, [:]) }) {
        StubServer.handler = { request in
            let path = request.url!.path
            if path == "/v1/config" {
                return (200, ["environment": "production", "amount": 120, "currency": "TWD", "checkoutEnabled": checkoutEnabled, "methods": ["ApplePay", "Credit"]])
            }
            if path == "/v1/orders", request.httpMethod == "POST" {
                if let custom = order(request) { return custom }
                return (201, ["orderId": self.orderId, "amount": 120, "currency": "TWD", "environment": "production",
                              "checkoutURL": "https://pay.example.com/checkout/\(self.orderId)?token=abc"])
            }
            if path.hasPrefix("/v1/orders/") { return (200, status(request)) }
            if path == "/v1/licenses/activate" { return activate(request) }
            return (404, ["error": "not_found"])
        }
    }

    // MARK: Entitlement from storage

    func testStartsFreeWithNothingSaved() {
        XCTAssertFalse(makeStore().isPro)
    }

    func testSavedVerifiedReceiptUnlocksProImmediately() {
        var record = LicenseRecord(); record.email = Vector.email; record.serial = "IDM-X"; record.licenseToken = Vector.good
        save(record)
        let store = makeStore()
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.email, Vector.email)
    }

    func testSavedReceiptThatDoesNotVerifyStaysFree() {
        var record = LicenseRecord(); record.email = "someone-else@example.com"; record.serial = "IDM-X"; record.licenseToken = Vector.good
        save(record)
        XCTAssertFalse(makeStore().isPro)
    }

    func testPurchasingIsOffWhenTheAppIsNotConfigured() async {
        let store = makeStore(configuration: ProConfiguration(enabled: false, apiBaseURL: "", environment: "production", publicKey: ""))
        XCTAssertFalse(store.isConfigured)
        let url = await store.purchase(email: Vector.email, method: "Credit")
        XCTAssertNil(url)
        XCTAssertTrue(StubServer.requests.isEmpty)
        XCTAssertFalse(store.isPro)
    }

    // MARK: Buying

    func testBuyingFlowUnlocksProAfterPayment() async throws {
        serve()
        let store = makeStore()
        await store.loadOptions()
        XCTAssertEqual(store.priceText, "NT$ 120")
        XCTAssertTrue(store.canPurchase)
        XCTAssertTrue(store.applePayAvailable)

        let url = await store.purchase(email: " Buyer@Example.com ", method: "Credit")
        XCTAssertEqual(url?.path, "/checkout/" + orderId)
        XCTAssertTrue(store.hasPendingPurchase)
        let create = StubServer.requests.last { $0.url?.path == "/v1/orders" }
        let sent = try JSONSerialization.jsonObject(with: create?.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(sent?["email"], Vector.email)
        XCTAssertEqual(sent?["method"], "Credit")
        XCTAssertNotNil(sent?["accessToken"])
        XCTAssertEqual(create?.value(forHTTPHeaderField: "X-Device-Id"), "device-aaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertNotNil(savedRecord()?.pending, "the pending order is saved so a crash cannot lose a payment")

        var paidNow = false
        serve(status: { _ in paidNow ? self.paid() : ["status": "pending"] })
        let early = await store.checkPayment()
        XCTAssertFalse(early)
        XCTAssertFalse(store.isPro)

        paidNow = true
        let done = await store.checkPayment()
        XCTAssertTrue(done)
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(store.showPurchaseCelebration)
        XCTAssertNil(savedRecord()?.pending)
        XCTAssertEqual(savedRecord()?.licenseToken, Vector.good)
    }

    func testRejectsAnInvalidEmailBeforeContactingTheServer() async {
        serve()
        let store = makeStore()
        await store.loadOptions()
        StubServer.requests = []
        let url = await store.purchase(email: "not an email", method: "Credit")
        XCTAssertNil(url)
        XCTAssertNotNil(store.message)
        XCTAssertTrue(StubServer.requests.isEmpty)
    }

    func testRefusesACheckoutLinkOnAnotherHost() async {
        serve(order: { _ in (201, ["orderId": self.orderId, "amount": 120, "currency": "TWD", "environment": "production",
                                   "checkoutURL": "https://evil.example.net/checkout/\(self.orderId)"]) })
        let store = makeStore()
        await store.loadOptions()
        let url = await store.purchase(email: Vector.email, method: "Credit")
        XCTAssertNil(url)
    }

    func testRefusesAnOrderWhosePriceDiffersFromTheAdvertisedOne() async {
        serve(order: { _ in (201, ["orderId": self.orderId, "amount": 1, "currency": "TWD", "environment": "production",
                                   "checkoutURL": "https://pay.example.com/checkout/\(self.orderId)?token=abc"]) })
        let store = makeStore()
        await store.loadOptions()
        let url = await store.purchase(email: Vector.email, method: "Credit")
        XCTAssertNil(url)
    }

    func testReceiptForAnotherEmailIsNotAccepted() async {
        serve(status: { _ in self.paid(email: "someone-else@example.com") })
        let store = makeStore()
        await store.loadOptions()
        _ = await store.purchase(email: Vector.email, method: "Credit")
        let done = await store.checkPayment()
        XCTAssertFalse(done)
        XCTAssertFalse(store.isPro)
    }

    func testReceiptThatFailsVerificationIsNotAccepted() async {
        serve(status: { _ in self.paid(token: Vector.staging) })
        let store = makeStore()
        await store.loadOptions()
        _ = await store.purchase(email: Vector.email, method: "Credit")
        let done = await store.checkPayment()
        XCTAssertFalse(done)
        XCTAssertFalse(store.isPro)
    }

    func testStorageFailureDoesNotUnlockPro() async {
        serve(status: { _ in self.paid() })
        let store = makeStore()
        await store.loadOptions()
        _ = await store.purchase(email: Vector.email, method: "Credit")
        vault.failWrites = true
        let done = await store.checkPayment()
        XCTAssertFalse(done)
        XCTAssertFalse(store.isPro)
    }

    // MARK: Restoring and devices

    func testRestoreActivatesASerialOnThisMac() async throws {
        serve(activate: { _ in (200, self.paid()) })
        let store = makeStore()
        await store.restore(email: "Buyer@example.com", serial: "IDM-AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD-EEEEEEEE")
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.serial, "IDM-AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD-EEEEEEEE")
        let request = StubServer.requests.last { $0.url?.path == "/v1/licenses/activate" }
        let sent = try JSONSerialization.jsonObject(with: request?.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(sent?["takeover"], "true", "pressing Activate moves the serial to this Mac")
        XCTAssertEqual(sent?["deviceId"], "device-aaaaaaaaaaaaaaaaaaaaaa")
    }

    func testBackgroundCheckNeverTakesTheSerialFromAnotherMac() async throws {
        serve(activate: { _ in (409, ["error": "device_replaced"]) })
        var record = LicenseRecord(); record.email = Vector.email; record.serial = "IDM-X"; record.licenseToken = Vector.good
        save(record)
        let store = makeStore()
        XCTAssertTrue(store.isPro)

        await store.resume()
        let request = StubServer.requests.last { $0.url?.path == "/v1/licenses/activate" }
        let sent = try JSONSerialization.jsonObject(with: request?.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(sent?["takeover"], "false")
        XCTAssertFalse(store.isPro, "another Mac holds the serial now")
        XCTAssertEqual(savedRecord()?.licenseToken, "")
        XCTAssertNotNil(store.message)
    }

    func testRevokedLicenseReturnsToFree() async {
        serve(activate: { _ in (409, ["error": "license_revoked"]) })
        var record = LicenseRecord(); record.email = Vector.email; record.serial = "IDM-X"; record.licenseToken = Vector.good
        save(record)
        let store = makeStore()
        await store.resume()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(savedRecord()?.licenseToken, "")
    }

    func testBeingOfflineKeepsAVerifiedLifetimeReceipt() async {
        StubServer.handler = { _ in (503, ["error": "service_unavailable"]) }
        var record = LicenseRecord(); record.email = Vector.email; record.serial = "IDM-X"; record.licenseToken = Vector.good
        save(record)
        let store = makeStore()
        await store.resume()
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(savedRecord()?.licenseToken, Vector.good)
    }

    func testWrongSerialIsReportedWithoutUnlocking() async {
        serve(activate: { _ in (403, ["error": "invalid_license"]) })
        let store = makeStore()
        await store.restore(email: Vector.email, serial: "IDM-WRONG")
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.message, LicenseError.invalid.errorDescription)
    }

    func testDeviceChangeLimitIsExplained() async {
        serve(activate: { _ in (429, ["error": "device_change_limited"]) })
        let store = makeStore()
        await store.restore(email: Vector.email, serial: "IDM-X")
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.message, LicenseError.request("device_change_limited").errorDescription)
    }
}
