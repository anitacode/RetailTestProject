# AI agent setup

| Layer | Location | Responsibility |
| --- | --- | --- |
| Repository instructions | [`AGENTS.md`](../AGENTS.md) | Architecture, current domain rules, commands, and data-handling conventions |
| Task procedures | [`.agents/skills/`](../.agents/skills/) | Focused workflows selected using the catalog in `AGENTS.md` |
| Automated checks | [`bin/check`](../bin/check), [GitHub Actions](../.github/workflows/checks.yml) | Execute checks and fail on errors independently of agent instructions |

## Using the skills

The skills are installed in the repository, not in a developer's global skill directory.
Codex supports repository skills under `.agents/skills`; see the official
[skills documentation](https://learn.chatgpt.com/docs/build-skills) and
[AGENTS.md documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
It should be discoverable on the next turn. In clients that cache skill discovery,
start a new session in this repository. Other agents can follow the explicit link
in `AGENTS.md` even when they do not automatically discover this directory.

Example request: `Use $rails-expert to add a tracking-event endpoint following AGENTS.md.`

Nine repository-authored skills complement the upstream Rails skill:
`rails-api-development`, `rails-api-security`, `rails-api-testing`,
`rails-database-migrations`, `rails-query-performance`, `rails-background-jobs`,
`external-api-integrations`, `api-contracts`, and `rails-bulk-imports`.
Their activation scopes and entrypoints are listed in [AGENTS.md](../AGENTS.md).
These are procedures for future work, not claims that authentication, job workers,
OpenAPI validation, external integrations, or resumable imports already exist.

For example: `Use $rails-database-migrations to review this new constraint`, or
`Use $rails-bulk-imports to add duplicate detection without changing rollback behavior`.
Normal automatic skill selection remains enabled. Load additional skills only
when their scope applies; a terminal formatting change does not need an API review.

## Upstream rails-expert provenance

Installed source:

- Requested listing: https://www.skills.sh/jeffallan/claude-skills/rails-expert
- Repository: https://github.com/jeffallan/claude-skills
- Revision: `36f3fe8052da7c57083783268c6ea3265d075265`
- Path: `skills/rails-expert`, version `1.1.0`
- License: MIT, preserved beside `SKILL.md`.
- Local adaptation: an integration section at the start of `SKILL.md` gives this
  repository's Minitest, dependency, indexing, and migration conventions precedence
  over upstream examples. All five upstream reference files are preserved.

To update, review a specific upstream revision, compare its skill and references,
retain the integration section and license, update the revision above, and validate
the result. Do not automatically replace project conventions when updating a skill.
Keep new task procedures in separate skill folders rather than expanding `AGENTS.md`
into a collection of detailed workflows.

## Running checks

Install dependencies with `bundle install`, configure a dedicated test database
as described in the root README, then run:

```bash
bin/check
```

The command forces `RAILS_ENV=test`. Syntax errors stop execution immediately;
other failures are collected so a security finding does not hide test results:

1. Ruby syntax lint for source, tests, migrations, tasks, and Ruby executables.
2. Brakeman static security analysis using the locked gem version.
3. Test database creation/migration (without seeds), Rails Zeitwerk loading
   validation, and Minitest tests. Tests are skipped if database preparation fails.

The test database is disposable; never configure it to use real application data.
The command does not run the destructive demo seed script or import the million-row CSV.
Focused iteration still uses `bin/rails test path/to/test.rb`.

The GitHub Actions workflow runs the same command on pushes and pull requests with
a disposable PostgreSQL service. It becomes active when these files are pushed.
To make passing checks a merge requirement, configure a GitHub branch rule requiring
`Rails checks` after the first workflow run. No remote branch settings are changed
by this setup.

This baseline has syntax lint, not a Ruby style policy, and no static type checker:
the app currently has neither RuboCop configuration nor type signatures. Brakeman
is a static Rails security scan, not a complete dependency advisory audit or security
guarantee. Add broader checks deliberately rather than claiming unsupported coverage.

## Initial security finding

On 2026-10-19, Brakeman reported an existing `EOLRails` warning for the locked
Rails 7.1.6 dependency. The check intentionally fails until this is addressed;
no ignore rule was added. Upgrading Rails should be handled as a separate,
tested compatibility change. The CI setup itself does not upgrade the application.
