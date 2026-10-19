---
name: rails-api-development
description: Add or change Rails endpoints, routes, parameter handling, JSON responses, or collection pagination. Use for endpoint implementation rather than unrelated model-only or terminal changes.
---

# Rails API development

Read the repository's `AGENTS.md`, routes, affected controllers, and nearby tests before editing. This app currently serves HTML index/show routes; do not convert them to API-only controllers or change their response format as a side effect.

1. Identify the caller, HTTP method, route, input shape, success response, and error cases. Reuse existing conventions; when no JSON convention exists, choose and document one for the requested endpoint without redesigning the application.
2. Keep HTTP handling in controllers and reusable business operations in existing models/services. Use Rails 7.1-compatible strong parameters; permit explicit nested fields and validate their types and domain rules. Strong parameters filter fields but do not validate values.
3. Scope lookups to the intended access boundary before finding a record. Apply `rails-api-security` to endpoint access and serialization decisions; do not assume a `current_user` or tenant model already exists.
4. Return explicit response fields and consistent status codes: ordinarily 200 for reads, 201 for creation, 204 for bodyless deletion, 422 for domain validation, and 404 for missing records. Preserve an existing contract when it differs; distinguish malformed requests from valid JSON with invalid domain values.
5. Bound collection responses with validated pagination parameters, a maximum page size, and deterministic ordering including a unique tie-breaker. Follow existing pagination tooling if present; do not add a gem for a simple limit. Specify defaults, navigation, and invalid-page behavior.
6. For tracking events, use current quantity/price payloads and preserve independent latest-observation ordering. Do not expose the legacy inventory boolean as authoritative.
7. Use `rails-api-testing` for behavioral coverage and `api-contracts` when the public request/response contract changes. Run focused tests and repository checks for code changes.

In the handoff, include the route, a concrete request/response example, pagination behavior, and checks actually run.
