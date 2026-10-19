---
name: rails-query-performance
description: Diagnose or improve Rails queries, association loading, collection endpoints, and import performance. Use when query shape, database round trips, ordering, memory use, or batching changes.
---

# Rails query performance

Read `AGENTS.md` and the actual query, rendering loop, or importer before changing it. Preserve semantics and measure the suspected bottleneck instead of adding indexes or eager loading to every query.

1. Identify representative cardinality, selected fields, sort order, association access, and query counts. Use local/isolated data and bounded instrumentation; do not run a million-row import as routine verification.
2. Detect N+1 queries across rendering, serializers, and loops. Choose `preload`, `includes`, or `eager_load` based on whether associated tables filter/order the result and whether a join would multiply rows. Eager loading does not substitute for pagination.
3. Bound returned rows and memory. Prefer targeted columns or `pluck` when models are unnecessary, and streaming/batched traversal for large workloads. Preserve a stable cursor/order and account for concurrent inserts or updates when choosing batching behavior.
4. Inspect existing indexes and `EXPLAIN` plans using realistic predicates before proposing new indexes. `EXPLAIN ANALYZE` executes the query: use an isolated database for writes and assess read cost before running it on large data.
5. Preserve independent inventory/price lookups ordered by `event_time DESC, id DESC`, excluding undated events. The existing composite index supports those lookups; a JSONB column alone is not a reason to add a GIN index.
6. For importer work, inspect the current batch constant, lookup strategy, transaction boundary, and missing-reference behavior. Compare round trips and bounded memory; do not choose a batch size from historical documentation.
7. Add meaningful regression checks for query counts or result semantics when appropriate. Avoid fragile wall-clock assertions. Report dataset size, before/after evidence, and limitations; use `rails-database-migrations` for index changes and `rails-bulk-imports` for import semantics.
