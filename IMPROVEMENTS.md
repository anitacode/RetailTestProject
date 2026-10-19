# Repository Improvement Log

This document records changes made during the repository setup and improvement work, why they were made, and how they were verified. Local machine setup is distinguished from changes tracked in Git. Secret values are intentionally omitted.

`README.md` is preserved unchanged. Use this document for subsequent changes,
updated commands, design decisions, and verification evidence. Dated entries
describe the state at that time; newer entries supersede earlier descriptions.

## Current setup and feature guide — moved from README on 2026-10-19

The README has been restored to the original assignment supplied by the project
owner, including its original Ruby 3.2.2 instructions. The implementation still
uses Ruby **3.4.11**, Rails **7.1.6**, and PostgreSQL. This documentation change does
not downgrade the application. Use the commands below for the improved version.
Earlier entries describing README edits are historical; future updates belong here.

### Current Ruby setup

```bash
rbenv install 3.4.11
rbenv local 3.4.11
bundle install
```

### Working with AI agents

Repository rules live in [AGENTS.md](AGENTS.md), task guidance in
[rails-expert](.agents/skills/rails-expert/SKILL.md), and automated checks run through
`bin/check` locally and in GitHub Actions. See [agent setup](docs/agent-setup.md)
for skill provenance, usage, and the checks included.

### Running tests

Configure `DB_USER`, `DB_PASSWORD`, `DB_HOST`, and `DB_PORT` in the git-ignored `.env.test.local` file. Dotenv does not load `.env.local` in the test environment. The test database defaults to `retail_test_project_rails_test`; override it with `DB_TEST_NAME` only for a separate test database. The configured PostgreSQL role must own that database and have `CREATEDB`, because Rails recreates it when preparing the test schema.

```bash
RAILS_ENV=test bin/rails db:create db:migrate
bin/rails test
```

### Import progress and terminal styling

The command first counts CSV records, then displays a progress bar with processed,
staged, and skipped row counts, plus elapsed seconds (including the counting pass).
The display updates after each batch and on completion. Inserts run in batches of 1,500 inside one transaction;
100% is displayed after the transaction succeeds. If the import fails, its changes
are rolled back. Missing stores/products or ambiguous product names abort the import, as documented in the atomic import entry below.
The progress display adapts to terminal width, using fewer details in narrow
windows so updates stay on a single line.

The importer and console watcher use Pastel with styling always enabled.

### Inventory and price observations

Tracking events use event-specific JSON in `value`:

- `inventory_presence`: `{ "quantity": 15 }` (requires a finite whole JSON number). Stock status is derived: quantity greater than zero is in stock; zero or negative is out of stock. The redundant `present` key is rejected.
- `price_tracker`: `{ "amount": 12.50, "currency": "USD" }` (requires a nonnegative JSON number and a three-letter uppercase currency code).

Rails validations and PostgreSQL check constraints enforce these rules, including for bulk inserts. Currency validation checks the code format, not membership in an ISO currency registry. Payloads have no default: callers must supply an observation. The payload migration converts legacy boolean inventory values and fails atomically if existing records cannot meet the constraints; it does not invent missing observations or prices. This data conversion is irreversible through `db:rollback`.

The quantity migration preserves existing counts and converts legacy true/false observations to 1/0. A converted 1 is a placeholder, not a measured count. This conversion cannot be rolled back. CSVs may supply a `Quantity` column with whole numbers; if absent, the legacy `Inventory Present` column is converted to 1/0. When both columns exist, `Quantity` takes precedence. Stock displays use quantity, not the legacy database boolean column.

Retrieve the current observations independently for a store/product pair:

```ruby
inventory = TrackingEvent.latest_inventory(store_id: store.id, product_id: product.id)
price = TrackingEvent.latest_price(store_id: store.id, product_id: product.id)
```

Each lookup returns an event or `nil` and filters by its own event category. Results are ordered by `event_time DESC, id DESC`: an older observation imported later cannot replace a newer one, and the greater ID breaks ties at identical observation times. Undated events remain in history but are excluded from current observations. A B-tree index on `(store_id, product_id, event_type, event_time DESC, id DESC)` supports these lookups; they do not search JSON contents and need no GIN index.

### Watching local changes in a terminal

Watch the current inventory and price for an existing store/product pair:

```bash
STORE_ID=1 PRODUCT_ID=1 bin/rails tracking_events:watch
```

Replace the IDs with your local records' IDs. The command prints initial values
(or `unknown`), then polls every second and prints only changed values. Set
`INTERVAL=2` to poll every two seconds. Stop with Ctrl-C; no web server is required.

In a second terminal, run `bin/rails console` and create observations for the same
pair (these save to your development database):

```ruby
pair = { store_id: 1, product_id: 1 }
TrackingEvent.create!(**pair, event_type: :price_tracker, event_time: Time.current, value: { amount: 12.50, currency: "USD" })
TrackingEvent.create!(**pair, event_type: :inventory_presence, event_time: Time.current, value: { quantity: 15 })
TrackingEvent.create!(**pair, event_type: :price_tracker, event_time: Time.current, value: { amount: 9.99, currency: "USD" })
TrackingEvent.create!(**pair, event_type: :inventory_presence, event_time: Time.current, value: { quantity: 0 })
```

Run each observation separately to see each transition. Polling reports the
latest state at each check; intermediate changes between checks can be missed.
Repeated values and historical imports that do not change the latest observation
produce no notification. This watches the local database, not external retailers;
live retailer data needs an additional integration that records observations.

## 2026-10-19 — Atomic import failures and unambiguous product matching

### Reject invalid records without committing a partial import

- **Problem:** `break` exited the batch loop normally, allowing the transaction to commit earlier inserts and skip the remainder of the batch. It did not trigger rollback.
- **Change:** `TrackingEvents::CsvImporter::InvalidRow` now raises inside the transaction for missing stores/products, invalid dates, and malformed explicit quantities. The task handles the error after rollback, displays the CSV record number and reason, and exits with status 1. Unexpected database errors retain their original diagnostic and also roll back.
- **Transaction boundary:** The importer currently uses batches of 1,500 inside one transaction. Progress reports staged rows; successful completion follows commit. A later-batch failure removes all inserts from that attempt while preserving pre-existing records.
- **Diagnostics:** Record numbering includes the header as record 1. A quoted multiline field remains part of one CSV record, so record numbers can differ from physical file line numbers. The importer stops at the first detected invalid record rather than collecting every error.

```text
Import failed; changes from this import were rolled back.
CSV record 1502: product not found for Product Name "Missing"
```

Fix the reported record and rerun `bin/rails tracking_events:import`. Failed attempts do not leave committed observations behind.

### Reject ambiguous product names

- **Problem:** Products are unique by name and brand, but the CSV has no brand identifier. Choosing the lowest matching product ID could assign observations to the wrong brand's product.
- **Change:** Product lookups aggregate matching IDs and counts in PostgreSQL, with one query per batch. Exactly one matching product is required. Two or more matches raise a record-specific error and roll back the import. Duplicate names not referenced by the CSV do not block it.
- **Decision:** Preserve the existing CSV format and reject ambiguity instead of guessing the product or fabricating brand information. A future stable product identifier would remove this ambiguity.

```text
CSV record 42: Product Name "Chocolate Frogs" matches 2 products; cannot choose a product without a unique identifier
```

### Verification and limits

- **Verified:** 48 tests passed with 50,451 assertions. Coverage includes failure after a completed batch, preservation of existing records, multiline record numbering, console error output/nonzero exit, two and three matching products, and unrelated duplicate names. Ruby syntax and Zeitwerk checks passed.
- **Security gate:** `bin/check` still fails on Brakeman's existing Rails 7.1.6 end-of-support warning; no suppression was added.
- **Scope:** Re-import deduplication, ambiguous store addresses, and strict validation of legacy boolean strings remain separate concerns. No full-file performance benchmark was run for these changes.

## 2026-10-17 — Ruby upgrade and reproducible dependencies

### Upgraded Ruby from 3.2.2 to 3.4.11

- **Changed:** Updated `.ruby-version`, `Gemfile`, `Gemfile.lock`, the Dockerfile's `RUBY_VERSION`, and the Ruby setup instructions in `README.md`. Installed Ruby 3.4.11 locally through rbenv and installed the project's gems for that runtime.
- **Why:** Ruby 3.2 had reached end of life. Moving to a supported Ruby release restores access to runtime bug fixes and security updates while keeping the application on Rails 7.1.6.
- **Scope:** This was a Ruby upgrade, not a Rails upgrade. Existing gem versions were retained except for newly introduced dependencies. Bundler remains pinned to 2.4.10.
- **Verified:** Dependency installation, including native extensions, completed. Rails boot and eager loading succeeded under Ruby 3.4.11. Database reads succeeded for all four application models. `/up`, `/`, `/stores`, `/brands`, and `/products` returned HTTP 200.
- **Limitation:** The Dockerfile version was updated, but a Docker image build was not verified.

### Audited gem compatibility before upgrading

- **Checked:** Ruby requirements published for all 87 then-locked gems, plus Bundler, covering 92 entries including platform variants.
- **Why:** Identify dependency restrictions before changing the runtime.
- **Result:** All checked entries allowed Ruby 3.4.11. This established declared compatibility; the subsequent app checks provided additional runtime evidence.
- **Follow-up:** Rails 7.1.6's Redis cache integration has an argument mismatch with the locked `connection_pool` 3.0.1. Redis caching is not enabled in the current configuration. Revisit this pairing before enabling it.

### Declared the CSV dependency explicitly

- **Changed:** Added `gem "csv", "~> 3.3"` to `Gemfile`; the lockfile resolved it to 3.3.6.
- **Why:** `TrackingEvents::CsvImporter` requires `csv`. In Ruby 3.4, CSV is a bundled gem rather than a default gem and must be included in the bundle explicitly.
- **Verified:** The importer loaded and handled an empty CSV with headers under Ruby 3.4.11.
- **Limitation:** This check did not exercise a full import or measure import performance.

## 2026-10-17 — Local environment configuration

### Added automatic loading of local environment files

- **Changed:** Added `dotenv-rails` to the default Gemfile group and installed version 3.2.0, along with `dotenv` 3.2.0.
- **Why:** Rails does not load `.env.local` automatically. Database settings previously had to be exported manually in each terminal session.
- **Decision:** The gem is available in all Rails environments because the initial setup also involved running production-mode commands locally. Day-to-day local work now uses development mode. Dotenv normally excludes `.env.local` in test mode.
- **Verified:** Rails loaded the local secret and database password from the file without those values being exported by the shell.
- **Behavior:** Existing shell environment variables take precedence over dotenv values. Old `DATABASE_URL` or `RAILS_ENV` exports can therefore override the intended local setup.

### Standardized database variable names

Development configuration in `config/database.yml` now reads:

| Variable | Purpose |
| --- | --- |
| `DB_NAME` | Database selected for local development |
| `DB_USER` | PostgreSQL login role |
| `DB_PASSWORD` | Password for that role |
| `DB_HOST` | PostgreSQL host |
| `DB_PORT` | PostgreSQL port |

