---
name: rails-api-testing
description: Add behavioral tests while implementing Rails features or fixing bugs, especially request-level coverage for changed endpoints, validation, authentication, authorization, and missing records. Follow the repository's existing test framework.
---

# Rails API testing

Read `AGENTS.md`, `test/test_helper.rb`, and adjacent tests. This repository uses Minitest: use `ActionDispatch::IntegrationTest` under `test/integration/` for requests, and the existing model/service test patterns for non-HTTP behavior. Do not add RSpec, FactoryBot, or a coverage tool solely to follow upstream examples.

1. Translate the changed behavior or regression into observable assertions. For endpoint work, exercise actual routes and middleware rather than invoking controller methods directly.
2. Cover a successful request, invalid input, and a missing record. Where access controls apply, cover unauthenticated and authenticated-but-forbidden callers as distinct cases, including access to another user's/business's records. For deliberately public endpoints, assert public access instead of inventing expected 401/403 responses.
3. Check status, content type, response fields, meaningful values, and persistence effects. Failed writes should leave no partial data or unintended jobs. Assert sensitive fields are absent and privileged submitted parameters cannot change protected state.
4. Cover pagination limits, ordering, and boundaries for changed collection endpoints. Check relevant unknown IDs, malformed bodies, nested parameters, and content negotiation without duplicating every implementation detail.
5. Use controlled clocks and isolated database records. Existing tracking tests disable fixture tables and use a single worker; follow that pattern where shared fixtures would interfere. Never use production records or the destructive demo seed task.
6. For payload constraints, test both normal model writes and bulk/direct writes with savepoints around expected PostgreSQL errors. For imports, test rollback after an earlier successful batch. For external calls, stub the network at a deliberate boundary and test failures as well as success.
7. Run the affected file with `bin/rails test path/to/test.rb`, then `bin/check` for code changes. Report commands and actual outcomes; distinguish a failing security gate from test failures.

For model-only or service-only fixes, test at that layer rather than creating unrelated HTTP endpoints. Avoid tests for prose or simple cosmetic changes unless behavior is at risk.
