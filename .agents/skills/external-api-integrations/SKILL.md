---
name: external-api-integrations
description: Add or modify outbound API clients or inbound webhooks, including timeouts, retry policy, signature verification, duplicate delivery, and integration tests. Applies to real retailer data integrations as well as other external services.
---

# External API integrations

Read `AGENTS.md`, existing clients/configuration, and the provider's official API documentation. This app's watcher only observes local database state; adding a live retailer requires an explicit data ingestion integration.

1. Establish endpoint/version, authentication, rate limits, pagination, payload schema, and error contract. Keep credentials in existing secret configuration; do not commit example secrets or put tokens in logs.
2. Isolate provider communication behind a small client/service. Set connection and response/read timeouts and bound total attempts. Retry documented transient failures with backoff/jitter and bounded `Retry-After` handling; do not blindly retry non-idempotent writes after an ambiguous timeout.
3. Use stable provider idempotency keys where supported. Record external event/operation identifiers with a database uniqueness constraint when duplicates must be suppressed. Consider crashes between an external side effect and local recording, not just repeated successful calls.
4. Validate and normalize responses before creating domain events. Preserve provider observation time separately from arrival time. Map inventory to quantity and prices to amount/currency; do not invent quantities or prices when the provider omits them.
5. For webhooks, verify the provider's signature against the raw body using its documented algorithm/SDK, enforce freshness/replay protections where supported, and persist/deduplicate accepted events before acknowledging durable receipt. Do not trust tenant IDs or callback URLs solely because they are in JSON.
6. Restrict configurable destinations and redirects to intended hosts where untrusted input could cause server-side requests. Validate TLS; never bypass certificate verification to resolve an integration failure.
7. Mock outbound calls and webhook delivery in tests: success, malformed data, timeouts, rate limits, exhausted retries, invalid signatures, duplicates, and out-of-order delivery. Normal tests must not need live credentials or network access. Use `rails-background-jobs` if processing is asynchronous.

Document provider assumptions, timeout/retry limits, idempotency scope, configuration names, and the distinction between mocked verification and a live integration test.
