# Working in RetailTestProject

## Shared conventions

- Follow existing patterns and keep changes scoped to the request. Inspect the working tree first and preserve unrelated edits.
- Preserve `README.md` unchanged unless the user explicitly requests an edit to it. This is a demonstration project: record implementation changes, rationale, usage updates, tradeoffs, and verification in `IMPROVEMENTS.md`. Earlier entries can be superseded; verify current behavior against code, tests, and the latest entries.
- Apply consistent Ruby and frontend formatting with `npm run format`; verify it with `npm run format:check`. RuboCop is configured for layout only; Prettier handles React/JS/CSS/frontend HTML. Keep README excluded from formatting.
- Before handing off code changes, run `bin/check`: syntax lint, Brakeman, test database preparation, Zeitwerk validation, and the Minitest suite. Report actual results and any blocked checks; do not weaken checks merely to pass.
- Add tests for changed behavior and regressions, particularly direct/bulk writes, ordering, and transaction failures. Pure documentation or cosmetic edits do not need artificial tests.
- Put updated examples and commands in `IMPROVEMENTS.md`, not `README.md`. Explain the problem, the solution, why it was chosen, tests run, and remaining limitations so reviewers can assess the improvement work.

Select skills matching the task. Read their `SKILL.md` files and only the references needed; do not load every skill for every edit. Add dependencies or change architecture only when the requested work needs them.

## Backend conventions

### Architecture

- Ruby version: `.ruby-version`; Rails and other dependencies: `Gemfile.lock`.
- This is a Rails application backed by PostgreSQL, with Minitest tests under `test/`.
- Keep controllers focused on HTTP concerns; tracking workflows live in `app/services/tracking_events/`, with terminal entry points in `lib/tasks/`.

### Domain and processing rules

- Inventory observations use `value: { quantity: N }`: a finite whole number. Greater than zero means in stock; zero or negative means out of stock. Do not reintroduce the JSON `present` key or use the legacy `inventory_present` column as the source of truth.
- Price observations require a nonnegative numeric amount and a three-letter uppercase currency code. Inventory and price observations are independent.
- Stored alerts distinguish `alert_no_inventory` and `alert_price_change`. Price alerts compare adjacent dated, alert-eligible price events for the same store/product by `event_time, id`; only different amounts in the same currency qualify. Only triggers with `price_alert_eligible: true` enter the inbox; pre-feature prices can be baselines but must not be backfilled. Keep reconciliation scoped by alert type so inventory and price alerts cannot invalidate each other.
- Current observations are selected separately by store, product, and category, ordered by `event_time DESC, id DESC`, excluding undated events. Insertion order alone is not observation order.
- Payload rules must be enforced by both Rails validations and PostgreSQL constraints: `insert_all!` bypasses model validations and callbacks.
- Alert processing uses GoodJob in external mode, sharing the application PostgreSQL database. Enqueue alert and simulated-notification work in the same transaction as its source writes so workers see only committed work. Preserve historical `alert_eligible: false` exclusions. `npm run dev` also starts the job worker.
- The CSV importer streams bounded batches inside one transaction. Missing references and detected invalid row values raise an error with a CSV record number and roll back the entire import. Preserve that behavior and staged-versus-committed progress semantics.
- Use the shared `PASTEL` formatter for terminal styling. The watcher polls current observations; it is not a durable event-delivery system.

### Development and checks

- Install backend dependencies with `bundle install`.
- Test connection settings belong in ignored `.env.test.local`: `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, and optionally `DB_TEST_NAME`. Never print or commit secrets. `.env.local` is not loaded in tests.
- Prepare the dedicated test database without demo seeds with `RAILS_ENV=test bin/rails db:create db:migrate`. The role must own it and have `CREATEDB`. Never point test configuration at development or production data.
- Run focused tests while iterating, for example `bin/rails test test/models/tracking_event_test.rb`.
- Use new migrations for schema changes and regenerate `db/schema.rb` through Rails. Examine data conversion, locks, and reversibility before executing migrations. Do not automatically roll back a failed migration; some existing migrations are intentionally irreversible.
- `db/seeds.rb` deletes existing records. Do not use seeding or database resets as routine verification. Use isolated test data.

### Backend skills

Endpoint work can combine development, security, and testing guidance. Use focused repository skills for their workflows and `rails-expert` for broader Rails/Hotwire guidance.

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

## Frontend conventions

### Architecture and imports

- The React/Vite frontend uses strict TypeScript under `frontend/src/`. Use `.ts`/`.tsx` for frontend changes and keep API response types in `frontend/src/types.ts` aligned with Rails responses. Run `npm run typecheck`; production builds enforce this check too.
- Always use absolute alias imports for local frontend modules; never use `./` or `../` imports. Use `@/component/Dialog` for shared components in `frontend/component/`, and `@/api`, `@/pages/AlertList/queries`, `@/components/Feedback`, etc. for `frontend/src/`. This includes type imports, stylesheet imports, re-exports, dynamic imports, and test mocks. Keep Vite/Vitest aliases and TypeScript paths aligned. External packages retain their package names; configuration filesystem paths are not module imports.

- Use `@/ui/Badge` for the shared Badge in `frontend/components/`; the `@/ui/*` alias maps to this directory without conflicting with existing `@/components/Feedback` imports.

- Use Tailwind named responsive variants (`md:`, `lg:`, `max-md:`, `max-lg:`, `2xl:`) with the standard theme breakpoints instead of arbitrary pixel breakpoints such as `max-[760px]:`. Use `max-*` when styling below a breakpoint; unprefixed `md:`/`lg:` apply at and above it.

- Organize each page under `frontend/src/pages/<PageName>/`, with `<PageName>.tsx`, page-owned `components/`, `queries.ts`, and `utils.ts`. Keep page-specific queries, mutations, presentation helpers, and components inside that directory; use absolute imports such as `@/pages/AlertList/components/AlertRow`. Colocate page-specific tests there too.
- Keep reusable layout/UI components (Dialog, Pagination, Header, SideMenu), API transport/types, session handling, and query-client/cache-key infrastructure shared. Shared code must not depend on page modules. Do not duplicate shared logic to fill a page folder.

### Data fetching and React guidance

For the React frontend, apply the Vercel React guidance to this Vite application. Use TanStack React Query for server data and mutations; the skill’s SWR example illustrates caching/deduplication, not a requirement to add a second query library. Keep brand identity in alert query keys and cancel/remove alert caches on session changes. Do not introduce Next.js-specific APIs into this application.

### Development and checks

- Install frontend dependencies with `npm ci`.
- Run `npm run typecheck`, `npm test`, and `npm run build` for frontend verification. The shared `bin/check` requirement still applies before handing off code changes.
- Use `npm run format:web` and `npm run format:web:check` for frontend-only formatting checks; the shared formatting commands cover both layers.

### Frontend skills

| Skill | Activate for |
| --- | --- |
| [vercel-react-best-practices](.agents/skills/vercel-react-best-practices/SKILL.md) | React/TypeScript components, client data fetching, and frontend performance |
