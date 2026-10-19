---
name: api-contracts
description: Define or change public API request/response schemas, OpenAPI descriptions, compatibility rules, versions, or deprecation behavior. Use when endpoint behavior affects clients or when API documentation is requested.
---

# API contracts

Read `AGENTS.md`, routes, request tests, and any existing API documentation. This repository has no established OpenAPI document; do not present one as already implemented or migrate HTML routes to JSON merely to document them.

1. Identify consumers and the actual implemented request/response behavior. Reuse an existing specification location and OpenAPI version; if introducing the first spec, choose a supported version and document its validation command/tool rather than claiming an unvalidated schema is enforced.
2. Describe paths/methods, authentication requirements, path/query/body fields, required versus optional values, content types, pagination, success/error responses, and concrete examples. Distinguish absent fields from explicit null and numeric values from numeric strings.
3. Keep tracking-event schemas category-specific: inventory has a whole-number quantity, price has amount and currency. Match model and database constraints, including quantity values at or below zero, and reject the redundant inventory `present` key. Do not document obsolete payloads from historical notes as current.
4. Review compatibility for field removal/renaming, newly required fields, type changes, enum expansion, status changes, ordering, and pagination defaults. Consider strict clients; an additive change is not always harmless. Preserve compatibility or propose an explicit migration/versioning plan.
5. For deprecations, document the replacement and agreed timeline; do not invent a retirement date or remove support without a requested decision. Keep old/new examples clear during transitions.
6. Tie request tests to documented examples and schemas when tooling exists. If adding validation tooling, keep it small and reproducible and add it to automated checks. Verify both implementation and spec, including error cases; documentation alone does not enforce a contract.

Summarize the consumer-visible change, compatibility impact, migration path if needed, and what was actually validated. Use `rails-api-development` for endpoint implementation and `rails-api-testing` for request coverage.
