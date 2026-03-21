---
name: plex
description: Use this skill when you need to work with Plex Media Server through scripts/commands. It can verify connectivity, list libraries, search media, inspect sessions and metadata, read the Watchlist, and trigger a library refresh.
---

# Plex Skill

## Overview
- Public interface: `scripts/commands/`
- Internal runtime: `scripts/lib/`
- Output: JSON by default

## Main Rule

Use only `scripts/commands/` in normal agent workflows.
Do not call `scripts/lib/` directly.

## Requirements

- Bash
- `curl`
- `jq`
- Plex server URL and token

## Public Interface

- `scripts/commands/server/*`
- `scripts/commands/watchlist/*`

## Output Rules

- Commands return JSON on success.
- Commands return JSON on failure with `success: false` and an `error` message.
- `refresh_section.sh` is a write action and should only be used when the user explicitly asks for a scan.

## Commands

### Server

```bash
~/.agents/skills/plex/scripts/commands/server/ping.sh
~/.agents/skills/plex/scripts/commands/server/libraries.sh
~/.agents/skills/plex/scripts/commands/server/search.sh --query "Alien" --limit 20
~/.agents/skills/plex/scripts/commands/server/recently_added.sh --section-id 1 --limit 10
~/.agents/skills/plex/scripts/commands/server/sessions.sh
~/.agents/skills/plex/scripts/commands/server/metadata.sh --rating-key 12345
~/.agents/skills/plex/scripts/commands/server/refresh_section.sh --section-id 1
```

### Watchlist

```bash
~/.agents/skills/plex/scripts/commands/watchlist/list.sh
~/.agents/skills/plex/scripts/commands/watchlist/list.sh --filter movie
~/.agents/skills/plex/scripts/commands/watchlist/list.sh --sort titleSort:asc
```

## JSON Contract

- base envelope: `{"success": true, ...}` or `{"success": false, "error": "..."}`
- ping: `{"success":true,"server":{"friendlyName":"...","version":"...","machineIdentifier":"...","platform":"...","updatedAt":1700000000}}`
- libraries: `{"success":true,"count":1,"libraries":[...]}`
- search and recently added: `{"success":true,"count":N,"items":[...]}`
- sessions: `{"success":true,"count":N,"sessions":[...]}`
- metadata: `{"success":true,"ratingKey":12345,"found":true,"items":[...]}`
- watchlist: `{"success":true,"count":N,"items":[...]}`

## Safety Boundaries

- Read commands are safe by default.
- `refresh_section.sh` is the only supported write command.
- Internal test files under `tests/` are not public API.
- The Watchlist is a Plex Discover cloud feature. It is not part of the local Plex server API.
- Never print or store real `PLEX_TOKEN` values in chat, logs, or fixtures.
