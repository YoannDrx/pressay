# Pressay commercialization implementation plan

Status values used below:

- `open`: implementation has not started.
- `in_progress`: a branch contains implementation work, but the release gate is not met.
- `verified`: automated and native acceptance criteria have passed.
- `external_gate`: completion requires a verified third-party account or credential.

No gate in this document authorizes enabling paid production traffic by itself.

## 1. Source, environments and data ownership

| Work item             | Acceptance criteria                                                                                                                                    | Status      |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| Cloud source of truth | Cloud control-plane history is merged through a reviewed PR to `main`; Vercel production deploys only an immutable `main` commit.                      | in_progress |
| Environment inventory | Direct app, MAS app, web, Cloud staging and Cloud production each have a named owner, URL, database branch and secret scope.                           | in_progress |
| Database identity     | A non-secret deployment fingerprint exposes environment, database project fingerprint, schema version and commit without exposing a connection string. | in_progress |
| Migration gate        | Migrations run on a Neon branch, pass schema comparison and smoke tests, then run once during a controlled production deploy.                          | open        |
| Rollback              | The previous deployment and the pre-migration Neon restore point are recorded before promotion.                                                        | open        |

## 2. Stripe Direct distribution

### Account and catalogue

- Create a dedicated `Pressay` account under the YoDev Stripe Organization.
- Never modify the RoutineKids account from a Pressay deployment.
- Create one `Pressay Pro` product and two recurring prices: monthly and annual.
- Keep Checkout disabled until the destination account ID, live product ID and both
  live price IDs pass the server-side catalogue audit.
- Configure branding, public business information, support URL, cancellation policy,
  invoice footer, customer portal and a statement descriptor confirmed against the
  legal entity.
- Use a restricted live key with only the permissions observed during sandbox tests.

### Backend acceptance criteria

- The client can select only `month` or `year`; Price IDs remain server-owned.
- Every webhook is signature-verified from the untouched body and deduplicated.
- A subscription is projected only if its Product, Price and interval match an active
  row in `billing_product`.
- Multiple subscription items, unknown products, mismatched customers and stale
  events are ignored and auditable.
- Invoice success/failure, refunds and disputes are recorded without storing provider
  payloads or payment instruments.
- Entitlements are recomputed after relevant lifecycle changes.
- Test Clocks confirm no trial, then cover renewal, failed renewal, recovery, cancellation, refund and
  dispute scenarios.

### Migration gate

Before archiving any source object, produce counts of active subscriptions, customers,
payment methods, invoices, refunds and disputes. If a paid subscription exists, use
Stripe's account-to-account migration process and reconcile destination IDs. Archive
old Prices only after all active subscriptions have moved; archive the Product last.

## 3. Mac App Store distribution

### Product boundary

- Bundle identifier: `fr.yodev.pressay` (the immutable identifier attached to
  the existing Pressay App Store Connect record).
- Store build uses App Sandbox, public APIs, StoreKit and Apple-delivered updates.
- Store build contains no Stripe checkout, external purchase CTA, direct updater or
  private NSPanel feature.
- Cross-application paste is capability-tested. If sandbox validation fails, the Store
  build exposes an explicit copy-only workflow and never promises automatic insertion.

### StoreKit client acceptance criteria

- Product IDs are immutable and identical in the client, Cloud catalogue and
  App Store Connect: `app.pressay.desktop.mas.pro.monthly` and
  `app.pressay.desktop.mas.pro.annual`.
- Load Apple-configured monthly and annual products with Apple-localized prices.
- Purchase using the authenticated Pressay account UUID as `appAccountToken`.
- Verify StoreKit transactions on-device, send their signed JWS to the authenticated
  Cloud restore endpoint, then finish them only after the server accepts the purchase.
- Listen for transaction updates and reconcile current entitlements at launch.
- Implement Restore Purchases, pending, user-cancelled, unverified and offline states.
- Never embed App Store Server credentials in the desktop application.

### App Store Connect gate

- Apple Distribution certificate and MAS provisioning profile are installed only in
  the protected archive job.
