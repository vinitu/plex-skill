# Plex API Cheat Sheet

This file maps public wrappers in `scripts/commands/` to Plex endpoints.

## Auth

- Header: `X-Plex-Token: <token>`
- Base URL: `PLEX_BASE_URL` (example `http://192.168.107.236:32400`)
- Config precedence: CLI flags -> shell env vars -> `.env`
- Recommended setup: copy `.env.example` to `.env` and replace placeholder values
- CLI dependencies: `bash`, `curl`, `jq`

## Command -> Endpoint

- `scripts/commands/server/ping.sh`
  - `GET /`
- `scripts/commands/server/libraries.sh`
  - `GET /library/sections`
- `scripts/commands/server/search.sh --query "<text>" --limit N`
  - `GET /search?query=<text>&X-Plex-Container-Size=<N>`
- `scripts/commands/server/recently_added.sh [--section-id ID] [--limit N]`
  - global: `GET /library/recentlyAdded?X-Plex-Container-Size=<N>`
  - section: `GET /library/sections/<ID>/recentlyAdded?X-Plex-Container-Size=<N>`
- `scripts/commands/server/sessions.sh`
  - `GET /status/sessions`
- `scripts/commands/server/metadata.sh --rating-key KEY`
  - `GET /library/metadata/<KEY>`
- `scripts/commands/server/refresh_section.sh --section-id ID`
  - `GET /library/sections/<ID>/refresh`
- `scripts/commands/watchlist/list.sh [--filter movie|show] [--sort FIELD:DIR]`
  - `GET https://discover.provider.plex.tv/library/sections/watchlist/all?includeCollections=1&includeExternalMedia=1[&sort=<SORT>][&type=1|2]`

## Typical Workflow

1. `ping` -> verify token/server.
2. `libraries` -> get section IDs.
3. `search` or `recently-added` -> find content.
4. `metadata` -> inspect selected item details.
5. `refresh-section` -> trigger scan when library changed on disk.
