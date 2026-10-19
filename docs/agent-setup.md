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

The command forces `RAILS_ENV=test` and collects failures across Ruby syntax,
RuboCop/Prettier formatting, Vitest, TypeScript/build, Brakeman, test database
preparation (without seeds), Zeitwerk, and Minitest. Tests are skipped if database
preparation fails. Never configure the test database to use real application data.
Focused iteration uses `bin/rails test path/to/test.rb` or `npm test`.

GitHub Actions runs independent Rails tests, Vitest, Brakeman, RuboCop, and Frontend
formatting and build jobs. Only Rails tests needs PostgreSQL. Configure branch
protection with these job names if passing checks are required before merging.

Brakeman is a static security scan, not a complete dependency advisory audit.
The original Rails 7.1.6 end-of-support warning was resolved by upgrading to
Rails 8.1.4; no ignore rule or disabled check was added.
