import Combine
import CryptoKit
import Foundation
import IOKit
import Security

// Pro licensing, modelled on MacMP4: a payment Worker sells a lifetime serial, signs a receipt
// (P-256) for the buyer's email, and allows one active Mac per serial. The app only trusts
// receipts that verify against the public key it ships with, so payment secrets never live here.

private func tr(_ key: String) -> String { NSLocalizedString(key, comment: "") }

// MARK: Configuration

/// `ProConfiguration.json` in the app bundle. `enabled: false` (the shipped default) keeps the app
/// on the Free plan with purchasing switched off until the payment service is deployed.
public struct ProConfiguration: Codable, Equatable {
    public let enabled: Bool
    public let apiBaseURL: String
    public let environment: String
    public let publicKey: String

    public init(enabled: Bool, apiBaseURL: String, environment: String, publicKey: String) {
        self.enabled = enabled
        self.apiBaseURL = apiBaseURL
        self.environment = environment
        self.publicKey = publicKey
    }

    public static func bundled(in bundle: Bundle = .main) -> ProConfiguration? {
        guard let url = bundle.url(forResource: "ProConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// The API origin, only when the configuration is complete and safe to talk to.
    public var baseURL: URL? {
        guard enabled, let url = URL(string: apiBaseURL), url.scheme == "https",
              let host = url.host, !host.hasSuffix(".invalid"), url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", let keyData = Data(base64Encoded: publicKey),
              (try? P256.Signing.PublicKey(x963Representation: keyData)) != nil else { return nil }
        #if IDEAMEMO_STAGING
        guard ["staging", "production"].contains(environment) else { return nil }
        #else
        guard environment == "production" else { return nil }
        #endif
        return url
    }
}

// MARK: Receipts

public struct LicenseClaims: Codable, Equatable {
    public let version: Int
    public let product: String
    public let environment: String
    public let licenseId: String
    public let email: String
    public let issuedAt: Int
    public let lifetime: Bool
}

public enum LicenseError: LocalizedError, Equatable {
    case unavailable, invalid, storage, revoked, pending, deviceReplaced, request(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return tr("Purchasing is not available yet. Please try again later.")
        case .invalid: return tr("Could not verify the license. Check the email and serial.")
        case .storage: return tr("Could not save the license to the Keychain. Make sure the Keychain is unlocked.")
        case .revoked: return tr("This license has been disabled. Please contact support.")
        case .pending: return tr("Payment not confirmed yet. You can check again later.")
        case .deviceReplaced: return tr("This serial is active on another Mac, so this Mac went back to Free. To use it here, enter your email and serial under “Have a serial? Restore Pro”.")
        case .request(let code):
            switch code {
            case "rate_limited": return tr("Too many attempts. Please try again later.")
            case "pending_limit": return tr("There are several unfinished orders. Please contact support to confirm your payment.")
            case "checkout_expired": return tr("The payment link has expired. Please contact support about your order.")
            case "device_change_limited": return tr("You can switch computers only once every 24 hours. Try again later, or contact support.")
            case "update_required": return tr("Please update Idea Memo to the latest version.")
            default: return tr("Could not reach the payment service. Please try again later.")
            }
        }
    }
}

public func normalizedLicenseEmail(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

public func decodeBase64URL(_ value: String) -> Data? {
    let base = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    return Data(base64Encoded: base + String(repeating: "=", count: (4 - base.count % 4) % 4))
}

public let proProductID = "ideamemo-pro-lifetime"

/// Checks a signed receipt: signature, product, environment, buyer email and issue time.
public func verifyLicenseToken(
    _ token: String, email: String, configuration: ProConfiguration, now: Date = Date()
) throws -> LicenseClaims {
    guard configuration.baseURL != nil else { throw LicenseError.unavailable }
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, let keyData = Data(base64Encoded: configuration.publicKey),
          let signatureData = decodeBase64URL(String(parts[1])),
          let payload = decodeBase64URL(String(parts[0])), payload.count < 4096,
          let key = try? P256.Signing.PublicKey(x963Representation: keyData),
          let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData),
          key.isValidSignature(signature, for: Data(parts[0].utf8)),
          let claims = try? JSONDecoder().decode(LicenseClaims.self, from: payload),
          claims.version == 1, claims.product == proProductID, claims.lifetime,
          claims.environment == configuration.environment, !claims.licenseId.isEmpty,
          claims.email == normalizedLicenseEmail(email), claims.issuedAt > 0,
          claims.issuedAt <= Int(now.timeIntervalSince1970) + 300 else { throw LicenseError.invalid }
    return claims
}

// MARK: Device and storage

/// A stable ID for this Mac: the hardware UUID hashed with an app-specific string. Only the hash
/// is sent, so the server cannot recover the hardware UUID.
public func licenseDeviceID() -> String {
    var uuid = ""
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    if service != 0 {
        uuid = (IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String) ?? ""
        IOObjectRelease(service)
    }
    if uuid.isEmpty {
        let key = "LicenseFallbackDeviceID"
        uuid = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        UserDefaults.standard.set(uuid, forKey: key)
    }
    let digest = SHA256.hash(data: Data(("ideamemo.device.v1:" + uuid).utf8))
    return Data(digest).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// The purchase page and the serial email follow the app language ("zh-Hant" or "en").
public func licenseLanguage(preferred: [String] = Locale.preferredLanguages) -> String {
    (preferred.first ?? "en").lowercased().hasPrefix("zh") ? "zh-Hant" : "en"
}

public protocol LicenseVault {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func clear() throws
}

public struct KeychainLicenseVault: LicenseVault {
    public var environment = "production"
    public var service = (Bundle.main.bundleIdentifier ?? "com.jimmy-tools.ideamemo") + ".license."

    public init(environment: String = "production") { self.environment = environment }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service + environment,
         kSecAttrAccount as String: "pro-v1"]
    }