- Monthly and annual auto-renewable subscriptions are reviewed with the application.
- App Store Server API credentials and V2 notification URL are configured in Cloud.
- StoreKit Configuration, Sandbox and TestFlight matrices pass before App Review.
- Version submitted for review is stable and contains complete FR/EN metadata,
  privacy answers, support URL, review notes and a working review account.

## 4. Validation matrix

### Automated

- App: translations, lint, formatting, frontend build, Playwright, Rust tests and MAS
  feature-graph/private-API inspection.
- Cloud: typecheck, lint, formatting, unit tests, secret scan, dependency audit,
  migration checksum and staging validation.
- Web: lint, typecheck, production build and checkout kill-switch tests.

### Native macOS

- M1 8 GB on macOS 14, a median Apple Silicon Mac and an Apple Intelligence Mac.
- Microphone, silence, device removal, permissions, push-to-talk, toggle and cancel.
- Mail, Messages, Notes, Safari, Chrome, Slack, Notion, Word, Cursor and Terminal.
- Direct DMG and sandboxed MAS build tested separately.

## 5. Promotion order

1. Merge and deploy Cloud staging from `main`.
2. Prove the production database identity and migration plan.
3. Complete Stripe sandbox and StoreKit Configuration tests.
4. Run native MAS sandbox tests with a development provisioning profile.
5. Promote Cloud production with all commercial kill switches still disabled.
6. Run Stripe live smoke tests with a private test account and refund the charge.
7. Distribute the MAS build through TestFlight.
8. Enable Direct Checkout gradually after reconciliation.
9. Submit the stable MAS build and its subscriptions for review.

## 6. Current release-gate ledger — 20 August 2026

| Gate                       | Evidence available                                                                                                                                                           | Remaining exit condition                                                                                                                                        | Status        |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| App source                 | `2.0.0-beta.2` is committed on `codex/commercialization-readiness`; translations, lint, frontend build, Playwright, MAS Cargo check and focused StoreKit tests pass locally. | Required PR checks, native macOS matrix, owner-authored PR section and human review.                                                                            | in_progress   |
| StoreKit client            | Closed product catalogue, Apple-localized products, purchase, restore, JWS verification and background reconciliation are implemented.                                       | Apple-signed Sandbox and TestFlight evidence with real App Store Connect products.                                                                              | external_gate |
| MAS sandbox graph          | Dedicated identifier, public feature graph, App Sandbox and audio-input entitlement are implemented and inspected by CI.                                                     | Apple Distribution and Mac Installer Distribution identities, provisioning profile and protected upload environment.                                            | external_gate |
| Cloud source               | The full control plane is represented by one secret-scan-clean commit in the draft Cloud PR. Local verification passes 23 files / 83 tests.                                  | Review, staging database migration, schema check, smoke tests and controlled merge to `main`.                                                                   | in_progress   |
| Cloud database             | Immutable migrations through `0013_billing_financial_events.sql`, `/health` environment identity and `/ready` schema version are implemented.                                | Run on a disposable Neon branch, record the destination fingerprint and restore point, then validate against production-shaped settings.                        | external_gate |
| Stripe Direct              | Exact-account and exact-catalogue audit, idempotent provisioning script, webhook lifecycle projection and server-side checkout kill switch are implemented.                  | Dedicated Pressay Stripe account, branding, restricted credentials, Test Clocks and signed webhook evidence. RoutineKids must remain untouched.                 | external_gate |
| Public DMG                 | Release workflow signs and notarizes a tagged DMG; landing and portfolio already resolve the latest non-draft GitHub release dynamically.                                    | Merge validated app PR, tag `v2.0.0-beta.2`, let the protected release workflow produce checksum and notarized DMG, then publish the draft after smoke testing. | external_gate |
| Landing/portfolio download | No code change is required for the download destination. Both consumers follow the latest valid GitHub release.                                                              | Publish the validated `beta.2` release; never point them at a branch artifact.                                                                                  | in_progress   |

The word `external_gate` is deliberate: source code cannot create legal agreements,
banking/tax verification, Apple certificates, production credentials or native-device
evidence. Paid traffic remains disabled until the corresponding evidence is attached
to the release record.
