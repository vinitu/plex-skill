# plex-skill

AI agent skill for interacting with Plex Media Server via its HTTP API and plex.tv cloud API.

Works with any local Plex Media Server and the plex.tv Watchlist.

## Installation

```bash
npx skills add vinitu/plex-skill
```

Or with [skills.sh](https://skills.sh):

```bash
skills.sh add vinitu/plex-skill
```

## What it does

This skill gives AI agents (Claude Code, Cursor, Copilot, etc.) the ability to:

- **Ping** the Plex server to verify connectivity and auth
- **List** libraries (sections) with metadata
- **Search** media by title across all libraries
- **Recently added** items globally or per library
- **Sessions** — view active playback sessions
- **Metadata** — inspect detailed info for any item by rating key
- **Refresh** a library section (trigger scan)
- **Watchlist** — read the user's Plex Watchlist from plex.tv (cloud)

## How it works

Uses the Plex Media Server HTTP/XML API for local server operations and `python-plexapi` for the plex.tv Watchlist (which is a cloud-only feature).

All commands are exposed through a single CLI script: `scripts/plex_cli.py`.

## Requirements

- Python 3.8+
- A running Plex Media Server with a valid token
- `plexapi` package (only for the `watchlist` command): `pip3 install plexapi`

## Configuration

Copy `.env.example` to `.env` in the skill root and fill in your real values:

```bash
cp .env.example .env
```

Then replace the placeholder values in `.env`.

```
PLEX_BASE_URL=http://YOUR_PLEX_IP:32400
PLEX_TOKEN=YOUR_PLEX_TOKEN
```

Configuration sources are resolved in this order:

1. CLI flags: `--base-url` / `--token`
2. Existing shell env vars: `PLEX_BASE_URL` / `PLEX_TOKEN`
3. `.env` file in the skill root

The CLI auto-loads `.env`, validates that both values are present, and returns JSON errors if `.env` is missing, incomplete, or still contains placeholder values from `.env.example`.

## Quick start

```bash
cp .env.example .env
# edit .env and replace the placeholder values
python3 scripts/plex_cli.py ping
python3 scripts/plex_cli.py libraries
python3 scripts/plex_cli.py search --query "Alien" --limit 20
python3 scripts/plex_cli.py recently-added --limit 10
python3 scripts/plex_cli.py sessions
python3 scripts/plex_cli.py watchlist --filter movie
```

## Watchlist

The Watchlist lives on **plex.tv** (cloud), not on the local Plex server. The local server API has no watchlist endpoint.

Filter by type:

```bash
python3 scripts/plex_cli.py watchlist --filter movie
python3 scripts/plex_cli.py watchlist --filter show
```

Sort options:

| Sort | Description |
|------|-------------|
| `watchlistedAt:desc` | Most recently added (default) |
| `watchlistedAt:asc` | Oldest first |
| `titleSort:asc` | Alphabetical A-Z |
| `titleSort:desc` | Alphabetical Z-A |
| `originallyAvailableAt:desc` | Newest releases first |
| `rating:desc` | Highest rated first |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/plex_cli.py` | Main CLI — all Plex operations |

## Output

All commands return JSON for easy integration with AI agents and automation tools.

Typical validation errors also stay machine-readable:

```json
{
  "success": false,
  "error": "Missing Plex configuration: PLEX_BASE_URL, PLEX_TOKEN. Create /path/to/.env from /path/to/.env.example, export the variables, or pass --base-url/--token."
}
```

## Validation

At minimum, verify the CLI and tests locally:

```bash
python3 -m py_compile scripts/plex_cli.py
python3 -m unittest discover -s tests
python3 scripts/plex_cli.py ping
```

## License

MIT