- **Changed:** Replaced the intermediate names `DEVELOPMENT_DATABASE_NAME`, `PGUSER`, `PGHOST`, `PGPORT`, and `RETAIL_TEST_PROJECT_DATABASE_PASSWORD` in the local setup. Production configuration also reads `DB_PASSWORD`; its database and username remain explicitly configured.
- **Why:** Use one consistent, application-facing naming convention and make local connection settings configurable without editing tracked files.
- **Implementation:** Development values are serialized with `to_json` when inserted into YAML, preserving quoting for values containing special characters.
- **Verified:** Rails resolved the configured database, user, host, port, and password from `.env.local` in development mode.
- **Important distinction:** The selected local database is named `retail_test_project_production`, but Rails runs in development mode. A database name does not select the Rails environment. The test database remains separately named `retail_test_project_test`.

### Kept local secrets out of Git

- **Changed locally:** Generated a random `SECRET_KEY_BASE` in `.env.local`, preserved the existing database password, and set file permissions to `0600` so only the owning user can read or write it.
- **Why:** Production-mode Rails commands initially failed because `secret_key_base` was missing. Saving local configuration also avoids repeated manual exports.
- **Verified:** The repository's existing `.gitignore` excludes `.env.local`. Its existing `.dockerignore` excludes local environment files from the build context.
- **Scope:** The ignore rules already existed; they were verified, not newly added. `.env.local` and its secret values are not part of the committed repository. New checkouts need their own local configuration.

## 2026-10-17 — Product uniqueness at the database level

### Added a unique index on product name and brand

- **Changed:** Added `db/migrate/20261017090000_add_unique_index_to_products_name_and_brand_id.rb` with a reversible `add_index :products, [:name, :brand_id], unique: true` operation.
- **Why:** Prevent duplicate product names within the same brand, including concurrent writes and inserts that bypass Rails model validations. Different brands may still use the same product name.
- **Scope:** No product model validation, case normalization, or nullability change was added. PostgreSQL's usual unique-index behavior still allows multiple null names; the existing `brand_id` column is non-nullable. The existing standalone brand index is retained.
- **Verified:** Migration syntax passed and a read-only query found zero duplicate non-null name/brand pairs in the configured local database at the time of checking.
- **Status:** Subsequently applied successfully to an isolated temporary database during importer testing, and `db/schema.rb` was regenerated. Application to the normal development database is not confirmed. Run `bin/rails db:migrate` there; migration will fail if conflicting duplicates have since been inserted.

## 2026-10-17 — Batched tracking-event CSV import

- **Changed:** `TrackingEvents::CsvImporter` streams the CSV in batches of 100 rows, looks up matching store and product IDs once per batch, and inserts matching tracking events with `insert_all!`. The final partial batch is also inserted. This imports tracking events; it does not create products.
- **Why:** The old importer performed two lookups and an individual insert for every row. A full matching batch now uses two lookup queries and one bulk insert, reducing SQL round trips and avoiding individual Active Record object creation. Memory use is bounded by the batch size rather than the entire CSV.
- **Preserved:** Rows with missing stores or products are skipped, dates and booleans use the same parsing rules, timestamps are populated, and the completion log reports processed and inserted counts.
- **Tradeoffs:** Bulk inserts bypass model callbacks and validations; the current event model has only its store/product associations, whose IDs are looked up before insertion and protected by database foreign keys. Initially, errors left earlier batches committed; the transaction improvement below supersedes that behavior. Re-running a successful import can still create duplicate events.
- **Matching limitation:** The CSV has no brand column, so product matching remains name-only. If multiple products share a name, the importer now consistently picks the lowest ID. Brand-aware matching requires additional CSV data or a separate policy.
- **Verified:** Added four regression tests covering 205 rows across full and partial batches, query counts, references and timestamps, missing references, boolean parsing, empty/no-match inputs, and invalid dates. Tests passed with 17 assertions, zero failures, and zero errors in a temporary PostgreSQL database that was removed afterward. The 205-row test confirmed three bulk inserts and six lookup queries.
- **Limit:** A complete million-row benchmark has not been run; no wall-clock speedup is claimed.

### Expanded row-mapping regression coverage

- **Changed:** Added a test for 100 distinct CSV rows and another for 102 valid rows with missing references inserted at CSV rows 100 and 101, across the batch boundary.
- **Why:** Record counts alone cannot detect store IDs, product IDs, dates, or inventory values being assigned to the wrong event.
- **Coverage:** Every imported event is checked against its source date for the exact store, product, and inventory value, plus populated timestamps. CSV rows are deterministically shuffled, product associations differ from store creation order, and names/addresses include commas and quotes. Assertions do not depend on implicit database row order.
- **Verified:** The expanded importer suite passed in an isolated temporary PostgreSQL database: six tests, 629 assertions, zero failures, and zero errors. The temporary database was removed after the run.

### Increased the import batch size to 500

- **Changed:** Increased `CsvImporter::BATCH_SIZE` from 100 to 500. Updated regression tests for 500 distinct records, skipped rows at positions 500 and 501, and 1,005 records spanning two full batches plus a partial batch.
- **Why:** Reduce lookup and insert round trips further while continuing to stream the file with bounded memory. Larger batches use more memory and make each individual insert larger; full-file runtime has not been benchmarked.
- **Verified:** Six tests passed with 3,029 assertions, zero failures, and zero errors in an isolated temporary PostgreSQL database. The 1,005-row test confirmed three bulk inserts and six lookup queries. The temporary database was removed afterward.

### Made the complete import transactional

- **Changed:** Wrapped all 500-row batches in `TrackingEvent.transaction(requires_new: true)`. Completion logging remains after the transaction block. When called inside another transaction, a savepoint isolates the import so its changes roll back even if the caller rescues the error.
- **Why:** A parsing or database error late in the file should not leave a partially imported dataset. Previously inserted batches from the same call now roll back, while events that existed before the import remain intact. Missing references continue to be skipped.
- **Tradeoff:** The transaction remains open for the entire file, which can hold locks and database resources longer than committing individual batches. Rows still stream in bounded batches, but a failed import must be retried from the beginning.
- **Verified:** Added tests for an invalid date after 500 valid rows and a database check-constraint failure in the second batch. Both verify full rollback; the date test also verifies pre-existing events survive. All eight tests passed with 3,037 assertions in an isolated temporary database, with zero failures or errors. The temporary database was removed afterward.

### Added terminal import progress

- **Changed:** The import task counts CSV records and displays a progress bar, percentage, processed/total rows, staged inserts, and skipped rows. `CsvImporter` optionally reports cumulative counts after each batch and returns final counts; callers that do not request progress remain quiet apart from the existing log entry. Progress formatting lives in `TrackingEvents::ImportProgress`.
- **Why:** Large imports previously provided no indication of progress between start and finish. Users can now see ongoing work, including batches where all references are missing.
- **Transaction behavior:** The bar stays below 100% until the importer returns successfully after its transaction block. The task then displays the final inserted count. On an import error, it reports rollback and re-raises the original exception instead of printing success.
- **Tradeoff:** Exact totals require a preliminary streaming CSV pass, announced as "Counting CSV rows". Counting CSV records instead of physical lines handles quoted multiline fields. No full-file array or additional gem is needed. Terminal output redraws one line; redirected output uses separate lines only when the percentage changes.
- **Verified:** Fourteen tests passed with 3,061 assertions in a temporary PostgreSQL database, including cumulative counts, skipped batches, empty input, progress completion/failure output, terminal line handling, and the existing data-mapping and rollback tests. The temporary database was removed afterward.

### Styled the import completion message

- **Changed:** Successful imports display a padded, bold white `Done` badge on a green background in interactive terminals. Redirected output retains the plain `Done :)` message.
- **Why:** Make successful completion easier to spot after a long-running import. ANSI styling is reset immediately after the badge so subsequent terminal output keeps its normal colors.
- **Verified:** Ruby syntax and whitespace checks passed. Import and transaction behavior are unchanged.

### Formatted import counts with comma separators

- **Changed:** Processed, total, staged, inserted, and skipped counts now use comma-separated thousands in both ongoing progress and the completion summary, for example `1,000,000/1,000,000 rows | inserted: 1,000,000 | skipped: 0`.
- **Why:** Make large import counts easier to read. The change only affects display formatting.

### Increased import batches to 1,000 records

- **Changed:** Increased `CsvImporter::BATCH_SIZE` from 500 to 1,000 and updated the README. Adjusted tests for 1,000 distinct rows, skipped references at rows 1,000 and 1,001, and 2,005 rows spanning two full batches plus a final partial batch. Rollback and progress tests now exercise the larger boundary as well.
- **Why:** Further reduce lookup and insert round trips while retaining bounded-memory streaming and a single transaction for the entire import. This supersedes the earlier 500-row setting.
- **Verified:** All fourteen tests passed with 6,061 assertions, zero failures, and zero errors in a temporary PostgreSQL database, which was removed afterward. The 2,005-row test still uses three inserts and six lookup queries. No full-file performance benchmark was run.

### Increased import batches to 5,000 records

- **Changed:** Increased `CsvImporter::BATCH_SIZE` from 1,000 to 5,000 and updated the README. Tests now cover 5,000 distinct rows, skipped references at rows 5,000 and 5,001, and 10,005 rows across two full batches and a partial batch. Progress and rollback coverage use the new boundary.
- **Why:** Reduce database round trips further. Each batch uses more memory and produces a larger insert; streaming, whole-import transaction rollback, and progress reporting remain in place. This supersedes the earlier 1,000-row setting.
- **Verified:** Fourteen tests passed with 30,061 assertions, zero failures, and zero errors in an isolated temporary PostgreSQL database, removed afterward. The 10,005-row test used three inserts and six lookup queries. Full-file throughput has not been benchmarked.

### Styled progress as a growing blue rectangle

- **Changed:** Interactive terminals now display the completed portion of the progress bar as blue-background spaces, creating a solid growing rectangle. Redirected output retains the plain-text bar. Color resets before the remaining bar and counts, and line padding measures visible characters rather than ANSI escape sequences.
- **Why:** Make progress easier to scan visually while retaining readable logs and the existing percentage/count display.
- **Verified:** Checked half-full and complete terminal rendering, color reset, and plain-text output without database access.

### Increased batches to 10,000 and refined progress timing and layout

- **Changed:** Increased `CsvImporter::BATCH_SIZE` to 10,000 and updated boundary, mapping, progress, and rollback tests. The progress bar now displays elapsed seconds to one decimal place, removes its surrounding brackets, and leaves a blank line before the green Done badge. The initial import message also uses comma-separated row counts.
- **Why:** Further reduce database round trips and make the duration and completion of long imports easier to read. This supersedes the earlier 5,000-row setting.
- **Timing:** Uses a monotonic clock so system-clock adjustments do not distort elapsed time. Timing begins before the CSV counting pass and ends after the import transaction succeeds. The display refreshes after each batch and at completion, rather than running a separate timer thread.
- **Verified:** Fifteen tests passed with 60,075 assertions, zero failures, and zero errors in an isolated temporary PostgreSQL database, removed afterward. Coverage includes 10,000 distinct row mappings, a 20,005-row import, rollback after a completed batch, blue bar rendering without brackets, and deterministic elapsed-time assertions. Task syntax and whitespace checks also passed.
- **Tradeoff:** Larger batches require more memory per insert; no full-file throughput benchmark has been run.

### Prevented progress updates from wrapping into multiple lines

- **Problem:** The blue bar plus counts and elapsed time could exceed the terminal width. Once wrapped, a carriage return only returned to the beginning of the current physical line, leaving earlier updates visible.
- **Changed:** Read terminal width on each render, reserve the final column to avoid automatic wrapping, and shorten the bar/details as needed. Narrow displays prioritize percentage, row progress, and elapsed time; very narrow displays retain percentage and time. Every interactive redraw explicitly clears the line, replacing the old padding approach. Redirected output retains complete details.
- **Verified:** Six progress-display tests passed with 78 assertions, including million-row counts at widths of 160, 100, 80, 40, and 20 columns. Each rendered frame stays below the terminal width and begins by clearing the previous line. The temporary test database was removed afterward.

