# Idea Memo Pro: how licensing works

Same model as MacMP4: SHOPLINE Payments checkout, a Cloudflare Worker + D1 that sells a lifetime
serial and signs a receipt, a serial email after payment, and **one active Mac per serial**.

**Status: built and tested, not deployed.** The app ships with `Config/ProConfiguration.json`
set to `"enabled": false`, so it stays on the Free plan and shows "Pro purchases are not open yet".
Nothing talks to any server until the steps below are done.

## Pieces

| Where | What |
| --- | --- |
| `payments/` | The Worker (`src/worker.mjs`), mail (`mail.mjs`), crypto (`crypto.mjs`), D1 migrations, Node tests |
| `Sources/StickyCore/ProLicense.swift` | App side: receipt verification, Keychain vault, device ID, purchase / check / restore flow |
| `Sources/IdeaMemo/ProSection.swift` | The Plan section in Settings (buy, check payment, restore, Pro details) |
| `Config/ProConfiguration.json` | Bundled by `Scripts/package-app.sh`: `enabled`, API origin, environment, receipt public key |
| `Tests/StickyCoreTests/ProLicenseTests.swift` | Swift tests, using receipts signed by the Worker's own signing code |

## Flow

1. The buyer enters an email in Settings and picks credit card or Apple Pay. The app creates an order
   (`POST /v1/orders`) with a random access token it saved first, then opens the SHOPLINE checkout.
2. SHOPLINE calls the pay hub webhook. The Worker re-queries SHOPLINE, checks the payment belongs to
   the order, succeeded, and equals `PRICE_TWD`, then marks it paid and emails the serial (`IDM-…`).
3. The app polls the order, gets `{email, serial, licenseToken}`, verifies the P-256 receipt against the
   public key it ships with, stores it in the Keychain, and unlocks Pro. Price, order id and checkout URL
   are validated against what the server advertised.
4. On a new Mac: Settings ▸ Plan ▸ "Have a serial? Restore Pro" with email + serial. Pressing Activate
   moves the serial to this Mac (once per 24 h); background checks never take a serial from another Mac.
5. Offline, a verified lifetime receipt keeps working. Online, the server can revoke it.

The price is **not** in the code: the Worker reads `PRICE_TWD` (whole NT$, 1-100000) and refuses to
serve until it is set. The app shows the price the server reports.

## Deploy runbook (needs Jimmy's explicit approval in chat before any production step)

1. Decide the price and the Pro product page URL (`SITE` in `payments/src/mail.mjs`; the mail also
   links an icon at `https://pay.jimmy-tools.com/assets/ideamemo-icon.png`, which has to be added to the pay hub).
2. `cd payments && npm install`, then `npx wrangler d1 create ideamemo-payments` (and `-staging`);
   put the database ids in `wrangler.jsonc`. The config uses custom domains
   (`ideamemo-payments.jimmy-tools.com`) on purpose: a `workers.dev` host would expose the Cloudflare
   account subdomain.
3. `node scripts/prepare-config.mjs production https://ideamemo-payments.jimmy-tools.com <price>`
   creates a fresh signing key plus `DATA_KEY`/`LOOKUP_KEY` in `.dev.vars.production` (mode 600, never
   committed) and writes `ProConfiguration.production.public.json`. **Back up `.dev.vars.production`
   off-site**: losing the signing key means existing receipts can no longer be verified by new app builds.
4. Fill `SHOPLINE_MERCHANT_ID`, `SHOPLINE_API_KEY`, `SHOPLINE_SIGN_KEY` in `.dev.vars.production`.
5. Route the webhook: the pay hub (`MacMP4/payments-hub`) routes by order-id prefix. Add prefix `I` →
   service binding to `ideamemo-payments`. SHOPLINE allows 20 webhooks, so reuse the single hub endpoint.
6. `npx wrangler d1 migrations apply ideamemo-payments --env production --remote`,
   `node scripts/upload-secrets.mjs production`, `npx wrangler deploy --env production`.
7. Run a staging end-to-end first. Then set `CHECKOUT_ENABLED` to `"true"` and `PRICE_TWD` in
   `wrangler.jsonc` for production and redeploy.
8. Copy the public config into the app: `cp payments/ProConfiguration.production.public.json Config/ProConfiguration.json`,
   set `"enabled": true`, rebuild with `Scripts/package-app.sh`.
9. Check by hand: card payment, Apple Pay, serial email arrives, restore on a second Mac, the 24 h
   switch limit, revocation.

## Tests

```bash
swift test                              # app side incl. receipts signed by the Worker's code
cd payments && node --test tests/*.test.mjs   # Worker: webhook signature, price, serials, devices, mail
```

`Scripts` hooks in the app: `--keychain-selftest` checks Keychain storage from inside the sandbox.