    public func read() throws -> Data? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw LicenseError.storage }
        return item as? Data
    }

    public func write(_ data: Data) throws {
        let values: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if update == errSecItemNotFound {
            let added = query.merging(values) { _, new in new }
            guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else { throw LicenseError.storage }
        } else if update != errSecSuccess {
            throw LicenseError.storage
        }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LicenseError.storage }
    }
}

// MARK: Wire types

public struct PendingPurchase: Codable, Equatable {
    public var email: String
    public var method: String
    public var accessToken: String
    public var orderId: String?
    public var checkoutURL: String?
}

public struct LicenseRecord: Codable, Equatable {
    public var email: String = ""
    public var serial: String = ""
    public var licenseToken: String = ""
    public var pending: PendingPurchase?
    public var previousPending: [PendingPurchase]?

    public init() {}
}

struct OrderReply: Decodable { let orderId: String; let checkoutURL: String; let amount: Int; let currency: String; let environment: String }
struct PaidReply: Decodable { let status: String; let email: String?; let serial: String?; let licenseToken: String? }
struct ServiceFailure: Decodable { let error: String }

public struct PaymentOptions: Decodable, Equatable {
    public let environment: String
    public let amount: Int
    public let currency: String
    public let checkoutEnabled: Bool
    public let methods: [String]
}

private final class NoPaymentRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private func privatePaymentSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    return URLSession(configuration: config, delegate: NoPaymentRedirects(), delegateQueue: nil)
}

// MARK: Store

/// Owns the Pro entitlement. Payment secrets never enter the app: Pro unlocks only through a
/// server receipt that verifies against the bundled public key.
@MainActor
public final class ProLicenseStore: ObservableObject {
    @Published public private(set) var isPro = false
    @Published public private(set) var email = ""
    @Published public private(set) var serial = ""
    @Published public private(set) var isBusy = false
    @Published public private(set) var hasPendingPurchase = false
    @Published public private(set) var message: String?
    @Published public private(set) var options: PaymentOptions?
    @Published public private(set) var showPurchaseCelebration = false

    private let configuration: ProConfiguration?
    private let vault: LicenseVault
    private let session: URLSession
    private let deviceID: String
    private let now: () -> Date
    private var record = LicenseRecord()
    private var started = false

    public var hasRecoverablePurchases: Bool { record.pending != nil || !(record.previousPending ?? []).isEmpty }
    public var pendingEmail: String? { record.pending?.email }
    public var pendingMethod: String? { record.pending?.method }
    public var pendingCheckoutURL: URL? { record.pending?.checkoutURL.flatMap(URL.init(string:)) }
    public var isConfigured: Bool { configuration?.baseURL != nil }
    public var canPurchase: Bool { isConfigured && options?.checkoutEnabled == true }
    public var applePayAvailable: Bool { options?.methods.contains("ApplePay") == true }