### Added tracking-event categories

- **Changed:** Added migration `20261017100000_add_type_to_tracking_events.rb`, creating a PostgreSQL `tracking_event_type` enum with `inventory_presence` and `price_tracker`, and a non-null `tracking_events.type` column defaulting to `inventory_presence`. Updated `db/schema.rb` from the isolated migration run.
- **Why:** Distinguish inventory observations from future price-tracking events. Existing rows receive `inventory_presence` when the column is added, so current data retains its meaning. PostgreSQL enforces the allowed values even for direct SQL writes.
- **Rails model:** Added a string-backed Rails enum and disabled single-table inheritance on `TrackingEvent`, because Rails normally reserves the `type` column for subclass names. Both categories can be saved and reloaded as ordinary tracking events.
- **CSV behavior:** Every imported event explicitly supplies `type: "inventory_presence"`; CSV data does not determine the category, and imports do not depend on the database default.
- **Verified:** In a temporary database, an existing event acquired the default category, rollback removed both the column and PostgreSQL enum, and reapplying succeeded. The combined importer/progress/model suite passed with 21 tests and 80,138 assertions. Tests cover both enum values, invalid/null database values, Rails inheritance behavior, every imported row's type, and explicit CSV typing even when the database default is changed within a test.
- **Scope:** The migration has not been applied to the normal development database by the assistant. Run `bin/rails db:migrate` before using the updated model/importer. This introduces event categories only; price amounts and price-tracking workflows remain future work. Rolling the migration back discards the category column.

### Added flexible JSONB event values

- **Changed:** Added migration `20261017110000_add_value_to_tracking_events.rb` with a non-null JSONB `value` column. Payloads contain a string `type` label and a `value` holding any JSON-compatible data, for example `{"type":"boolean","value":true}`. A database check requires both properties and a string label, without restricting the labels to a fixed enum or imposing a data type on the inner value.
- **Why:** Store different kinds of event measurements in one column: booleans, numbers, strings, arrays, objects, null, or custom-labeled JSON data. The nested payload type is distinct from the event category (`inventory_presence` / `price_tracker`).
- **Existing records:** Inventory events are backfilled from `inventory_present`, preserving true and false as JSON booleans. Missing inventory values and other events use `{"type":"null","value":null}` rather than inventing a measurement. This is also the default for new events that omit the payload.
- **CSV behavior:** The file and headers are unchanged. The importer parses `Inventory Present` once and writes both the existing boolean column and `value: { type: "boolean", value: inventory_present }`. The legacy column remains for compatibility; other writers must explicitly supply their payload, since no automatic synchronization callback was added.
- **Verified:** Checked backfill for true, false, missing values, and an existing price event, plus migration rollback/reapply in an isolated temporary PostgreSQL database. Twenty-four tests passed with 100,159 assertions, zero failures, and zero errors. Tests verify JSON data types and custom labels, reject malformed payload structures, and check the payload on every imported test row. The temporary database was removed afterward.
- **Deployment:** The normal development database has not been migrated by the assistant. Run `bin/rails db:migrate` before importing. The migration updates existing inventory rows, so its runtime and locking depend on table size. Rolling it back removes the JSON payloads while retaining the legacy inventory column.

## Local setup and troubleshooting completed during this work

These are environment/setup activities, not additional application features:

- **Ruby selection:** Diagnosed commands using macOS system Ruby 2.6 despite an rbenv version being selected. Provided shell initialization instructions so Ruby and Bundler resolve through rbenv instead of requiring writes to system gem directories.
- **Bundler:** Installed the project's pinned Bundler version for the upgraded Ruby runtime to keep dependency installation reproducible.
- **PostgreSQL access:** Identified the PostgreSQL 18 client outside the shell PATH, diagnosed password-authentication failures, and provided a local administrator password-reset procedure. The temporary peer-authentication rule was intended to be removed afterward; that restoration was not independently verified.
- **Database role:** Provided setup instructions for the `retail_test_project` login and database ownership, followed by `CREATEDB` permission for local database creation. Subsequent application database reads succeeded.
- **Beekeeper connection:** Clarified that Beekeeper has independent credentials and must select the same database as Rails. The screenshot showed the development-named database while the app was configured for the production-named local database.
- **Schema and sample data:** Explained the difference between creating a database, running migrations, and seeding it. The existing seed script deletes stores, brands, and products before rebuilding sample data; it was not changed as part of this work.

## Verification limits and remaining work

- The original Rails test files contain no active tests; importer regression tests have now been added. Ownership/schema permissions on the normal `retail_test_project_test` database remain unresolved, so importer verification used a separate temporary database.
- Successful boot, database reads, and page responses are smoke checks, not comprehensive behavioral or regression coverage.
- The product uniqueness migration has been verified in the temporary test database; application to the normal development database remains unconfirmed.
- The README objectives for price tracking and alerts have not been implemented. Importer batching is implemented, but full-scale performance measurement remains outstanding.

## Adding future entries

For each improvement, record the date, affected files, what changed, why it changed, verification results, and any remaining limitations. Distinguish implemented changes from proposals and local-only setup, and never include passwords or generated secrets.

## Brand alerts with React and Vite

The alert inbox lives at `/alerts`, with an individual detail page for each alert. Sign in using an existing brand name (case insensitive). Ambiguous names are rejected. Name-only access is a demonstration convenience: anyone who knows a brand's name can enter; it does not verify identity.

Rails stores the selected brand in its session and preserves CSRF protection. `AlertPolicy::Scope` centralizes brand access using Pundit; both API list and detail lookups use `policy_scope(Alert)`, with `verify_policy_scoped` checking that the scope was applied. `pundit_user` supplies `current_brand`. Cross-brand IDs return 404; anonymous requests return 401. Lists are paginated at 20 alerts and eager load displayed associations.

An alert represents each adjacent pair of inventory observations with quantity <= 0 for the same product and store, ordered by `event_time`, then ID to resolve ties. Price observations and undated events are excluded. Three consecutive empty observations produce two alerts. These are historical observations, not a claim that inventory is still empty now.

New model-created observations queue reconciliation for their product/store. The CSV importer queues one reconciliation after its bulk inserts. Both queue inserts share the tracking transaction; workers run after commit (see queued notifications below). Late observations can invalidate alerts or change the preceding observation. A unique triggering-event index prevents duplicate alerts; reconciliation is idempotent. A PostgreSQL advisory transaction lock serializes reconciliation. This favors correctness for the demonstration but limits concurrent ingestion throughput; full imports also scan dated alert-eligible inventory history. Observations should be appended. Direct SQL/bulk writes outside the importer, edits, deletions, or product brand reassignment require explicit reconciliation of eligible observations.

### Running the UI

Use Node 24 and the repository Ruby version:

```bash
bundle install
npm ci
bin/rails db:migrate
npm run build
bin/rails server
```

Open `http://localhost:3000/alerts`. For frontend development, keep Rails on port 3000, run `npm run dev:web`, and open `http://127.0.0.1:5173/alerts`; Vite proxies `/api` to Rails. Run `npm run build` again to update the version served by Rails. Docker includes a separate Node build stage and copies the generated UI into Rails' public directory.

`bin/check` now runs Vitest and the production frontend build as well as the existing Rails checks. CI installs Node dependencies first. Tests exercise login, pagination, details, session expiry, cross-brand access, CSRF, event ordering, late observations, idempotency, and transaction rollback.

Verification: the full Rails suite passed (60 tests, 50,498 assertions), followed by two focused policy tests (3 assertions). All five React tests and the production build passed. Ruby syntax and Zeitwerk passed. `bin/check` remains nonzero solely because Brakeman flags the existing unsupported Rails 7.1.6 dependency; that warning was not suppressed. The Docker build and visual browser testing have not been run.

## Consistent code formatting

Ruby/Rails uses RuboCop's layout rules; React, JavaScript, CSS, and frontend HTML use Prettier. Both use two-space indentation and LF line endings. `.editorconfig` supplies matching editor defaults. Ruby formatting is restricted to layout corrections; it does not introduce a new set of architecture, naming, or complexity rules. Ruby line length is unrestricted for SQL and long test descriptions; Prettier wraps at 100 columns where possible.

```bash
npm run format             # Apply Ruby and frontend formatting
npm run format:check       # Check both without changing files
npm run format:ruby        # Ruby only
npm run format:web         # React/JS/CSS/HTML only
```

Install dependencies with `bundle install` and `npm ci`. Formatting checks run through `bin/check` and the existing CI workflow. The initial formatting pass was applied to existing source files. Generated schema/assets, dependencies, and vendored agent skills are excluded; README and other Markdown files are excluded from automatic formatting. ERB templates are not covered by these formatters. Changes to this setup are documented here, leaving the original README intact.

Adding RuboCop initially resolved JSON 3, which rejects the `quirks_mode` option used by Rails 7.1. The Gemfile now constrains JSON to version 2 to preserve compatibility; the lockfile records the resolved version.

The verification run also exposed a pagination type mismatch in the current alert controller (integer conversion before regex validation). Page validation now receives a string, and policy scoping occurs before the invalid-page early return.

Final verification: formatting checks passed (80 Ruby files plus frontend sources), all 62 Rails tests and 5 React tests passed, and the frontend production build succeeded. The remaining `bin/check` failure is the existing Brakeman unsupported-Rails warning.

### Format on save in VS Code / Cursor

Workspace settings in `.vscode/settings.json` enable full-file formatting on save for Ruby, JavaScript/React, TypeScript/TSX, CSS, HTML, and JSON. Ruby uses the bundled RuboCop with layout-only safe corrections; Prettier uses the repository configuration. Ruby associations also cover Gemfile, Rakefile, rake tasks, and Rails bin scripts. Markdown save formatting and whitespace rewriting are disabled to preserve the original README.

Install the recommended `rubocop.vscode-rubocop` and `esbenp.prettier-vscode` editor extensions (listed in `.vscode/extensions.json`), run `bundle install` and `npm ci` if needed, and reload the editor window. Settings are scoped to this repository. Other editors require their own formatter-on-save integration; ERB remains outside this formatter setup. The settings JSON was validated, but an actual editor save was not exercised in this session.

### Start both development servers

Run `npm run dev` from the project root to start Rails on `127.0.0.1:3000` and Vite on `127.0.0.1:5173` together. Open `http://127.0.0.1:5173/alerts`. Output is labeled `rails` or `vite`; Ctrl+C stops both, and either process exiting stops the other. The launcher uses the local `concurrently` development dependency. `bin/dev` and `npm run dev:all` are aliases; `npm run dev:web` starts only Vite.

Run `bundle install`, `npm ci`, and `bin/rails db:migrate` as initial setup. The launcher does not seed, reset, or migrate the database. Stop any separately running Rails/Vite instances before starting it.

Launcher verification: both servers started, `/alerts` and the proxied `/api/session` returned HTTP 200, and Ctrl+C stopped both. Shell syntax, formatting, frontend tests/build, and all 62 Rails tests passed. `bin/check` still reports the existing Brakeman unsupported-Rails warning.

### Frontend root URL

Opening Vite at `http://127.0.0.1:5173/` now replaces the browser URL with `/alerts` before mounting the router, preserving query parameters and fragments. Previously, the `/alerts` router basename did not match `/`, so React rendered nothing. Direct detail URLs remain unchanged. Regression tests cover the root entry and direct detail paths. Rails' existing root page remains the store index.

