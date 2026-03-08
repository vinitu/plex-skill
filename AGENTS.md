# AGENTS.md

## Purpose

This repository provides an AI skill for interacting with Plex Media Server through its HTTP API and the plex.tv cloud API (Watchlist).

Primary goals:
- keep the CLI dependency-free for local server commands (stdlib only);
- use `plexapi` only for plex.tv cloud features (Watchlist);
- preserve predictable JSON I/O for agents;
- never print or commit real Plex tokens.

## Repository Layout

- `SKILL.md`: the skill contract and usage instructions for agents.
- `README.md`: public project overview and installation notes.
- `.github/workflows/ci-pr.yml`: PR validation, auto-merge, version bump, tag, and release flow.
- `.github/workflows/ci-main.yml`: main-branch validation, patch tag, and release flow.
- `scripts/plex_cli.py`: main CLI script — all Plex operations.
- `references/api-cheatsheet.md`: maps CLI commands to Plex API endpoints.
- `.env`: credentials file (git-ignored, never committed).

## Working Rules

- The CLI must work with Python 3.8+ stdlib for all local server commands. The only external dependency is `plexapi` for the `watchlist` command.
- Preserve CLI behavior. Existing commands, arguments, and output shapes should remain stable unless the task explicitly requires a breaking change.
- Preserve JSON output as the integration boundary. Success and error responses should stay machine-readable.
- If you change script behavior, update both `SKILL.md` and `README.md` when usage, arguments, or examples change.
- Never log, print, or commit `PLEX_TOKEN` or `.env` contents.
- Keep `references/api-cheatsheet.md` in sync when adding new commands or endpoints.

## Script Conventions

- Read-only operations: `ping`, `libraries`, `search`, `recently-added`, `sessions`, `metadata`, `watchlist`.
- Write operations: `refresh-section` (triggers a library scan).
- All commands return `{"success": true, ...}` on success and `{"success": false, "error": "..."}` on failure.
- The `.env` file is loaded automatically from the skill root (parent of `scripts/`).

## Validation

After making changes:
- run `python3 scripts/plex_cli.py ping` to verify connectivity;
- test modified commands against a live Plex server if available;
- at minimum, syntax-check with `python3 -m py_compile scripts/plex_cli.py`;
- verify `SKILL.md` and `README.md` examples match actual CLI behavior.

## Common Pitfalls

- The Plex Watchlist is a plex.tv cloud feature — it does NOT exist on the local server API. Always use `plexapi` for watchlist access.
- Plex API returns XML by default. The CLI parses XML responses; do not assume JSON from the server.
- `ratingKey` from watchlist items (plex.tv) may not match local server `ratingKey` values. Use `search` to find local library matches.
- The `.env` file must be in the skill root (next to `SKILL.md`), not inside `scripts/`.