    /// The price shown to the buyer, straight from the server (e.g. "NT$ 120").
    public var priceText: String? {
        guard let options else { return nil }
        return "NT$ \(options.amount)"
    }

    public init(
        configuration: ProConfiguration? = .bundled(),
        vault: LicenseVault? = nil,
        session: URLSession? = nil,
        deviceID: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.vault = vault ?? KeychainLicenseVault(environment: configuration?.environment ?? "production")
        self.session = session ?? privatePaymentSession()
        self.deviceID = deviceID ?? licenseDeviceID()
        self.now = now
        loadStoredLicense()
    }

    /// Reads the saved receipt right away so the plan is correct from the first frame.
    private func loadStoredLicense() {
        guard let data = try? vault.read(), let saved = try? JSONDecoder().decode(LicenseRecord.self, from: data) else { return }
        record = saved
        publishRecord()
        if !saved.licenseToken.isEmpty, let configuration,
           (try? verifyLicenseToken(saved.licenseToken, email: saved.email, configuration: configuration, now: now())) != nil {
            isPro = true
        }
    }

    /// App start: load options, resume any unfinished payment, and re-check the serial online.
    public func resume() async {
        guard !started else { return }
        started = true
        await loadOptions()
        if hasRecoverablePurchases { _ = await checkPayment() }
        // Offline, a verified lifetime receipt keeps working; online, the server can revoke it
        // or tell us another Mac took over.
        if !record.serial.isEmpty { await restore(email: record.email, serial: record.serial, quietly: true) }
    }

    private func publishRecord() {
        email = record.email
        serial = record.serial
        hasPendingPurchase = record.pending != nil
    }

    private func persist(_ updated: LicenseRecord) throws {
        try vault.write(JSONEncoder().encode(updated))
        record = updated
    }

    public func dismissPurchaseCelebration() { showPurchaseCelebration = false }
    public func reportBrowserFailure() { message = tr("Could not open the browser. Press “Reopen payment page”.") }

    public func loadOptions() async {
        guard isConfigured else { return }
        do {
            let result: PaymentOptions = try await call("/v1/config", method: "GET")
            guard result.environment == configuration?.environment, result.amount > 0, result.currency == "TWD" else {
                throw LicenseError.invalid
            }
            options = result
        } catch {
            message = error.localizedDescription
        }
    }