## Tailwind CSS integration

Tailwind CSS is compiled by the official `@tailwindcss/vite` plugin. The React stylesheet imports Tailwind's theme and utilities, with shared brand colors and font families defined through `@theme`. Existing styles live in the components layer so utility classes can override them. Shared buttons and error panels use `@apply`; the loading layout uses utilities directly, and accessible hidden text uses Tailwind's `sr-only` utility.

This is an incremental adoption: custom layouts remain in CSS. Tailwind Preflight is intentionally omitted to retain the existing reset and browser defaults while migrating. Prettier's Tailwind plugin sorts utility classes on format/save using the stylesheet's theme. The Tailwind IntelliSense editor extension is recommended in workspace settings. No Rails Tailwind gem or separate CSS build process is needed; `npm run dev` and `npm run build` compile it through Vite. Restart the development command after installing these dependencies.

Verification: formatting, all 7 frontend tests, all 62 Rails tests, and the production build passed. Generated CSS contains the expected Tailwind layout/accessibility utilities and brand theme. Browser visual regression testing was not performed. The existing Brakeman unsupported-Rails warning remains the only failing check.

## TypeScript frontend

The React/Vite frontend now uses `.ts`/`.tsx`, including its tests and Vite configuration. Strict compiler checks cover component props, loading/session state, form events, API responses, and test mocks. Shared response types live in `frontend/src/types.ts`; the API client accepts standard `RequestInit` options and exposes `ApiError` for typed status handling. Response types describe the Rails contract at compile time; they are not runtime JSON schema validation.

`npm run typecheck` runs TypeScript without emitting files. `npm run typecheck:watch` is available for continuous terminal feedback. `npm run build` checks types before bundling, so existing `bin/check`, CI, and Docker builds enforce types too. The Docker stage copies the TypeScript config. Prettier and format-on-save cover TS/TSX; `npm run dev` remains the single command for Rails and Vite. Legacy Rails Stimulus/importmap files remain JavaScript, outside the React frontend migration.

Verification: strict TypeScript and formatting checks, all 10 frontend tests, all 62 Rails tests, and the production build passed. API regression tests cover status errors, non-JSON failures, and custom Headers. The only failing repository check remains Brakeman's existing unsupported-Rails warning. Docker was updated but not built in this session.


## Alerts start with new tracking observations only

Historical backfilling was removed at the user's request. The new `alert_eligible` database column marks all observations present when the migration runs as false, then changes the default to true for subsequent inserts (including CSV bulk inserts). Reconciliation only considers eligible observations, so an old pair cannot reappear during an unrelated new import. Two new eligible out-of-stock observations for the same product/store are required. New observations are still ordered by event time, with ID as tie breaker; late dates in new inserts remain eligible.

The previous `alerts:rebuild` task and setup instructions were removed. In the local development database, 39,114 generated alerts were deleted; all 1,000,001 tracking records were preserved and excluded from future alert generation. This cleanup was explicitly requested and run only in development, not embedded as a destructive migration for other environments. The column migration takes a brief schema lock and uses PostgreSQL's constant-default behavior to avoid rewriting historical rows. Rolling it back removes eligibility metadata and does not recover deleted alerts.

Restart Rails after applying the migration so running processes refresh the tracking-event schema. Normal model creation and CSV imports continue creating new alerts transactionally. Tests cover an empty start, exclusion of old pairs, two new observations, and CSV imports without historical backfill.

Verification: all 64 Rails tests and 10 frontend tests passed, along with type checking, formatting, and the production build. The existing Brakeman unsupported-Rails warning is still the only failing check.

## React best-practices review and React Query

Installed `vercel-react-best-practices` from `vercel-labs/agent-skills` into `.agents/skills/` using the requested skills CLI; `skills-lock.json` records its source and content hash. The repository skill catalog now points agents to it. Relevant rules reviewed: client request deduplication, deriving state instead of effects, stable component definitions, cached repeated work, and one-time application initialization. The skill's SWR guidance is applied with the explicitly requested TanStack React Query; this remains a Vite app, without Next.js-specific APIs.

The review found repeated effect-driven request state in session/list/detail views and a large combined component file. Queries now own cached server data, pending/error state, deduplication, and refetching; login/logout use mutations. Components were split into login, list, detail, and shared presentation files. `App.tsx` handles session rendering and routing. A single `Intl.DateTimeFormat` instance replaces one formatter allocation per displayed timestamp, and initial URL normalization now runs during application startup rather than as a side effect of rendering the router.

Alert query keys include the brand ID plus page or alert ID. Alerts stay fresh for 30 seconds, stale queries revalidate with React Query's focus/reconnect behavior, and Refresh explicitly refetches. No cache is persisted to local storage. Fetches consume the query's abort signal. Client errors are not retried; transient failures get at most one retry. Mutations are not automatically retried. Login/logout cancel old queries and remove alert caches before publishing the new session. A 401 from the current brand's alert queries removes cached alerts and returns to login; errors from obsolete brand queries cannot sign out a newer session. The session query stays cached until a session mutation, unauthorized response, or page reload. Separate browser tabs sharing cookies are not synchronized by this client cache.

Regression coverage includes concurrent request deduplication, fresh-cache reuse, separate brand/page keys, cancellation, 401 handling without retries, and cache clearing after both login and logout, in addition to the existing UI/API tests. Server-side Pundit access controls remain authoritative.

Verification: all 16 frontend tests and 64 Rails tests passed. Strict TypeScript, formatting, Zeitwerk, and the production build also passed. Brakeman's existing unsupported-Rails warning remains the only failed check. No browser visual test or Docker build was performed for this refactor.

### Automatic alert refresh

Alert list and detail queries now refetch every five seconds through React Query while the page is mounted and the tab is active. Polling stops when the view unmounts (including logout); hidden tabs use React Query's default pause behavior. The session query does not poll. Existing cached content remains visible during background fetches, and manual Refresh is still available. A timer regression test verifies the five-second interval and that leaving the page stops requests.


## Queued alerts and simulated SMS

Alert calculation now runs in `Alerts::ReconcileJob` on the `alerts` queue. New alert inserts queue `Alerts::SimulateSmsJob` on `notifications`. GoodJob stores jobs in the existing PostgreSQL database; no Redis or SMS provider is needed. The adapter runs in external mode, and `npm run dev` starts Rails, Vite, and a single-thread job worker with labeled output. `npm run jobs` starts only the worker. Production needs a separate `bundle exec good_job start` process alongside Rails; Docker's default command still starts only the web server.

Run `bundle install`, `npm ci`, and `bin/rails db:migrate`, then restart `npm run dev` and any open Rails consoles. Queue and notification tables are new; migrations do not backfill existing alerts or change tracking history. Their rollback drops queue/delivery state, so they should not be rolled back with pending work.

### Transaction boundary and retries

Unlike an in-memory async adapter, GoodJob persists the job in the same PostgreSQL transaction as the tracking insert or import. This deliberately enqueues inside the transaction rather than using an after-commit callback: workers cannot see it before commit, rollback removes it, and there is no gap between committing data and recording work. This guarantee depends on GoodJob sharing the application database/connection configuration. Imports remain synchronous and all-or-nothing for tracking rows, while alert processing happens afterward. Alert creation and SMS-job insertion likewise share a transaction.

Reconciliation retains its advisory lock and unique triggering-event index. Only newly inserted alerts queue notifications; recalculating unchanged alerts or updating a late observation's adjacency does not resend. Missing/invalidated alerts are skipped by the notification job. Both jobs retry deadlocks and lock timeouts up to three attempts, three seconds apart; other errors or exhausted retries remain recorded as failed GoodJob jobs. Inspect failures with `GoodJob::Job.where.not(error: nil).order(created_at: :desc)` in Rails console. After addressing the cause, an errored job can be retried with `GoodJob::Job.find(job_id).retry_job`.

### SMS simulation

The fictional destination is `+12025550123` (constant `Alerts::SimulateSmsJob::DEMO_PHONE_NUMBER`). A `SmsDelivery` row stores the message, destination, alert ID, and simulation time. A unique alert index plus the reconciliation lock prevents duplicate delivery records for duplicate job executions. The worker prints and logs, for example:

```text
[SMS SIMULATED] to=+12025550123 The Prancing Pony: Bree-Brewed Ale was out of stock in two consecutive checks at Demo shop. Alert #123. (no real SMS sent)
```

Check `SmsDelivery.order(id: :desc).first` in Rails console. This is only an emulator: no phone receives anything. The persisted delivery record is authoritative; console logging happens after commit and is not an exactly-once external-delivery guarantee. A real provider would need its own idempotency key/reconciliation strategy. Deleting an invalidated alert cascades to its simulated delivery record. No notification is generated just by installing this feature.

The worker must be running for queued work to execute. Jobs persist across worker restarts. The frontend still polls every five seconds, so a newly created alert appears after worker completion and the next poll.

Verification: 70 Rails tests and 17 frontend tests passed, together with formatting, TypeScript, Zeitwerk, and the production build. A real GoodJob adapter test verifies that the queued row is inserted inside the tracking transaction and disappears on rollback. The worker was started against local PostgreSQL and shut down cleanly. Job tests cover normal delivery, duplicates, invalidated/missing alerts, eligibility, and bounded retry exhaustion. Brakeman's existing unsupported-Rails warning is still the only failed check.

## Brand contacts and notification preferences

This supersedes the earlier fixed-number SMS demo. `Brand` now has many `Contact` records, each with a required name, optional email/phone, and a required JSONB `setup`. At least one channel is required. Phone numbers use international `+` format with 8–15 digits. Setup defaults to `{alert_no_inventory: false, alert_price_change: false}`; both keys must exist and be real JSON booleans. Unknown keys are rejected. Rails validations and PostgreSQL constraints enforce these requirements, including bulk writes.

As requested, every available channel is used: phone produces a simulated SMS; email produces a simulated email. A contact with both receives both, provided that event's preference is true. Manage contacts through Rails console:

```ruby
contact = Brand.find(1).contacts.create!(
  name: "Inventory team",
  email: "inventory@example.com",
  phone: "+12025550123",
  setup: { alert_no_inventory: true, alert_price_change: true }
)

# Disable only price notifications, preserving the other preference.
contact.update!(setup: contact.setup.merge("alert_price_change" => false))
NotificationDelivery.where(contact: contact).order(id: :desc)
```

New inventory alerts enqueue `Notifications::DispatchJob`. New dated, eligible price observations also enqueue dispatch: a price differs from its immediately preceding eligible price observation for the same store/product, ordered by event time and ID. A first price, unchanged amount, or currency change does not send a price-change message. Historical ineligible observations are not used as the baseline. Price notifications are separate from the inventory-only alert inbox. Late inserts evaluate the newly inserted event; they do not resend notifications for previously evaluated successor price events.

Dispatch iterates the brand's subscribed contacts in batches, then queues one `Notifications::DeliverJob` per available channel. Delivery rechecks the source, contact's current brand, preference, and destination. `NotificationDelivery` stores the message, destination, kind, channel, simulation time, and inventory-alert or price-event source. Database uniqueness per source/contact/channel and the reconciliation lock make repeated jobs safe. Preferences/destination changes before delivery are respected; adding a contact does not backfill old notifications. Separate contact records sharing an address are separate recipients.

