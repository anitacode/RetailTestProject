---
name: rails-api-security
description: Review and implement access controls when Rails endpoints, authentication, authorization, permitted parameters, serialization, or user/business-scoped data access change. Keep the review scoped to the affected behavior.
---

# Rails API security

Read `AGENTS.md` and trace the request through controllers, scopes, services, and serializers. This repository currently has no user authentication or business tenancy implementation; do not invent an existing security boundary or assume every public read must become private.

1. Establish who may perform each affected action and which records/fields they may access. If a new protected operation needs an identity or tenant model and the request leaves it undefined, clarify that decision while continuing independent work.
2. Verify authentication and authorization separately. A logged-in user is not necessarily entitled to another user's record. Derive ownership/business scope from trusted identity, not a submitted owner ID or header accepted without verification.
3. Apply access scope before record lookup, including nested resources, search, pagination, bulk operations, and background-job inputs. Test cross-boundary IDs and parent/child mismatches. Preserve the application's documented 403/404 concealment policy.
4. Permit only client-editable parameters. Reject or ignore privileged owner, role, tenant, and internal-state fields according to the contract. Use explicit response fields so adding a database column cannot silently expose it.
5. Check credentials, request logging, error bodies, and exception paths for sensitive values. Keep secrets in existing configuration mechanisms. Parameterize user-derived SQL and use allowlists for dynamic ordering or column names.
6. Preserve CSRF protections for cookie/session authentication. Do not disable them merely because an endpoint returns JSON. For token authentication, verify token handling using the chosen mechanism instead of adding ad hoc checks.
7. Add relevant unauthenticated, forbidden, cross-boundary, and sensitive-field assertions via `rails-api-testing`. Run Brakeman through repository checks, but do not equate a clean static scan with verified authorization.

Report concrete access rules tested, findings with affected code, and unresolved design decisions. Do not expand a narrow endpoint change into an unrelated security rewrite.
