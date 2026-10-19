---
name: rails-background-jobs
description: Add or change Rails background jobs, enqueue timing, retries, idempotency, concurrency, or failure handling. Use when moving work out of a request or handling asynchronous execution.
---

# Rails background jobs

Read `AGENTS.md`, `ApplicationJob`, adapter configuration, and callers. This project has an Active Job base class but no established Sidekiq workflow. Use the configured adapter; do not add Sidekiq/Redis just because generic Rails examples mention them.

1. Define the unit of work, durable inputs, expected side effects, and acceptable delay. Pass stable identifiers rather than secrets or large serialized records. Decide how missing or changed records should behave at execution time.
2. Enqueue work after the relevant transaction commits. Verify actual behavior for the installed Rails version and adapter; do not assume newer Rails guarantees. If durable database-write/enqueue coordination is required, evaluate an outbox rather than promising atomicity across systems.
3. Design for duplicate delivery and overlapping workers. Use a stable operation key plus a database uniqueness/locking strategy where needed. Avoid a race-prone check-then-act flag. External side effects need provider idempotency or reconciliation, not just a local transaction.
4. Classify transient and permanent errors. Use bounded retries with backoff, explicit exhaustion handling, and time limits for network work. Do not retry validation failures forever or rescue all exceptions and report success.
5. Define operational failure visibility without logging sensitive payloads. Specify whether an operator can safely retry and what state proves completion. Do not claim exactly-once delivery.
6. Test commit/rollback enqueue timing, normal execution, duplicate execution, missing records, transient failure, and exhausted retries where relevant. Use Active Job test helpers and stub external effects; test concurrency-sensitive database invariants separately.

Report the adapter used, enqueue boundary, retry policy, duplicate behavior, and recovery path. Preserve synchronous CLI imports unless the task explicitly needs asynchronous execution.