Both channels remain simulated: `[SMS SIMULATED]` / `[EMAIL SIMULATED]` appear in worker output and Rails logs; nothing is sent externally. The old `SmsDelivery` table is retained as historical demo data. The old queued `Alerts::SimulateSmsJob` name delegates to contact dispatch for compatibility; it no longer uses a hardcoded recipient. Contacts and deliveries are new tables with no contact or historical notification backfill. Foreign keys cascade delivery deletion when its contact/source is deleted. Reversing the migration loses contact preferences and delivery history; stop workers before any rollback.

Restart `npm run dev` and Rails consoles after migrating to load the new jobs/associations. No contacts UI or public contact API was added; console management is the entry point for this change. Verification: all 78 Rails tests and 17 frontend tests passed, as did formatting, TypeScript, Zeitwerk, and the production build. Tests cover model/direct-write constraints, both channels, subscription/brand isolation, preference changes, price baselines/changes, and duplicate delivery. The existing Brakeman unsupported-Rails warning remains the only failing check.

### SideMenu component

Extracted the workspace sidebar into `frontend/component/SideMenu.tsx`, as requested. `App` passes the signed-in brand through a typed prop. Markup, navigation, and appearance are preserved. TypeScript and Tailwind include the new component directory; the existing frontend formatting glob already covers it.

### Reusable brand hook

`frontend/src/hooks/useBrand.ts` selects the signed-in brand from the existing React Query session cache. Both App and SideMenu use it; the sidebar no longer takes a brand prop. The hook returns the query result, including loading/error/refetch state, with `data` containing the brand (`undefined` while loading, `null` when signed out). Consumers share the session query rather than fetching independent copies or introducing duplicate context state. A stable selector subscribes consumers to the brand value.

### Header component

Extracted the top bar into `frontend/component/Header.tsx` alongside SideMenu. Typed `onLogout` and `loggingOut` props preserve the existing button behavior and pending text; App continues to own the session mutation and display its errors.

### Login while the session loads

Removed App's separate boot screen: an absent brand now renders Login immediately. Login shares the existing session query and keeps submission disabled until session initialization supplies the CSRF token. Session errors and retry remain available directly on the form. Existing sessions open their workspace after loading, so a brief login screen can appear during startup. Removed the unused boot-screen CSS.

Regression coverage verifies immediate login rendering, disabled submission during a delayed session request, recovery from a failed request, and returning to login after session expiration.

Verification: 19 frontend tests and 78 Rails tests (50,610 assertions) passed. Formatting, TypeScript, production build, and Zeitwerk checks passed. `bin/check` still fails only on the existing Brakeman warning about unsupported Rails 7.1.6.

### React form event typing

Replaced the deprecated React `FormEvent<HTMLFormElement>` with `SubmitEvent<HTMLFormElement>` in Login's submit handler, matching the installed React types. Runtime behavior is unchanged. Verification: TypeScript, formatting, build, 19 frontend tests, and 78 Rails tests passed; `bin/check` still reports the existing Brakeman unsupported-Rails warning.

### Tailwind component styling

Moved the login, workspace, sidebar, header, alert list, alert detail, and feedback styling from named CSS selectors into Tailwind `className` utilities. Responsive variants carry the existing 760px/1100px/1500px layouts; pseudo-element and state variants cover decorative effects, row hover, and input focus. Exact colors and dimensions use arbitrary values where the standard scale would change the design. Existing shared accessibility defaults (keyboard focus outlines and disabled controls) remain in the base layer.

`frontend/src/styles.css` is reduced from 864 to 80 lines: font imports, Tailwind source/theme configuration, and document defaults. Component selectors and `@apply` rules are removed. Prettier continues sorting Tailwind classes on format/save. README is unchanged by this work.

Verification: all 361 distinct component utility classes compile through Tailwind. Formatting, TypeScript, production build, 19 frontend tests, and 78 Rails tests passed. `bin/check` still fails only for the existing Brakeman unsupported-Rails warning. No browser screenshot comparison was performed; automated checks verify compilation and behavior, not pixel-level visual equivalence.

### Teal and slate palette

Replaced the forest-green/olive interface colors with Tailwind's teal and slate palette. The sidebar and login story use slate-900, surfaces and borders use light slate, primary actions use teal-700/800, and highlights use teal-300. Supporting text uses slate-500/600 instead of pale olive; informational panels and timeline markers use teal accents. Existing warm out-of-stock badges and error colors retain their meaning. Focus indicators and the browser theme color follow the new palette.

Component colors use named Tailwind classes; shared brand tokens reference Tailwind's teal variables. Layout and behavior are unchanged. No new dependencies or README edits were needed.

Verification: formatting, TypeScript, production build, 19 frontend tests, and 78 Rails tests passed. The only failing `bin/check` step remains the existing Brakeman unsupported-Rails warning. No browser visual comparison was performed.

### LoginForm component

Extracted the login form into `frontend/component/LoginForm.tsx`, alongside Header and SideMenu. LoginForm owns the name input, shared session query, login mutation, submission guard, errors, and retry action. The Login page now composes the form with the surrounding layout. Styling and behavior are preserved, including waiting for session initialization before submitting.

Verification: formatting, TypeScript, production build, 19 frontend tests, and 78 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### AlertRow component

Extracted the alert table row into `frontend/component/AlertRow.tsx`. It accepts a typed `InventoryAlert` prop and renders the product/store, stock badge, observation time, and detail links. AlertList maps results to keyed AlertRow components and retains query and pagination ownership. Existing markup, Tailwind classes, accessible link labels, and navigation behavior are preserved.

Verification: formatting, TypeScript, production build, 19 frontend tests, and 78 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Pagination component

Extracted the page indicator and previous/next controls into `frontend/component/Pagination.tsx`, with typed `page`, `pages`, and `onPageChange` props. AlertList retains URL search-parameter handling, keeping the component independent of routing and alert data. Styling and boundary disabling are preserved. Buttons explicitly use `type="button"` so the component can also be used inside a form without submitting it.

Verification: formatting, TypeScript, production build, 19 frontend tests, and 78 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Absolute frontend imports

Configured matching Vite/Vitest aliases and TypeScript paths: `@/component/*` resolves to `frontend/component/*`, and other `@/*` imports resolve to `frontend/src/*`. Migrated local frontend imports, including types, CSS, and test mocks, to these aliases. Components remain in their existing directories. This removes fragile parent-directory paths when extracting or moving components.

AGENTS.md now requires absolute alias imports for local frontend modules, including re-exports and dynamic imports. VS Code prefers non-relative auto-imports for TypeScript and JavaScript. External dependency imports keep their package names. Configuration filesystem paths, such as Vite's output directory, are not module imports and remain relative to their configuration context. README is unchanged.

Verification: no relative module paths remain in frontend TypeScript files. Formatting, TypeScript, production build, 19 frontend tests, and 78 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Agent conventions by application layer

Reorganized AGENTS.md into shared, backend, and frontend conventions. Shared rules cover scope, documentation, formatting, and required verification. Backend sections group Rails architecture, domain rules, database workflows, and backend skills. Frontend sections group TypeScript/import conventions, React Query guidance, frontend commands, and the React skill. Existing rules were retained, with dependency installation split by layer. Verified rule preservation and all skill links. Documentation-only change; application tests were not rerun, and README was not edited.

### AlertSummary component

Extracted the recorded-alert count and inventory-rule explanation into `frontend/component/AlertSummary.tsx`. AlertList supplies a typed `total` prop through an absolute alias import and retains query ownership. The component preserves responsive styling, locale-formatted counts (including zero), and the em-dash placeholder before data arrives.

Verification: formatting, TypeScript, production build, 19 frontend tests, and 78 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Refresh within AlertSummary

Moved the Refresh button into AlertSummary's recorded-alert card. The component accepts typed `onRefresh` and `isRefreshing` props; AlertList still owns the query, supplies refetch, and disables the action during fetching. Removed the now-unused wrapper from AlertList. The button sits beneath the count with responsive grid placement on small screens.

Verification: formatting, TypeScript, production build, 19 frontend tests, and 78 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Unseen alert count and detail visits

AlertSummary now displays **NEW ALERTS**, counting only the signed-in brand's alerts whose `seen_at` is null, across all pages. The inbox and pagination still include seen alerts. Seen state is shared by the brand because the demo has brand-level login, not individual user accounts. Existing alerts start unseen: earlier visits were not recorded and cannot be inferred.

The nullable `alerts.seen_at` timestamp records the first successful detail-visit acknowledgement. AlertDetail issues `PATCH /api/alerts/:id/seen` only after it has loaded an unseen alert. A conditional database update preserves the first timestamp for repeated or concurrent requests. Ordinary GET requests never mark alerts seen. Reconciliation leaves existing timestamps intact; newly inserted alerts have null timestamps. A deleted and recreated alert is a new unseen record.

The PATCH endpoint uses the existing AlertPolicy scope, takes no editable body fields, and returns `200 { "seen_at": "2026-10-19T15:00:00.000000Z" }`. Anonymous requests return 401; missing or other-brand IDs return 404; invalid CSRF tokens return 422. Submitted ownership/timestamp fields are ignored. List/detail alert JSON adds nullable `seen_at`; the list response adds numeric `unseen_count`, separate from unchanged `pagination.total`. Frontend TypeScript types reflect these additive fields.

React Query cancels an in-flight detail fetch before updating its cached timestamp and invalidates that brand's list caches so returning to the inbox refreshes the count. A mutation completing after a different brand logs in cannot recreate the previous brand's cache. Other active inboxes continue polling every five seconds. A failed acknowledgement exposes a retry action without hiding the detail; it does not falsely mark the alert as seen.

Migration `20261019160000_add_seen_at_to_alerts` was applied to development and the dedicated test database, and Rails regenerated the schema. Adding a nullable timestamp requires a brief table lock but no application backfill or row rewrite. Deploy the migration before code using the field. Existing brand indexes support the scoped count; no speculative index was added. Rolling back the migration drops seen history, so it is structurally reversible but not a recovery of that data. No tracking observations or alerts were recreated or deleted by this migration.

Verification: 21 frontend tests and 81 Rails tests (50,644 assertions) passed, along with formatting, TypeScript, production build, and Zeitwerk. Request tests cover scoped/global-across-pages counts, GET without mutation, repeat visits, persistence across login, new queued alerts, ownership isolation, missing records, and CSRF. Frontend tests cover visiting details, count refresh, keeping seen rows, avoiding a second acknowledgement on revisit, and retrying a failed acknowledgement. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Automatic refresh only

Removed the manual Refresh button and its unused callback/loading props from AlertSummary. The count now sits directly in the card layout. Five-second query polling and retry actions for failed requests remain available; the summary still counts only unseen alerts.

Verification: formatting, TypeScript, production build, 21 frontend tests, and 81 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### New badge in the inventory alert list

AlertRow now shows a teal “New” badge beside the product name when `seen_at` is null. Seen alerts keep their row and out-of-stock badge but no longer display “New”. The existing detail-visit regression test now verifies that the badge appears before viewing and disappears on return after the seen acknowledgement succeeds. No duplicate read/unread state is stored in the frontend.

The summary card was removed separately in the working tree; removed its stale import and updated the navigation regression test to assert the row badge instead of the removed summary. Verification: `bin/check` passed 81 Rails tests but initially exposed that stale import in frontend checks. After cleanup, all 21 frontend tests, TypeScript, the production build, and frontend formatting passed. The existing Brakeman unsupported-Rails warning remains unresolved.

### Inventory panel fills the viewport

