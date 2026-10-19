# Working in RetailTestProject

## Project and architecture

- Ruby version: `.ruby-version`; Rails and other dependencies: `Gemfile.lock`.
- This is a Rails application backed by PostgreSQL, with Minitest tests under `test/`.
- Keep controllers focused on HTTP concerns; tracking workflows live in `app/services/tracking_events/`, with terminal entry points in `lib/tasks/`.
- Follow existing patterns and keep changes scoped to the request. Inspect the working tree first and preserve unrelated edits.
- `README.md` describes current behavior. `IMPROVEMENTS.md` is historical and may describe superseded behavior; verify against code and tests.

## Domain rules

- Inventory observations use `value: { quantity: N }`: a finite whole number. Greater than zero means in stock; zero or negative means out of stock. Do not reintroduce the JSON `present` key or use the legacy `inventory_present` column as the source of truth.
- Price observations require a nonnegative numeric amount and a three-letter uppercase currency code. Inventory and price observations are independent.
- Current observations are selected separately by store, product, and category, ordered by `event_time DESC, id DESC`, excluding undated events. Insertion order alone is not observation order.
- Payload rules must be enforced by both Rails validations and PostgreSQL constraints: `insert_all!` bypasses model validations and callbacks.
- The CSV importer streams bounded batches inside one transaction. Preserve rollback and progress semantics. Read its tests before changing missing-reference behavior; do not infer it from outdated documentation.
- Use the shared `PASTEL` formatter for terminal styling. The watcher polls current observations; it is not a durable event-delivery system.

## Development and checks

- Install dependencies with `bundle install`.
- Test connection settings belong in ignored `.env.test.local`: `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, and optionally `DB_TEST_NAME`. Never print or commit secrets. `.env.local` is not loaded in tests.
- Prepare the dedicated test database without demo seeds with `RAILS_ENV=test bin/rails db:create db:migrate`. The role must own it and have `CREATEDB`. Never point test configuration at development or production data.
- Run focused tests while iterating, for example `bin/rails test test/models/tracking_event_test.rb`.
- Before handing off code changes, run `bin/check`: syntax lint, Brakeman, test database preparation, Zeitwerk validation, and the Minitest suite. Report actual results and any blocked checks; do not weaken checks merely to pass.
- Add tests for changed behavior and regressions, particularly direct/bulk writes, ordering, and transaction failures. Pure documentation or cosmetic edits do not need artificial tests.
- Use new migrations for schema changes and regenerate `db/schema.rb` through Rails. Examine data conversion, locks, and reversibility before executing migrations. Do not automatically roll back a failed migration; some existing migrations are intentionally irreversible.
- `db/seeds.rb` deletes existing records. Do not use seeding or database resets as routine verification. Use isolated test data.
- Update relevant README examples when behavior or commands change. Summarize what changed, validation, and remaining limitations in the handoff.

## Task-specific skills

Select skills matching the work below. Read their `SKILL.md` files and only the references needed for the task; do not load every skill for every Rails edit. Endpoint work can combine development, security, and testing guidance. Use focused repository skills for their workflows and `rails-expert` for broader Rails/Hotwire guidance.

| Skill | Activate for |
| --- | --- |
| [rails-expert](.agents/skills/rails-expert/SKILL.md) | General Rails implementation and Hotwire |
| [rails-api-development](.agents/skills/rails-api-development/SKILL.md) | Adding or changing endpoints, parameters, responses, pagination |
| [rails-api-security](.agents/skills/rails-api-security/SKILL.md) | Endpoint access, authentication, authorization, data exposure |
| [rails-api-testing](.agents/skills/rails-api-testing/SKILL.md) | Feature/bug regression tests and request coverage |
| [rails-database-migrations](.agents/skills/rails-database-migrations/SKILL.md) | Tables, indexes, constraints, enums, data conversions |
| [rails-query-performance](.agents/skills/rails-query-performance/SKILL.md) | Queries, collection endpoints, N+1 issues, batching |
| [rails-background-jobs](.agents/skills/rails-background-jobs/SKILL.md) | Async work, retries, idempotency, enqueue/commit timing |
| [external-api-integrations](.agents/skills/external-api-integrations/SKILL.md) | API clients, webhooks, timeouts, duplicate delivery |
| [api-contracts](.agents/skills/api-contracts/SKILL.md) | OpenAPI, request/response schemas, compatibility, deprecation |
| [rails-bulk-imports](.agents/skills/rails-bulk-imports/SKILL.md) | Streaming imports, bulk writes, duplicates, resume design |

Repository conventions take precedence over generic examples in that skill: use Minitest rather than adding RSpec, use the checks above rather than assuming RuboCop exists, and do not install Sidekiq or add a coverage threshold just because the upstream skill mentions them. Choose indexes based on actual query patterns and plans, not every referenced column. Add dependencies or change architecture only when the requested work needs them.
