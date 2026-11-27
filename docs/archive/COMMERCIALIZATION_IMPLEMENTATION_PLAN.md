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

## 6. Current release-gate ledger — 23 August 2026

| Gate                       | Evidence available                                                                                                                                             | Remaining exit condition                                                                                                                  | Status        |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| App source                 | `v2.0.0-beta.3` is published from `main`; stacked PRs #70–#72 are mergeable and all required checks are green.                                                 | Explicit human diff approval, merge in stack order, then rerun the release suite on the resulting `main`.                                 | in_progress   |
| StoreKit client            | Closed product catalogue, Apple-localized products, purchase, restore, JWS verification and background reconciliation are implemented.                         | Apple-signed Sandbox and TestFlight evidence with real App Store Connect products.                                                        | external_gate |
| MAS sandbox graph          | Identifier `fr.yodev.pressay`, sandbox graph, Apple distribution identities and provisioning profile are present; CI checks the public dependency graph.       | Upload credentials to the protected GitHub environment, archive/upload, then validate StoreKit Sandbox and TestFlight.                    | external_gate |
| Cloud source               | Stacked PRs #24–#26 are mergeable and green; Google/Apple, Free-first bootstrap, billing and deletion contracts are covered by the source tests.               | Explicit human diff approval, merge in stack order, deploy staging from `main`, then run the remote contract suite.                       | in_progress   |
| Cloud database             | Migration `0015_free_bootstrap_and_web_accounts.sql` was applied and tested on disposable Neon branch `br-restless-lab-b2k7ypak`; synthetic rows were removed. | Merge source, create a production restore point, apply to staging, then production only after smoke tests and rollback rehearsal.         | in_progress   |
| Stripe Direct              | Dedicated account is activated; one live `Pressay Pro` product has active 7.99 EUR monthly and 69 EUR annual prices. Checkout remains disabled.                | Create restricted environment credentials, validate signed webhooks/Test Clocks and obtain the remaining tax confirmation before opening. | external_gate |
| Public DMG                 | `v2.0.0-beta.3` was downloaded again from GitHub; checksum, strict signature, Gatekeeper and stapler validations pass for both DMG and inner app.              | Complete the native application matrix before promoting the stable commercial train.                                                      | in_progress   |
| Landing/portfolio download | Both public download routes resolve the verified `v2.0.0-beta.3` GitHub asset; the web PR keeps unvalidated Pro claims and checkout fail-closed.               | Merge web PR #18 after approval and promote its verified preview before the stable commercial launch.                                     | in_progress   |

The word `external_gate` is deliberate: source code cannot create legal agreements,
banking/tax verification, Apple certificates, production credentials or native-device
evidence. Paid traffic remains disabled until the corresponding evidence is attached
to the release record.