Replaced the panel's percentage height (which had no definite parent height) with a growing flex layout. The workspace has a dynamic viewport minimum height; its body and main content pass remaining space to the alert panel below the header. Mobile uses an automatic navigation row followed by the growing workspace row. The header does not shrink, the existing outer padding remains, and long content can extend the page rather than being clipped. The table region grows to keep pagination at the panel bottom on short lists.

Verification: formatting, TypeScript, production build, 21 frontend tests, and 81 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning. No browser screenshot comparison was performed for this layout change.

### Named Tailwind breakpoints

Replaced arbitrary responsive thresholds throughout the frontend with standard Tailwind variants: `max-[760px]:` becomes `max-md:`, `max-[1100px]:` becomes `max-lg:`, and `min-[1500px]:` becomes `2xl:`. The default thresholds are 48rem, 64rem, and 96rem (768px, 1024px, and 1536px at the default font size), so layouts now transition at the framework's standard sizes. Max variants retain the existing below-breakpoint behavior; changing them directly to `md:` or `lg:` would invert that behavior. Added this convention to AGENTS.md's frontend section.

Verification: formatting, TypeScript, production build, 21 frontend tests, and 81 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning. Responsive transitions were not visually compared in a browser.

### Notification settings view

Added **Notification settings** at `/alerts/settings`, accessible from workspace navigation on desktop and mobile. Signed-in brands can add contacts and edit names, email addresses, phone numbers, and the two existing alert preferences. Reusable ContactForm and ContactCard components use TypeScript, absolute imports, named Tailwind breakpoints, and the teal/slate palette. The header identifies the current settings page.

The form requires a name and at least one delivery channel. Phone numbers use the existing international format (`+` followed by 8–15 digits, beginning with a nonzero digit). Separate checkboxes control out-of-stock and price-change alerts; both unchecked pauses notifications for that contact. Every provided channel receives the selected alerts. The page explicitly states that delivery remains simulated. No provider integration, contact backfill, deletion workflow, or schema migration was added. Existing jobs consume the saved setup without changes.

The API uses ContactPolicy scopes derived from the session brand, never a submitted brand ID:

- `GET /api/contacts?page=1` returns `contacts` plus `pagination` (`page`, `per_page`, `total`, `pages`). Results are newest ID first, 20 per page. Page must be an integer from 1 through 999999; invalid values return 422.
- `POST /api/contacts` accepts `{ "contact": { "name": "Inventory team", "email": "inventory@example.com", "phone": "+12025550123", "setup": { "alert_no_inventory": true, "alert_price_change": false } } }`. Success returns 201 with `{ "contact": { "id": 1, "name": "Inventory team", "email": "inventory@example.com", "phone": "+12025550123", "setup": { "alert_no_inventory": true, "alert_price_change": false } } }`.
- `PATCH /api/contacts/:id` accepts the same editable fields and returns 200 with the contact. Omitted fields retain their values; supplied setup must contain both boolean preferences. New contacts without setup use the existing default of both false. Blank email/phone values normalize to null.

Responses expose only ID, name, email, phone, and setup. Malformed input and validation failures return 422 with an error message; missing/cross-brand IDs return 404; unauthenticated requests return 401. Cookie-authenticated writes retain CSRF protection. Unpermitted ownership fields are ignored. The existing name-only login remains demo access without identity verification.

React Query contact caches include brand ID and page, use abortable reads, and invalidate after saves. Session changes and expired sessions cancel and remove both alert and contact caches. A save completing after a brand switch cannot populate the prior brand's cache. Forms preserve input on failure and disable duplicate submission while saving. Cancel closes the form; pagination closes an open editor. Lists use the shared Pagination component. Existing active alert queries still poll every five seconds; settings lists refresh after saves and through normal query refetch behavior.

Verification: 26 frontend tests and 87 Rails tests (50,723 assertions) passed, along with formatting, TypeScript, production build, and Zeitwerk. New request coverage checks tenant-scoped reads/writes, ignored ownership input, explicit response fields, invalid and malformed input, unchanged records on failure, pagination, missing/cross-brand IDs, and CSRF on both write endpoints. Frontend coverage exercises adding/editing both channels and preferences, save failure/cancel, list retry/pagination, navigation, and contact-cache clearing on session change/expiry. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning. No browser screenshot comparison was performed. README remains untouched by this feature.

### Contact edit dialogs and queue visibility

Editing a contact now navigates to `/alerts/settings/:contactId` while keeping settings behind a modal dialog. Direct links and refreshes load the contact through `GET /api/contacts/:id`. Success returns the same explicit `{ contact: ... }` fields as create/update; anonymous access returns 401 and missing/cross-brand IDs return 404 through ContactPolicy. Rails serves the frontend shell for the nested route. Closing, cancelling, or pressing Escape returns to `/alerts/settings`; saving closes the dialog after the existing mutation succeeds. Contact creation remains on the settings page.

The reusable `frontend/component/Dialog.tsx` uses native `showModal()` for top-layer presentation, keyboard focus containment, and background inertness, with a labelled title, explicit close button, Escape handling, viewport-bounded scrolling, and body-scroll restoration. ContactEditDialog composes it with contact loading/error/retry states and the existing ContactForm. jsdom tests shim native dialog open/close state; they do not verify real-browser focus trapping.

A discreet **Queue status ↗** link at the bottom of settings opens `/alerts/jobs`. It shows the signed-in brand's attributable, retained GoodJob jobs and polls every five seconds while active. Statuses are queued, scheduled, running, retrying, completed, and failed, with queue, attempts, scheduled time, finish time, and job ID. A completed delivery job means the job finished successfully; it does not guarantee a message was sent (delivery is simulated and jobs can intentionally skip unsubscribed contacts).

`GET /api/queued_jobs?page=1` returns `{ jobs: [{ id, job_class, queue, status, attempts, created_at, scheduled_at, finished_at }], pagination: { page, per_page, total, pages } }`. Pages contain up to 20 jobs ordered by creation time and ID descending. Page validation matches contacts (1–999999; invalid values return 422). Anonymous access returns 401. There are no retry/delete/run controls. The global GoodJob dashboard is not mounted.

QueuedJobPolicy maps known job argument shapes to the session brand's existing products, tracking observations, or alerts using database subqueries. Global reconciliation jobs, unknown job classes, and jobs with deleted sources are excluded because brand ownership cannot be established safely. Ownership follows current source records rather than creating a separate audit ledger. Payloads, recipients, and raw exception messages are never serialized. GoodJob advisory locks are included in the paginated query to avoid a per-job running-state query. Existing retention/cleanup rules determine how long completed jobs appear; this is not permanent job history. Large queue histories may require indexed tenant metadata later; no new schema or speculative indexes were introduced.

Job query keys include brand/page, reads accept cancellation, and session changes clear job caches along with contacts and alerts. The new view does not enqueue work or alter retry/delivery behavior. No dependencies, migrations, or README changes were needed.

Verification: 30 frontend tests and 92 Rails tests (50,752 assertions) passed. Formatting, TypeScript, production build, and Zeitwerk passed. Coverage includes dialog deep links and dismissal, missing contact handling, safe job serialization and brand isolation, status classification, pagination, queue navigation, five-second polling/unsubscribe behavior, and session-cache cleanup. Frontend tests/formatting were rerun after ensuring opening an edit dialog closes any open create form. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning. Native browser focus behavior was not visually tested.

### Current navigation highlight

Workspace links now use React Router NavLink. Tailwind styles its generated `aria-current="page"` attribute with a slate background and teal text, providing a persistent selected state and an accessible current-page indication. Inventory matches the inbox exactly; settings also matches nested contact-edit URLs. Unlike CSS `active:`, this remains highlighted after the click is released. Navigation tests check the inbox and nested settings selection.

Verification: formatting, TypeScript, production build, 30 frontend tests, and 92 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Frontend organization by page

Reorganized AlertList, AlertDetail, Login, NotificationSettings, and QueueStatus into `frontend/src/pages/<PageName>/`. Each directory contains its named page component, `components/`, `queries.ts`, and `utils.ts`. AlertRow/AlertEmptyState belong to AlertList; MarkAlertSeen to AlertDetail; LoginForm to Login; ContactForm/ContactCard/ContactEditDialog to NotificationSettings; and JobTable to QueueStatus. Helpers cover empty-state copy, detail error messages, login submission eligibility, contact payload conversion, and optional job timestamps without duplicating shared formatting.

Removed the monolithic `frontend/src/queries.ts` and the top-level contact/job query modules. Shared infrastructure now lives in `queryClient.ts`, `queryKeys.ts`, and `session/queries.ts`. Login's page query hook uses the shared session mutation so login/logout retain the same cache-clearing behavior. Shared infrastructure and UI components do not import page modules. Dialog, Pagination, Header, SideMenu, feedback components, transport, and API types remain shared. Query keys, polling intervals, cancellation, session isolation, routes, and response shapes are unchanged.

NotificationSettings tests are colocated with the page. Cross-page cache/session tests now live in `queryClient.test.tsx`; App tests retain end-to-end navigation coverage. All moved imports use the existing absolute aliases. AGENTS.md documents page ownership and shared-code boundaries for future changes. No dependencies, database changes, or README edits were needed.

Verification: formatting, TypeScript, production build, 30 frontend tests, and 92 Rails tests passed. Confirmed shared query/session infrastructure and shared UI components have no page-module imports, and obsolete query/component imports are gone. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Login introduction component

Extracted the login wordmark, introductory copy, and inventory-check tagline into the page-owned `LoginIntro` component. It returns a fragment so the existing section layout and responsive styling remain unchanged. `Login.tsx` retains both section containers and composes LoginIntro with LoginForm.

Verification: formatting, TypeScript, production build, 30 frontend tests, and 92 Rails tests passed. `bin/check` still fails only on the existing Brakeman unsupported-Rails warning.

### Shared status badge

Added `frontend/components/Badge.tsx` with typed error (red), info (sky), warning (amber), and success (teal) variants. Info is the default. It accepts span attributes, children, and an optional className for placement. Alert details use the warning variant for consecutive out-of-stock checks. Static Tailwind class mappings keep all variants discoverable by the build. The aligned TypeScript/Vite `@/ui/*` alias targets this requested directory while preserving existing component imports. No dependency or README changes were needed.

Verification: formatting, TypeScript, production build, 30 frontend tests, and 92 Rails tests passed. `bin/check` fails only on the existing Brakeman unsupported-Rails warning. No browser visual verification was performed.

### Alert type labels

Alert details now render a shared AlertTypeBadge from the API alert_type field rather than hard-coded trigger text. The component maps alert_no_inventory to an amber Inventory alert badge and alert_price_change to a sky Price change badge. GET /api/alerts and GET /api/alerts/:id add alert_type: "alert_no_inventory" to each serialized alert; existing fields, session authentication, brand scoping, and pagination are unchanged. This is an additive API field. TypeScript retains the inventory-only observation contract for currently persisted alerts.

Price-change notifications already exist, but they originate from TrackingEvent and do not create inbox Alert records. Supporting the price badge does not add those records, migrate data, or claim that price alerts appear in the inbox. Persisting and displaying price alerts requires a separate workflow change.

Verification: 32 frontend tests and 92 Rails tests (50,754 assertions) passed, including both badge labels and list/detail alert_type serialization. Formatting, TypeScript, production build, and Zeitwerk passed. bin/check still fails only on the existing Brakeman unsupported-Rails warning.

### Stored price-change alerts

