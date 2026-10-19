---
name: rails-database-migrations
description: Create or review Rails PostgreSQL changes to tables, indexes, constraints, enums, or stored-data representations. Assess locking, backfills, rollout compatibility, and rollback before executing migrations.
---

# Rails database migrations

Read `AGENTS.md`, `db/schema.rb`, relevant prior migrations, model validations, and all writers, including `insert_all!` importers. Existing data conversions in this project are intentionally irreversible; never use automatic rollback as a generic error-recovery step.

1. State the invariant being changed and inspect existing data assumptions without disclosing row contents or secrets. Identify nulls, invalid payloads, duplicates, and downstream readers. Do not invent replacement observations; clarify semantic conversions when necessary.
2. Add a new migration rather than rewriting already-applied history. Pair model validation with PostgreSQL constraints when bulk writers can bypass callbacks. Use foreign keys and uniqueness constraints for invariants that must survive concurrent writes.
3. Assess table size, write traffic, lock duration, scan/rewrite cost, and old/new application compatibility. Separate large backfills into bounded, restartable work; consider an expand/backfill/validate/contract rollout when a one-step change would block traffic or break mixed versions.
4. Choose indexes for actual access paths, considering existing composite indexes and ordering. For a production-sized table, consider concurrent index creation and its requirement to run outside the migration transaction; account for invalid indexes after interruption. Verify the syntax against the installed Rails/PostgreSQL versions.
5. For new checks or foreign keys on large existing tables, consider adding without immediate validation and validating separately. Distinguish that strategy from uniqueness/index operations. Document when the invariant becomes fully enforced.
6. State reversibility honestly. A down migration that loses data is not a safe undo plan. Review the exact target environment before execution; do not reset or seed application databases to recover from errors.
7. Test schema changes and representative data conversions in an isolated database, including direct-write rejection and boundary cases. Test rollback only when reversible and safe there. Regenerate `db/schema.rb` through Rails and inspect the diff; run the relevant model/import tests and repository checks.

Provide the migration's data effect, expected deployment order, locking/backfill considerations, verification results, and recovery limitations. Do not claim populated-data conversion was tested merely because a fresh schema loaded.
