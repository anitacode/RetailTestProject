# Improvements

Current implementation summary. `README.md` preserves the original assignment; setup updates and decisions belong here.

## Tracking and data integrity

- Upgraded Ruby to **3.4.11**; retained Rails **7.1.6** and PostgreSQL. Added explicit CSV and dotenv dependencies.
- Separated inventory and price observations using event types and JSONB payloads.
- Inventory uses `{ quantity: N }`: whole numbers; positive means in stock, zero/negative means out of stock.
- Price uses `{ amount: N, currency: "USD" }`: nonnegative amount and uppercase three-letter currency.
- Enforced payload rules in Rails and PostgreSQL, including bulk writes; rejected the redundant `present` key.
- Migrated legacy stock booleans to quantities 1/0 while preserving existing counts. Converted 1 values are placeholders; these data conversions are irreversible.
- Selected latest observations independently by category using `event_time DESC, id DESC`; excluded undated events from current values.
- Added an index for latest-observation lookups and a unique product-name/brand index.

## CSV import and console watcher

- Streamed imports in **1,500-row batches**, with batched reference lookups and bulk inserts inside one transaction.
- Rolled back the entire import on missing references, invalid dates/quantities, or ambiguous product names (two or more matches).
- Reported the first invalid CSV record number and reason; record numbers include the header and support multiline fields.
- Preferred CSV `Quantity`; fell back to legacy `Inventory Present` as 1/0.
- Added terminal progress, elapsed time, formatted counts, and staged-versus-committed reporting.
- Shared always-enabled Pastel styling, including green/red stock backgrounds.
- Added a polling watcher showing product, store, quantity, and current price; only changed values are printed.
- Queued alert reconciliation after bulk imports within the same database transaction.

## Alerts and background jobs

- Created inventory alerts for two consecutive out-of-stock observations for the same store/product, ordered by observation time and ID.
- Added price-change inbox alerts for different amounts in the same currency, using the preceding eligible price as the baseline.
- Enabled alerts for new observations without backfilling historical alerts; retained eligibility flags for legacy data.
- Added shared brand-level read/unread state, marked on detail visits, and a New badge.
- Used GoodJob with PostgreSQL for durable reconciliation and notification jobs, transaction-safe enqueueing, retries, and duplicate-delivery protection.
- Added queue status with five-second polling and retry actions for eligible failed jobs.
- Simulated SMS/email delivery through logs and delivery records; no external messages are sent.

## Brand access and contacts

- Added brand-name demo login, session handling, CSRF protection, and sidebar logout.
- Scoped alerts, contacts, jobs, and tracking events through policies using the session brand.
- Used a product join for tracking-event access; shared stores never expose another brand's observations.
- Added brand contacts with name, email, phone, and JSONB inventory/price notification preferences.
- Sent notifications through every available channel: SMS for phone and email for email, subject to preferences.
- Added contact create/edit dialogs, reusable dialog footer actions, and URL-based editing at `/alerts/settings/:id`.
- Added name/email/phone search with a **500 ms debounce**, pagination, and an international phone-input mask.

## Frontend

- Built a React, Vite, TypeScript, Tailwind, and React Query workspace with a teal/slate palette.
- Added alert list/detail, notification settings, queue status, and tracking-event history pages.
- Added selected sidebar navigation and shared session access through `useBrand`.
- Organized pages into their own directories with local components, queries, and utilities; standardized absolute imports.
- Extracted reusable forms, rows, pagination, dialogs, badges, and feedback components.
- Unified errors and empty states with centered `InfoMessage`, supporting an optional title and error/info/warning/success variants.
- Replaced nested rendering ternaries with early returns in page content; removed duplicate legacy implementations.
- Added scrollable tables, sticky headers, persistent pagination, and named responsive breakpoints.
- Added tracking-event date sorting across pages, with stable ID ordering, undated rows last, and URL-preserved direction.
- Refreshed alerts and jobs every five seconds; separated query caches by brand and cleared them on session changes.

## Tooling and checks

- Added `npm run dev` to start Rails, Vite, and the GoodJob worker together.
- Added RuboCop layout formatting, Prettier, editor format-on-save settings, and frontend TypeScript/build checks.
- Added frontend asset builds to Docker and Node setup to CI.
- Separated CI into **Rails tests**, **Vitest**, **Brakeman**, **RuboCop**, and **Frontend formatting and build** jobs.
- Kept `bin/check` as the local aggregate check; shared Ruby syntax checks through `bin/check-syntax`.
- Separated backend/frontend agent conventions in [AGENTS.md](AGENTS.md); added Rails/API/database/import skills and React best practices. See [agent setup](docs/agent-setup.md).

## Running locally

Requirements: Ruby **3.4.11**, Node **24**, and PostgreSQL. Configure `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`, and `DB_PORT` in ignored `.env.local`.

```bash
bundle install
npm ci
bin/rails db:create db:migrate
npm run dev
```

Open `http://127.0.0.1:5173/alerts` and enter an existing brand name. Rails runs on port 3000. `db:seed` deletes existing records; use it only for intentional demo-data initialization.

| Command | Purpose |
| --- | --- |
| `bin/rails tracking_events:import` | Import the tracking CSV |
| `STORE_ID=1 PRODUCT_ID=1 bin/rails tracking_events:watch` | Watch local observations; optional `INTERVAL=2` |
| `npm run jobs` | Run the worker separately |
| `npm run format` | Format Ruby and frontend files |
| `bin/check` | Run all local checks |

Tests use ignored `.env.test.local` with `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, and optional `DB_TEST_NAME` (default: `retail_test_project_rails_test`). Use a dedicated database and a role with ownership/CREATEDB; `.env.local` is not loaded in tests.

```bash
RAILS_ENV=test bin/rails db:create db:migrate
bin/rails test
npm test
```

## Verification and limitations

- Latest local verification: **109 Rails tests / 50,890 assertions** and **45 frontend tests** passed, plus formatting, Ruby syntax, Zeitwerk, TypeScript, and production frontend build.
- **Brakeman still fails because Rails 7.1.6 is unsupported.** The security check remains enabled; a Rails upgrade is outstanding.
- Split CI configuration was validated locally; GitHub execution requires the next push. Update branch protection if it requires the old “Rails checks” status.
- Brand-name login is demo access without identity verification; read state is shared by the brand.
- New tracking records trigger jobs; editing existing records does not. The worker must be running.
- The watcher observes the local database, can miss intermediate changes, and does not connect to retailers.
- Imports are not deduplicated on rerun. Ambiguous store addresses and strict legacy-boolean parsing remain follow-ups.
- Currency/phone checks validate format, not real-world validity. Phone search uses stored international text.
- Large-history counts, sorting, and deep offset pagination can be expensive; no full-million-row timing benchmark was completed.
- Docker image builds and real-browser layout/focus checks were not verified. Revisit Rails/connection_pool compatibility before enabling Redis caching.
