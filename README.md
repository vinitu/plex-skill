# plex-skill

AI agent skill for Plex Media Server.

It reads from a local Plex server and from the Plex Discover Watchlist API.
The stable public interface remains `scripts/plex_cli.py`, with shell wrappers under `scripts/commands/`.

## Installation

```bash
npx skills add vinitu/plex-skill
```

Or with [skills.sh](https://skills.sh):

```bash
skills.sh add vinitu/plex-skill
```

Package name: `vinitu/plex-skill`

Installed directory: `~/.agents/skills/plex`

The package name and installed directory are different. Use the installed directory in absolute command examples.

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
- `jq`
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

Config precedence:

1. CLI flags: `--base-url` and `--token`
2. Existing shell environment variables
3. `.env` in the skill root

## Public interface

Preferred entrypoint for agents and existing integrations:

```bash
python3 scripts/plex_cli.py ping
python3 scripts/plex_cli.py libraries
python3 scripts/plex_cli.py search --query "Alien" --limit 20
python3 scripts/plex_cli.py recently-added --limit 10
python3 scripts/plex_cli.py sessions
python3 scripts/plex_cli.py metadata --rating-key 12345
python3 scripts/plex_cli.py refresh-section --section-id 1
python3 scripts/plex_cli.py watchlist --filter movie
```

Shell wrappers in `scripts/commands/` are also supported:

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
- `scripts/plex_cli.py`: stable public CLI entrypoint
- `scripts/commands/`: public command surface
- `scripts/lib/`: internal shared runtime
- `references/`: endpoint notes
- `tests/`: smoke tests, contract checks, mocks, and fixtures
- `.github/workflows/`: CI

This repo does not use `scripts/applescripts/` because it is an HTTP skill.

## Validation

Run from the repo root:

```bash
make check
make compile
make test
```

For a live server check:

```bash
python3 scripts/plex_cli.py ping
scripts/commands/server/ping.sh
```

## Known limits

- The Watchlist is a Plex Discover cloud feature, not a local server feature.
- Watchlist IDs may not match local library IDs.
- The skill is read-mostly. The only write action is `refresh_section.sh`.
- `scripts/plex_cli.py` is kept for backward compatibility and should remain stable across non-breaking releases.

## License

MIT
