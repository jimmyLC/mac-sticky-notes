import AppKit
import StickyCore
import SwiftUI

/// The "Plan" part of Settings: what you have, how to buy Pro, and how to restore it on a new Mac.
struct ProSection: View {
    @ObservedObject var license: ProLicenseStore
    let memoCount: Int

    @State private var email = ""
    @State private var useApplePay = false
    @State private var restoreEmail = ""
    @State private var restoreSerial = ""
    @State private var showRestore = false
    @State private var polling: Task<Void, Never>?

    var body: some View {
        Section(L("Plan")) {
            LabeledContent(L("Your plan")) { planTag }

            if license.isPro {
                proDetails
            } else {
                Text(L("Free holds up to 10 memos. Pro has no limit."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if license.isConfigured { buying } else { notOpenYet }
                restore
            }

            if let message = license.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { polling?.cancel() }
    }

    // MARK: Pieces

    private var planTag: some View {
        let plan: Plan = license.isPro ? .pro : .free
        return Text(plan.tagText(currentCount: memoCount))
            .font(.caption.weight(.bold))
            .foregroundStyle(license.isPro ? Color.orange : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(license.isPro ? Color.yellow.opacity(0.3) : Color.secondary.opacity(0.18), in: Capsule())
    }

    private var proDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Thank you for supporting Idea Memo!")).font(.callout)
            if !license.email.isEmpty {
                Text("\(L("Purchase email")): \(license.email)").font(.caption).foregroundStyle(.secondary)
            }
            if !license.serial.isEmpty {
                Text("\(L("Serial")): \(maskedSerial)").font(.caption).foregroundStyle(.secondary)
            }
            Text(L("To use Pro on another Mac, enter your email and serial there. A serial works on one Mac at a time."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var maskedSerial: String {
        let parts = license.serial.split(separator: "-")
        guard parts.count > 2, let first = parts.first, let last = parts.last else { return license.serial }
        return "\(first)-••••••••-••••••••-••••••••-••••••••-\(last)"
    }

    private var notOpenYet: some View {
        Text(L("Pro purchases are not open yet."))
            .font(.callout)
    }

    @ViewBuilder
    private var buying: some View {
        if license.canPurchase {
            if license.hasPendingPurchase {
                Text(String(format: L("Waiting for your payment (%@)."), license.pendingEmail ?? ""))
                    .font(.callout)
                HStack {
                    Button(L("Reopen payment page")) { openCheckout() }
                    Button(L("Check payment")) { Task { _ = await license.checkPayment() } }
                    Button(L("Start over")) { Task { await license.prepareNewOrder() } }
                }
                .disabled(license.isBusy)
            } else {
                TextField(L("Email for your serial"), text: $email)
                    .textContentType(.emailAddress)
                if license.applePayAvailable {
                    Picker(L("Pay with"), selection: $useApplePay) {
                        Text(L("Credit card")).tag(false)
                        Text("Apple Pay").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Button(buyTitle) { buy() }
                    .buttonStyle(.borderedProminent)
                    .disabled(license.isBusy || email.isEmpty)
            }
        } else {
            Text(L("Pro purchases are not open yet.")).font(.callout)
        }
    }

    private var buyTitle: String {
        if let price = license.priceText { return String(format: L("Buy Pro — %@"), price) }
        return L("Buy Pro")
    }

    private var restore: some View {
        DisclosureGroup(L("Have a serial? Restore Pro"), isExpanded: $showRestore) {
            TextField(L("Purchase email"), text: $restoreEmail).textContentType(.emailAddress)
            TextField(L("Serial"), text: $restoreSerial)
            Button(L("Activate Pro")) {
                Task { await license.restore(email: restoreEmail, serial: restoreSerial) }
            }
            .disabled(license.isBusy || restoreEmail.isEmpty || restoreSerial.isEmpty || !license.isConfigured)
        }
    }

    // MARK: Actions

    private func buy() {
        Task {
            guard let url = await license.purchase(email: email, method: useApplePay ? "ApplePay" : "Credit") else { return }
            open(url)
        }
    }

    private func openCheckout() {
        if let url = license.pendingCheckoutURL {
            open(url)
        } else {
            Task { if let url = await license.purchase(email: license.pendingEmail ?? email, method: license.pendingMethod ?? "Credit") { open(url) } }
        }
    }

    private func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) { license.reportBrowserFailure() }
        startPolling()
    }

    /// After the browser opens, ask the server every few seconds until the payment lands.
    private func startPolling() {
        polling?.cancel()
        polling = Task { @MainActor in
            for _ in 0..<100 {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled || license.isPro || !license.hasPendingPurchase { return }
                if await license.checkPayment() { return }
            }
        }
    }
}