    /// Creates (or resumes) an order and returns the checkout page to open in the browser.
    public func purchase(email: String, method: String) async -> URL? {
        guard !isBusy else { return nil }
        guard canPurchase else { message = LicenseError.unavailable.localizedDescription; return nil }
        let normalized = normalizedLicenseEmail(email)
        let valid = normalized.range(
            of: "^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9][a-z0-9.-]*\\.[a-z]{2,63}$", options: .regularExpression
        ) != nil && normalized.count <= 254
        guard record.pending != nil || valid else {
            message = tr("Please enter a valid email.")
            return nil
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            if record.pending == nil {
                let random = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                let token = random.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
                var updated = record
                updated.pending = PendingPurchase(email: normalized, method: method, accessToken: token)
                // Save the ability to recover first, then ask the server; a timeout can retry with the same token.
                try persist(updated)
                publishRecord()
            }
            guard let pending = record.pending else { throw LicenseError.invalid }
            let reply: OrderReply = try await call("/v1/orders", body: [
                "email": pending.email, "method": pending.method,
                "accessToken": pending.accessToken, "language": licenseLanguage(),
            ])
            guard reply.amount == options?.amount, reply.currency == "TWD", reply.environment == configuration?.environment,
                  let url = URL(string: reply.checkoutURL), url.scheme == "https", url.host == configuration?.baseURL?.host,
                  url.port == nil, url.user == nil, url.password == nil, url.path == "/checkout/" + reply.orderId,
                  reply.orderId.range(of: "^[A-Z0-9]{20}$", options: .regularExpression) != nil else { throw LicenseError.invalid }
            var updated = record
            updated.pending?.orderId = reply.orderId
            updated.pending?.checkoutURL = reply.checkoutURL
            try persist(updated)
            publishRecord()
            return url
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    /// Asks the server whether the pending order has been paid; unlocks Pro when it has.
    @discardableResult
    public func checkPayment() async -> Bool {
        guard !isBusy else { return false }
        let pendingOrders = ([record.pending].compactMap { $0 }) + (record.previousPending ?? [])
        guard !pendingOrders.isEmpty else { return false }
        isBusy = true
        defer { isBusy = false }
        var lastError: Error?
        for pending in pendingOrders {
            guard let orderId = pending.orderId else { continue }
            do {
                let reply: PaidReply = try await call("/v1/orders/" + orderId, method: "GET", token: pending.accessToken)
                if reply.status == "paid" {
                    try accept(reply, expectedEmail: pending.email, celebratePurchase: true)
                    message = tr("Thank you! Pro is now active.")
                    return true
                }
            } catch {
                lastError = error
            }
        }
        message = lastError?.localizedDescription ?? LicenseError.pending.localizedDescription
        return false
    }

    /// Before starting a new order, check the old one and keep its token so a late payment notice
    /// can never leave a paying customer without a license.
    public func prepareNewOrder() async {
        guard !isBusy, let pending = record.pending else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let id = pending.orderId {
                let reply: PaidReply = try await call("/v1/orders/" + id, method: "GET", token: pending.accessToken)
                if reply.status == "paid" {
                    try accept(reply, expectedEmail: pending.email, celebratePurchase: true)
                    return
                }
            }
            var updated = record
            var previous = updated.previousPending ?? []
            guard previous.count < 5 else { throw LicenseError.request("pending_limit") }
            previous.append(pending)
            updated.previousPending = previous
            updated.pending = nil
            try persist(updated)
            publishRecord()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    /// Activates an existing serial on this Mac. Background checks (`quietly`) never take a serial
    /// away from another Mac; only the user pressing "Activate Pro" moves it here.
    public func restore(email: String, serial: String, quietly: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        if !quietly { message = nil }
        defer { isBusy = false }
        do {
            let reply: PaidReply = try await call("/v1/licenses/activate", body: [
                "email": normalizedLicenseEmail(email), "serial": serial,
                "deviceId": deviceID, "takeover": quietly ? "false" : "true",
            ])
            try accept(reply, expectedEmail: normalizedLicenseEmail(email))
            if !quietly { message = tr("Thank you! Pro is now active.") }
        } catch LicenseError.deviceReplaced {
            dropReceipt()
            message = LicenseError.deviceReplaced.localizedDescription
        } catch LicenseError.revoked {
            dropReceipt()
            message = LicenseError.revoked.localizedDescription
        } catch {
            if !quietly { message = error.localizedDescription }
        }
    }

    private func dropReceipt() {
        var updated = record
        updated.licenseToken = ""
        do {
            try persist(updated)
            publishRecord()
        } catch {
            message = error.localizedDescription
        }
        isPro = false
    }

    private func accept(_ reply: PaidReply, expectedEmail: String, celebratePurchase: Bool = false) throws {
        guard reply.status == "paid", let email = reply.email, let serial = reply.serial,
              let token = reply.licenseToken, let configuration,
              email == normalizedLicenseEmail(expectedEmail) else { throw LicenseError.invalid }
        _ = try verifyLicenseToken(token, email: email, configuration: configuration, now: now())
        let firstPurchase = celebratePurchase && record.licenseToken.isEmpty
        var updated = record
        updated.email = email
        updated.serial = serial
        updated.licenseToken = token
        updated.pending = nil
        updated.previousPending = nil
        try persist(updated)
        publishRecord()
        isPro = true
        if firstPurchase { showPurchaseCelebration = true }
    }

    private func call<T: Decodable>(
        _ path: String, method: String = "POST", body: [String: String]? = nil, token: String? = nil
    ) async throws -> T {
        guard let base = configuration?.baseURL else { throw LicenseError.unavailable }
        var request = URLRequest(url: base.appendingPathComponent(String(path.dropFirst())), timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count < 32768 else { throw LicenseError.invalid }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ServiceFailure.self, from: data))?.error ?? "service_unavailable"
            if code == "license_revoked" { throw LicenseError.revoked }
            if code == "device_replaced" { throw LicenseError.deviceReplaced }
            if code == "invalid_license" { throw LicenseError.invalid }
            throw LicenseError.request(code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
