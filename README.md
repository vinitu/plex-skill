# plex-skill

AI agent skill for Plex Media Server.

It reads from a local Plex server and from the Plex Discover Watchlist API.
The public interface is the shell command surface under `scripts/commands/`.

## Installation

```bash
npx skills add vinitu/plex-skill
```

Or with [skills.sh](https://skills.sh):

```bash
skills.sh add vinitu/plex-skill
```

Package name: `vinitu/plex-skill`

Installed skill directory depends on the skill manager configuration.

## Purpose and scope

This skill lets agents:

- verify Plex connectivity;
- list libraries;
- search media;
- read recently added items;
- inspect active sessions;
- inspect metadata by rating key;
- trigger a library refresh;
- read the user's Watchlist.

## Requirements

- Bash
- `curl`
- a running Plex Media Server
- a valid `PLEX_TOKEN`

## Configuration

Copy `.env.example` to `.env` in the repo root and fill in your real values:

```bash
cp .env.example .env
```

```dotenv
PLEX_BASE_URL=http://YOUR_PLEX_IP:32400
PLEX_TOKEN=YOUR_PLEX_TOKEN
```

The `.env` file must stay in the skill root, next to `SKILL.md`. Do not commit real Plex credentials.

Config precedence:

1. CLI flags: `--base-url` and `--token`
2. Existing shell environment variables
3. `.env` in the skill root

## Public interface

Public commands:

### Server

```bash
scripts/commands/server/ping.sh
scripts/commands/server/libraries.sh
scripts/commands/server/search.sh --query "Alien" --limit 20
scripts/commands/server/recently_added.sh --limit 10
scripts/commands/server/sessions.sh
scripts/commands/server/metadata.sh --rating-key 12345
scripts/commands/server/refresh_section.sh --section-id 1
```

### Watchlist

```bash
scripts/commands/watchlist/list.sh
scripts/commands/watchlist/list.sh --filter movie
scripts/commands/watchlist/list.sh --sort titleSort:asc
```

## Output contract

All public commands return JSON.

Success output starts with:

```json
{"success": true}
```

Failure output starts with:

```json
{"success": false, "error": "message"}
```

## Repository layout

- `AGENTS.md`: rules for coding agents
- `README.md`: setup, public interface, layout, validation, and limits
- `SKILL.md`: agent-facing contract
- `Makefile`: standard validation entrypoints
- `scripts/commands/`: public command surface
- `scripts/lib/`: internal shared runtime
- `references/`: endpoint notes
- `tests/`: smoke tests, contract checks, mocks, and fixtures
- `.github/workflows/`: CI

This repo does not use `scripts/applescripts/` because it is an HTTP skill.
Unlike the default macOS skill schema, this repo uses `scripts/lib/plex_runtime.sh` as a shared internal backend for the public shell wrappers.

## Validation

Run from the repo root:

```bash
make check
make compile
make test
```

For a live server check:

```bash
scripts/commands/server/ping.sh
```

The command wrappers must remain runnable from the repo root.

## Known limits

- The Watchlist is a Plex Discover cloud feature, not a local server feature.
- Watchlist IDs may not match local library IDs.
- The skill is read-mostly. The only write action is `refresh_section.sh`.
- Public wrapper scripts delegate parsing and JSON shaping to `scripts/lib/plex_runtime.sh`. This intentional deviation from the default wrapper pattern is part of the current compatibility design.

## License

MIT