Supersedes the earlier badge-only limitation: new price observations now queue Alerts::ReconcileJob in addition to the existing notification dispatch. Reconciliation stores alert_price_change records when consecutive dated, alert-eligible prices for the same store/product have different numeric amounts in the same currency. Chronology is event_time then id; first observations, unchanged amounts, undated records, and currency transitions do not alert. Price increases and decreases both qualify. Inventory checks never interrupt price comparisons. Reconciliation handles late arrivals by updating/removing affected pairs, while retaining seen_at on surviving alerts.

The migration adds alerts.alert_type with a PostgreSQL allowlist constraint and Rails inclusion validation, and tracking_events.price_alert_eligible. Existing alerts remain inventory alerts. Existing tracking rows receive false; only future inserts default to true. Earlier eligible prices may be baselines, but never trigger historical price inbox alerts. Nothing is deleted or backfilled by the migration. PostgreSQL constant defaults avoid a tracking-table rewrite; schema changes still need exclusive locks and checking the alerts constraint scans that table. A five-second lock timeout fails rather than waiting indefinitely. Apply the migration before deploying/restarting app and worker code; the down migration is explicitly irreversible because dropping the type would mislabel persisted price alerts. Development and test schemas were migrated through Rails, without seeds or resets.

Both categories reconcile under the existing transaction-level advisory lock and unique triggering_event_id constraint, so duplicate jobs do not duplicate alerts. Deletions are scoped to the category. GoodJob queues reconciliation in the observation transaction, with existing bounded deadlock/lock-timeout retries. The configured worker must be running. Per-pair reconciliation currently scans that pair's eligible history for each category; global import reconciliation scans all eligible history. No new speculative indexes were added; very long histories may need incremental reconciliation later.

Contact preferences affect notifications, not inbox creation: price alerts are stored even with no subscribed contacts. Existing price notification jobs still use tracking-event IDs and their existing per-contact/channel deduplication; reconciliation does not enqueue duplicate price notifications. Delivery is still simulated. Editing an existing observation does not enqueue reconciliation; record a new TrackingEvent for each new observed price. Bulk inserts need the existing explicit reconciliation call (the importer already queues it after its batches).

GET /api/alerts and GET /api/alerts/:id now return a discriminated alert shape: alert_no_inventory has observations with quantity; alert_price_change has observations with amount and currency. Existing brand scope, pagination, chronological ordering, five-second polling, unseen counts, and PATCH /api/alerts/:id/seen apply to both. Consumers must branch on alert_type instead of assuming quantity. Frontend types and rendering do so: the list shows the category badge, and price details show PREVIOUS PRICE and NEW PRICE. Shared inbox navigation is now labelled Alerts. README is unchanged.

For local trials, restart `npm run dev` and any open Rails console after migration. Create new dated price observations rather than updating the prior record:

```ruby
[10, 12].each_with_index do |amount, index|
  TrackingEvent.create!(store_id: 1, product_id: 1, event_type: :price_tracker,
                        event_time: Time.current + index.seconds,
                        value: { amount: amount, currency: "USD" })
end
```

Use existing store/product IDs for your brand. The worker stores the new comparison asynchronously and the inbox polls every five seconds. Existing recent prices can also cause an alert for the first example insertion if it changes their amount.

Verification: final bin/check passed formatting, TypeScript, production build, Zeitwerk, 33 frontend tests, and 99 Rails tests (50,815 assertions). Only the pre-existing unsupported-Rails Brakeman warning remains. Regression coverage includes increases/decreases, baseline/unchanged/currency exclusions, history flags, late/tied timestamps, category and store/product isolation, bulk writes, invalid-type database enforcement, rollback, repeat reconciliation, price notification deduplication, API brand isolation, read status, and list-to-detail price rendering. Migration completed locally and in the isolated test database; history exclusion is also exercised with explicit pre-feature flags in tests. No browser visual check or production-scale query benchmark was performed.

### Observation label lookup

Replaced the nested alert-detail label ternary with the page-owned observationTags map, keyed by AlertType and indexed by observation position. TypeScript requires both labels for each supported category; rendered labels remain unchanged.

Verification: formatting, TypeScript, production build, 33 frontend tests, and 99 Rails tests passed. bin/check still fails only on the existing Brakeman unsupported-Rails warning.

### Alert detail guard clauses

AlertDetail now returns early for errors and missing alert data, then renders the loaded view directly. This removes nested page-state ternaries while preserving error retry, loading, and read-status behavior. Hooks remain above the conditional returns.

Verification: formatting, TypeScript, production build, 33 frontend tests, and 99 Rails tests passed. bin/check still fails only on the existing Brakeman unsupported-Rails warning.

### Diagnosing a missing inbox alert

A new qualifying price observation had queued reconciliation correctly, but no GoodJob worker was registered; the job had neither performed_at nor finished_at. Starting `npm run jobs` processed the pending job successfully and stored the price-change alert. Use `npm run dev` to start Rails, Vite, and the worker together, or keep `npm run jobs` running when starting Rails/Vite separately. The inbox polls every five seconds while active. Verification used read-only job/alert queries after starting the worker; no application code or README changes were necessary.

### Retry failed queue jobs

Queue status now offers Retry for failed jobs. It disables retry controls while a request is pending, reports failures, refreshes the brand's job queries after the request, and continues five-second polling. Retrying re-enqueues work; a running GoodJob worker is still required. It does not run the task inside the HTTP request or promise success when the underlying failure persists.

POST /api/queued_jobs/:id/retry returns HTTP 202 with {"status":"accepted"}. It requires the current brand session and CSRF token. QueuedJobPolicy::Scope finds only attributable brand-owned jobs, and QueuedJobPolicy#retry? authorizes the action. Anonymous requests return 401; missing, other-brand, global, or unrecognized jobs remain hidden with 404. Nonfailed/running jobs and stale duplicate requests return 409. Unavailable serialized job data returns a safe 409; an incompatible adapter returns 503. Raw exception text and arguments are not exposed. Existing list responses are unchanged.

The endpoint uses GoodJob 4.22.1's retry_job operation, which locks, reloads, checks the failed state, and re-enqueues the existing job with its original arguments. Execution history and counters are preserved using GoodJob's behavior; this does not reset bounded application retry counters or create a parallel copy. Existing alert and delivery idempotency protections still apply. No migrations or new dependencies were needed. Two navigation assertions were updated to recognize the current Back to all alerts link text without reverting the UI changes.

Verification: final bin/check passed formatting, TypeScript, production build, Zeitwerk, 35 frontend tests, and 102 Rails tests (50,837 assertions). Request tests exercise actual GoodJob re-enqueue, duplicate requests, nonfailed states, anonymous/cross-brand/global/missing IDs, and CSRF; UI tests cover pending controls, request token, refreshed status, and retry errors. Test-adapter overrides are restored so later job tests remain isolated. Only the existing Brakeman unsupported-Rails warning remains. No real failed job was retried or external notification sent during verification.

### Queue status sidebar navigation

Moved Queue status from the Notification settings footer into the shared workspace sidebar. It uses NavLink and the same active-page styling as other destinations, making it available throughout the workspace. Navigation coverage verifies the link is in the sidebar, appears only once, and highlights the queue view.

Verification: bin/check passed TypeScript, production build, formatting, Zeitwerk, and 102 Rails tests. The navigation test initially looked for the sidebar before session loading completed; after waiting for the navigation element, all 35 frontend tests passed on rerun. The existing Brakeman unsupported-Rails warning remains unresolved.

### Notification settings guard clauses

Removed the nested list-rendering ternaries from NotificationSettings. The page composes a page-owned ContactList that owns its existing React Query read and returns early for error, loading, and empty results. Add-contact and edit-dialog controls remain mounted independently of list failures. Existing retry, query keys, pagination (including empty pages), and mutation invalidation behavior are preserved.

Verification: formatting, TypeScript, production build, 35 frontend tests, and 102 Rails tests passed. bin/check fails only on the existing Brakeman unsupported-Rails warning.

### Dialog footer actions

Dialog accepts an optional ReactNode footer, rendered in a separated footer area below its body. Contact editing places Save contact and Cancel there. ContactForm exposes a renderLayout callback with form and actions so its draft, validation, mutation, and pending state stay together; the inline add-contact form retains its default layout. The external submit button targets a unique form ID using the native form attribute, preserving HTML validation and normal submission. Cancel and Save are disabled during submission, and rejected saves retain input and show the existing error. Loading/error dialogs use early returns without save controls. Escape coverage targets the currently loaded dialog, since loading and editable dialog content have separate render branches.

Verification: formatting, TypeScript, production build, 36 frontend tests, and 102 Rails tests passed. Coverage includes footer placement, external-button submission and HTML validation, disabled controls during save, retained input on failure, cancellation, and Escape dismissal. bin/check fails only on the existing Brakeman unsupported-Rails warning. No real-browser focus inspection was performed.

### Contact creation dialog and keyword search

Add contact now opens a page-owned ContactCreateDialog using the shared Dialog footer and ContactForm. Both new and existing contacts show Out-of-stock alerts and Price-change alerts preferences; new contacts start with both off. Save and Cancel remain footer actions with native form validation and pending controls. Creation closes the dialog after success, clears the search, and returns to page one so the new contact can be found. Cancellation discards the unsaved draft. The edit dialog's existing URL behavior is unchanged.

Search contacts filters name, email, or phone using one case-insensitive literal substring. It waits 500 ms after the last input change before applying a trimmed keyword and resetting pagination together. Timers are cleared on changes/unmount. React Query includes brand, page, and keyword in the cache key and passes cancellation signals; saving invalidates every search for that brand. Clearing the field restores the unfiltered list. A search with no matches shows its own empty message, retaining pagination controls where applicable.

GET /api/contacts?page=1&q=alice searches inside ContactPolicy's current-brand scope before counting and paginating. q is optional; blank/whitespace means no filter. Arrays/objects and strings over 200 characters return 422. SQL uses bound values and escapes LIKE wildcard characters, so percent and underscore are literal. Matching remains newest ID first with 20 records per page; response shape, authentication, and contact writes are unchanged. Phone search matches the stored E.164 text; it does not normalize formatted phone input. No dependency, migration, or README changes were needed. Substring searches can scan a brand's contacts; no speculative index was added for this small contact directory.

Verification: formatting, TypeScript, production build, 38 frontend tests, and 105 Rails tests (50,859 assertions) passed. New coverage verifies creation-dialog preferences/footer, debounce timing and replacement of intermediate keywords, page reset and clearing, no-match text, case-insensitive name/email/phone matching, brand isolation, literal wildcard handling, malformed input, and filtered pagination. bin/check fails only on the existing Brakeman unsupported-Rails warning. No browser visual check or production-scale search benchmark was performed.

### Queue table scrolling

The queue route now constrains the workspace to the dynamic viewport height. Flex ancestors allow the queue panel to shrink; its heading/status area and pagination remain outside the scroll container. JobTable uses a keyboard-focusable scroll region with overflow-y-auto, horizontal overflow for narrow screens, and sticky column headings. Other routes retain their document-height layout. Pagination remains visible when multiple pages exist.

Verification: bin/check passed formatting, TypeScript, production build, Zeitwerk, and 105 Rails tests. Frontend checks identified the repositioned contact-search input missing its accessible name; adding aria-label preserved its visual layout and all 38 frontend tests passed on rerun. The existing unsupported-Rails Brakeman warning remains. Scroll geometry was not verified in a real browser.

### International phone input mask

