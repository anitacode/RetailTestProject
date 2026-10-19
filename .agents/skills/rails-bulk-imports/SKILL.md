---
name: rails-bulk-imports
description: Implement or change large Rails file imports, streaming parsers, bulk writes, validation, duplicate prevention, checkpoints, or resumable processing. Use for importer behavior rather than display-only progress styling.
---

# Rails bulk imports

Read `AGENTS.md`, `TrackingEvents::CsvImporter`, its task, progress renderer, constraints, and importer tests. The current importer streams CSV batches inside one transaction; it has no durable resume checkpoint or event-deduplication key. Missing references and detected invalid row values raise an error with a CSV record number and roll back the entire import. Do not silently change these semantics while optimizing.

1. Define supported headers, encoding, malformed-row policy, reference lookup rules, and duplicate semantics. The current `Quantity` column takes precedence; legacy presence maps to placeholder 1/0. Consult current code for batch size instead of historical README values.
2. Stream records with bounded batches and bulk reference lookups. Avoid loading the whole file or issuing per-row queries. Count CSV records, not physical lines, when embedded newlines are possible.
3. Remember `insert_all!` bypasses model validation/callbacks. Validate or normalize inputs deliberately and enforce critical payload/foreign-key/uniqueness rules in PostgreSQL. Decide which failures skip rows and which abort the import; report each accurately.
4. Define event identity before adding deduplication. A repeated value or timestamp alone is not proof of a duplicate observation. Use a source event ID or documented composite key backed by a unique constraint; handle conflicts consistently and test re-imports.
5. Preserve the existing all-or-nothing transaction unless the requested design changes it. Staged counts are not committed counts, and 100% success must follow commit. A failure after earlier batches must roll back under the current contract.
6. If resumability is requested, design it explicitly: immutable source identity/checksum, stable record boundary, checkpoint persisted atomically with each committed batch, idempotent replay, and handling of changed files or concurrent workers. Explain that batch commits change all-or-nothing semantics; an in-memory row counter is not durable resume support.
7. Test multiple full/partial batches, malformed rows, missing references, direct database rejection, duplicate/replay behavior where implemented, rollback after earlier batches, and bounded query counts. Use small generated CSVs with quoted delimiters/newlines; reserve full-file benchmarks for a deliberate isolated run.

Report processed/staged/committed/skipped counts according to the actual transaction model, recovery behavior, and measured performance limitations. Use `rails-query-performance` for query plans and `rails-database-migrations` for new indexes or constraints.
