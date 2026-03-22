# AGENTS.md

## Purpose

This repository provides an AI skill for Plex Media Server.
It reads data from the local Plex HTTP API and from the Plex Discover Watchlist API.
The skill is for agents, so JSON output and stable command contracts matter more than shell convenience.

## Source Of Truth

- `SKILL.md` is the source of truth for the public skill contract.
- `scripts/plex_cli.py` is the stable public CLI entrypoint.
- `scripts/commands/` is a supported wrapper surface for shell-oriented workflows.
- `scripts/lib/` is internal implementation only.
- `README.md` is the source of truth for install, layout, validation, and limits.

## Repository Layout

- `AGENTS.md`: repository rules for coding agents.
- `README.md`: human-facing overview, setup, layout, validation, and limits.
- `SKILL.md`: agent-facing interface and JSON contract.
- `Makefile`: standard entrypoints for checks and tests.
- `scripts/plex_cli.py`: stable public CLI entrypoint.
- `scripts/commands/`: public command wrappers.
- `scripts/lib/`: internal helper scripts used by the public wrappers.
- `references/api-cheatsheet.md`: endpoint mapping.
- `tests/`: smoke checks, contract checks, mocks, and fixtures.
- `.github/workflows/`: CI validation workflows.

## Public Interface

- Preferred public CLI: `scripts/plex_cli.py`.
- Public read commands live in `scripts/commands/server/` and `scripts/commands/watchlist/`.
- Public write command: `scripts/commands/server/refresh_section.sh`.
- Public commands must keep JSON success and error envelopes stable.
- `scripts/plex_cli.py` and the command wrappers must stay runnable from the repo root.

## Internal Implementation

- `scripts/lib/plex_runtime.sh` is internal runtime code.
- `tests/mocks/` and `tests/fixtures/` are test-only internals.
- `references/` is documentation support, not runtime API.

## Working Rules

- Keep the runtime dependency-light: Bash, `curl`, and `jq`.
- Preserve existing JSON field names and envelope shapes unless a breaking change is explicitly requested.
- Update `README.md`, `SKILL.md`, and `references/api-cheatsheet.md` when command behaviour or output changes.
- Never print, log, or commit real Plex tokens or `.env` contents.
- Keep write operations explicit and clearly marked.

## Validation

Run from the repo root:

- `make check`
- `make compile`
- `make test`
- `scripts/commands/server/ping.sh` against a real Plex server when live verification is possible

## Common Pitfalls

- The Watchlist is a Plex Discover cloud feature. It does not exist on the local Plex server API.
- Watchlist `ratingKey` values may not match local server `ratingKey` values.
- `scripts/plex_cli.py` is the compatibility contract for existing users. Do not remove or break it without an explicit breaking release.
- The command wrappers under `scripts/commands/` are public, but they do not replace the stable CLI entrypoint.
- This repo does not use `scripts/applescripts/` because it is an HTTP skill, not a macOS app automation skill.
- The `.env` file must stay in the skill root, next to `SKILL.md`.

## Safety Rules

- Treat Plex library and session data as real user data.
- Read operations are safe by default.
- `refresh_section.sh` is a write operation because it triggers a library scan.
- Do not add unsupported destructive actions unless the user explicitly asks and the docs are updated.