The shared contact form now masks phone input while typing and pasting in both create and edit dialogs. It adds a leading plus, keeps ASCII digits only, excludes leading zeroes from the country-code position, and caps the number at 15 digits. Pasted spaces, parentheses, and dashes are removed. Empty input remains allowed when email supplies the contact channel; a partial plus/short number cannot be submitted because the existing 8–15-digit HTML pattern and Rails/PostgreSQL validations remain in place. The mask preserves the caret for edits within a number, and autocomplete/mobile input hints identify the field as a phone number.

This follows the existing international storage format rather than assuming a US country code or inserting country-specific separators. Users must include their country code. It enforces syntax only; it does not verify that a number exists. No masking library or backend contract changes were needed.

Verification: formatting, TypeScript, production build, 39 frontend tests, and 105 Rails tests passed. New UI coverage checks typed letters, automatic plus prefix, formatted paste, clearing, length limits, leading-zero rejection, insertion/backspace caret behavior, incomplete-number validation, and normalized submission. bin/check fails only on the existing Brakeman unsupported-Rails warning.

### Queue rendering guard clauses

QueueStatus now composes a page-owned QueueContent component with early returns for unavailable, loading, and empty data instead of nested rendering ternaries. The existing query/mutation feedback stays in the fixed header, cached rows remain available after a refetch error, and table scrolling and pagination positioning are preserved. JobsResponse names the existing response shape without changing the API.

Verification: formatting, TypeScript, production build, 39 frontend tests, and 105 Rails tests passed. bin/check fails only on the existing Brakeman unsupported-Rails warning.

### Alerts inbox table scrolling

Applied the queue viewport-height layout to the alerts inbox route. The inbox heading and pagination do not shrink, while the keyboard-focusable table region uses overflow-y-auto and sticky column headings. Horizontal scrolling remains available on narrow screens. Alert details and settings retain their document-height layout.

Verification: formatting, TypeScript, production build, 39 frontend tests, and 105 Rails tests passed. bin/check fails only on the existing Brakeman unsupported-Rails warning. Scroll geometry was not inspected in a real browser.

### Brand-scoped TrackingEvents page

Added TrackingEvents under frontend/src/pages/TrackingEvents with page-owned components, queries, utilities, and tests. The sidebar opens /alerts/tracking-events, with selected navigation and header title. The page displays product, store address, observation category, quantity/stock status or amount/currency, and observation time. It uses early-return loading/error/empty states and the shared pagination. Rows scroll within the viewport while column headers and pagination stay visible. This is read-only; it does not create alerts or alter observations.

GET /api/tracking_events?page=1 uses TrackingEventPolicy::Scope to restrict product_id to the current session brand's products. Stores are represented only through those scoped observations. Sharing a store with another brand does not permit viewing the other brand's products/events; supplied brand_id parameters cannot override the session. Anonymous requests return 401. Historical events remain visible, including undated observations, independently of alert eligibility flags.

The endpoint returns {tracking_events: [{id, event_type, event_time, value, product: {id, name}, store: {id, address}}], pagination: {page, per_page, total, pages}}. Inventory value contains quantity; price value contains amount and currency. Other payload keys and internal eligibility flags are excluded. Dates are nullable ISO 8601; undated entries show Undated. Pagination is 20 rows per page, ordered by event_time DESC NULLS LAST and id DESC, with page numbers 1–999999 (422 otherwise). An out-of-range valid page returns an empty array and the same scoped total. Associations are eager-loaded only for the page, avoiding per-row product/store queries.

React Query keys include brand and page, requests accept cancellation, and tracking-event caches are cancelled/removed on session changes and expiration. Normal query refresh/staleness behavior applies; there is no five-second polling of the large history. A read-only EXPLAIN on the local million-row dataset showed a parallel sequential scan/hash join and sort for the scoped history order. Pagination bounds response/rendering memory, but exact counts, ordering, and deep OFFSET pages can remain expensive; no latency improvement is claimed and no speculative index or schema change was made. Consider measured index/keyset work if this view becomes a production workload.

The existing Rails frontend shell route supports direct links to the page. No dependencies, migrations, or README changes were required.

Verification: 108 Rails tests (50,884 assertions) and 42 frontend tests passed. TypeScript initially caught missing pagination in two cache test fixtures; after correcting the fixtures, production build/typecheck and the frontend suite passed on rerun. Formatting and Zeitwerk passed. New coverage checks shared-store brand isolation, ignored ownership parameters, anonymous access, safe inventory/price serialization, undated/tied-time ordering, page limits, navigation, empty/error/retry states, and session-cache cleanup. The existing Brakeman unsupported-Rails warning remains unresolved. No real-browser layout verification or timed production-scale benchmark was performed.

### Tracking events: sortable observation date

The Observed column now has an accessible sort button with a direction arrow. Newest first remains the default; clicking switches to oldest first and resets to page 1. The URL stores `order=asc|desc`, pagination preserves it, and React Query caches each direction separately.

The API applies sorting before pagination using an allowlist of SQL order clauses; unsupported orders return 422. Equal timestamps use the ID in the same direction, and undated observations remain last in both directions. The existing brand policy scope is preserved. This changes ordering, not the history query's existing count/offset performance limitations.

Regression coverage checks both directions, tied timestamps, undated rows, pagination, brand isolation, invalid order values, and toggling from page 3.

Verification: `bin/check` passed formatting, syntax, all 43 frontend tests, TypeScript/build, Zeitwerk, and all 109 Rails tests (50,890 assertions). Its only failing gate remains Brakeman's existing unsupported Rails 7.1.6 warning. The endpoint qualifies its sort columns for joined policy scopes and explicitly selects full event rows/counts all rows so a restricted policy projection does not break serialization or pagination.

### Tracking event policy: product join

Changed the brand filter to `@scope.joins(:product).where(products: { brand_id: @brand.id })`, following the existing product association instead of a product-ID subquery. The scope still uses the session brand, returns no records without a brand, and excludes other brands' observations even at shared stores. The belongs-to join does not multiply event rows. Existing endpoint tests cover brand isolation, serialization, sorting, and pagination; this change does not claim a measured performance improvement.

Verification: `bin/check` passed formatting, syntax, 43 frontend tests, TypeScript/build, Zeitwerk, and 109 Rails tests (50,890 assertions). The existing Brakeman warning about unsupported Rails 7.1.6 remains the only failing check.

### Sidebar owns logout

`SideMenu` now owns the shared session logout mutation, pending button state, and error feedback. `App` no longer passes logout props or manages logout errors. The button disables while signing out, supports retry after failure, and uses readable colors on the dark sidebar. Successful logout retains the existing session cache cleanup and returns to login. The removed Header component's stale App reference was also removed.

Verification: added a sidebar integration test covering pending state, DELETE request, failure/retry, and return to login. `bin/check` passed 109 Rails tests (50,890 assertions), syntax, and Zeitwerk. Its frontend tests/build initially caught the stale reference to the concurrently removed Header; after fixing it, all 44 frontend tests, TypeScript/build, and formatting checks passed on rerun. The existing Brakeman unsupported Rails 7.1.6 warning remains.

### Reusable informational messages

Added `frontend/components/InfoMessage.tsx` with just `message` and `variant` props. Its variants match Badge: `error` (red/cross), `info` (sky/information), `warning` (amber/exclamation), and `success` (teal/check). Each includes a tinted background and decorative SVG icon; errors use the alert role and other messages use status. The queue's empty state now uses `<InfoMessage message="No retained jobs for this brand." variant="info" />`. No new dependencies were needed.

Verification: `bin/check` passed formatting, syntax, all 44 frontend tests, TypeScript/build, Zeitwerk, and all 109 Rails tests. The only failing gate remains the existing Brakeman warning about unsupported Rails 7.1.6.

### Centered InfoMessage empty state

Updated InfoMessage to match the alerts empty-state layout: automatic margins center it in the available flex space, with the icon above centered text. The variant colors now tint the circular icon background and border, preserving the `message`/`variant` API. The queue empty state inherits this presentation without additional page-specific styling.

Verification: `bin/check` passed formatting, syntax, 44 frontend tests, TypeScript/build, Zeitwerk, and 109 Rails tests. Only the existing Brakeman unsupported Rails 7.1.6 warning remains. Visual layout was matched against the alerts component; no browser screenshot verification was performed.

### Optional InfoMessage title

InfoMessage accepts `title?: string`. A supplied title appears between the icon and message using the alerts empty-state heading style. Omitting it keeps the existing layout. Example: `<InfoMessage title="No jobs yet" message="No retained jobs for this brand." variant="info" />`.

Verification: `bin/check` passed formatting, syntax, 44 frontend tests, TypeScript/build, Zeitwerk, and 109 Rails tests. The existing Brakeman unsupported Rails 7.1.6 warning is the only failing gate.

### AlertList early-return rendering

Moved the page's query-driven content into its own `AlertListContent` component. It returns early for errors, loading, and empty collections before rendering the table and pagination. AlertList keeps the shared section and heading visible in every state, preserving the scrolling layout, five-second polling, retry, and URL pagination behavior without nested render ternaries. Added coverage for loading-to-error-to-retry-to-empty transitions; existing tests cover populated lists and pagination.

Verification: `bin/check` passed formatting, syntax, all 45 frontend tests, TypeScript/build, Zeitwerk, and all 109 Rails tests. Only the existing Brakeman unsupported Rails 7.1.6 warning remains.

### Notification settings table layout

Replaced contact cards with page-owned `ContactTable` and `ContactRow` components, matching queue status: sticky column headers, scrollable rows, and pagination outside the scrolling area. Columns show name, email, phone, alert preferences, and the existing edit action. Settings routes (including edit dialogs) use the viewport-height layout so pagination remains visible. Search keeps its 500 ms debounce, and create/edit dialogs retain their existing behavior. Empty states use InfoMessage; pagination is shown even for a single page. Removed the unused ContactCard component.

Extended the existing contact create/edit test to verify table columns, channel values in the same row, and pagination outside the table. Existing tests continue to exercise searching, paging, and dialogs.

Verification: `bin/check` passed formatting, syntax, 45 frontend tests, TypeScript/build, Zeitwerk, and 109 Rails tests. The existing Brakeman unsupported Rails 7.1.6 warning remains the only failing gate. Browser screenshot verification was not performed.

### Unified error presentation

Replaced every ErrorMessage use with `<InfoMessage message={...} variant="error" />` across session, login/logout, alerts, tracking events, contacts, and queue status. Existing retry controls remain alongside their messages; InfoMessage retains its simple string message API and error alert role. Removed the unused ErrorMessage export and ReactNode import from Feedback. The shared Mark component remains unchanged. No ErrorMessage references remain in the frontend.

Verification: `bin/check` passed formatting, syntax, all 45 frontend tests (including error/retry flows), TypeScript/build, Zeitwerk, and all 109 Rails tests. The existing Brakeman unsupported Rails 7.1.6 warning remains the only failing gate.

### Remove duplicate legacy AlertList implementation

A second file at `frontend/src/pages/AlertList.tsx` still contained the old ErrorMessage rendering and obsolete imports. The application imports the organized page at `pages/AlertList/AlertList.tsx`. Replaced the legacy implementation with a re-export of that current component so either import path uses the same early-return content and InfoMessage error presentation. A frontend-wide search now finds no ErrorMessage references.

Verification: `bin/check` passed formatting, syntax, 45 frontend tests, TypeScript/build, Zeitwerk, and 109 Rails tests. The existing Brakeman unsupported Rails 7.1.6 warning remains the only failing gate.
