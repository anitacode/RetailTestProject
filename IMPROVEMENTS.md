# Repository Improvement Log

This document records changes made during the repository setup and improvement work, why they were made, and how they were verified. Local machine setup is distinguished from changes tracked in Git. Secret values are intentionally omitted.

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
