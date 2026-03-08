---
name: plex
description: Work with Plex Media Server via Plex HTTP API. Use when you need to verify Plex connectivity, list libraries, search movies/series, check recently added items, inspect active sessions, read metadata, get the user's watchlist, or trigger library refresh.
---

# Plex Skill

## Overview
- Manages a Plex Media Server through its HTTP API.
- Credentials stored in `.env` file next to this SKILL.md. Start from `.env.example`; the CLI auto-loads and validates the final `.env`.
- Main helper script: `scripts/plex_cli.py` (Python 3).
- **Dependency**: `plexapi` package required for `watchlist` command (`pip3 install plexapi`).

## Quick Start

1. **Credentials**: create `.env` next to this SKILL.md from `.env.example`, then fill in your real Plex URL and token. The CLI auto-loads `.env`, but CLI flags and existing shell env vars override it.
2. Run:
   ```bash
   cp ~/.agents/skills/plex/.env.example ~/.agents/skills/plex/.env
   # edit ~/.agents/skills/plex/.env and replace the placeholder values
   python3 ~/.agents/skills/plex/scripts/plex_cli.py ping
   python3 ~/.agents/skills/plex/scripts/plex_cli.py libraries
   ```

Section IDs are server-specific. Use `python3 ~/.agents/skills/plex/scripts/plex_cli.py libraries` to discover them on the target server.

## What This Skill Can Do

1. Verify Plex connection and auth:
   ```bash
   python3 ~/.agents/skills/plex/scripts/plex_cli.py ping
   ```
2. List Plex libraries:
   ```bash
   python3 ~/.agents/skills/plex/scripts/plex_cli.py libraries
   ```
3. Search media by title:
   ```bash
   python3 ~/.agents/skills/plex/scripts/plex_cli.py search --query "Alien" --limit 20
   ```
4. Show recently added items:
   ```bash
   python3 ~/.agents/skills/plex/scripts/plex_cli.py recently-added --limit 10
   python3 ~/.agents/skills/plex/scripts/plex_cli.py recently-added --section-id SECTION_ID --limit 10
   ```
5. Show active playback sessions:
   ```bash
   python3 ~/.agents/skills/plex/scripts/plex_cli.py sessions
   ```
6. Get metadata by `ratingKey`:
   ```bash
   python3 ~/.agents/skills/plex/scripts/plex_cli.py metadata --rating-key 12345
   ```
7. Trigger library refresh (scan) — normally not needed, Plex scans automatically:
   ```bash
   python3 ~/.agents/skills/plex/scripts/plex_cli.py refresh-section --section-id SECTION_ID
   ```
8. Get user's Plex Watchlist (from plex.tv cloud, not local server):
   ```bash
   python3 ~/.agents/skills/plex/scripts/plex_cli.py watchlist
   python3 ~/.agents/skills/plex/scripts/plex_cli.py watchlist --filter movie
   python3 ~/.agents/skills/plex/scripts/plex_cli.py watchlist --filter show
   python3 ~/.agents/skills/plex/scripts/plex_cli.py watchlist --sort titleSort:asc
   ```

## Watchlist

The watchlist lives on **plex.tv** (cloud), not on the local Plex server. The `watchlist` command uses `python-plexapi` to fetch it.

### Important notes
- **Requires**: `pip3 install plexapi` (already installed).
- The local Plex server API does NOT have a watchlist endpoint — it only exists on plex.tv.
- Returns metadata from Plex's online database (title, year, guid, type). These are NOT local library items.
- To match watchlist items against the local library, search by title/year using the `search` command.

### Filter options
- `--filter movie` — only movies
- `--filter show` — only TV shows
- No filter — returns all items (movies + shows)

### Sort options (format: `field:dir`)
| Sort | Description |
|------|-------------|
| `watchlistedAt:desc` | Most recently added to watchlist first (default) |
| `watchlistedAt:asc` | Oldest watchlist additions first |
| `titleSort:asc` | Alphabetical A→Z |
| `titleSort:desc` | Alphabetical Z→A |
| `originallyAvailableAt:desc` | Newest releases first |
| `rating:desc` | Highest rated first |

### Workflow: Download all watchlist movies
1. Get watchlist: `plex_cli.py watchlist --filter movie`
2. For each item, search RuTracker (see `rutracker` skill)
3. Send .torrent to NAS (see `synology-download-station` skill)
4. Plex picks up new files automatically after download

## Operational Notes
- Default output is JSON for easy processing.
- Invalid or incomplete config also returns JSON errors, not Python tracebacks.
- Library refresh happens automatically — only use `refresh-section` if the user explicitly asks.
- Never print or commit real `PLEX_TOKEN`.
- Summarize results naturally — don't dump raw JSON to the user.

## References
- `references/api-cheatsheet.md` for endpoint and command mapping.
