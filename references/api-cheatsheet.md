# Plex API Cheat Sheet

This file maps `scripts/plex_cli.py` commands to Plex endpoints.

## Auth

- Header: `X-Plex-Token: <token>`
- Base URL: `PLEX_BASE_URL` (example `http://192.168.107.236:32400`)
- Config precedence: CLI flags -> shell env vars -> `.env`
- Recommended setup: copy `.env.example` to `.env` and replace placeholder values

## Command -> Endpoint

- `ping`
  - `GET /`
- `libraries`
  - `GET /library/sections`
- `search --query "<text>" --limit N`
  - `GET /search?query=<text>&X-Plex-Container-Size=<N>`
- `recently-added [--section-id ID] --limit N`
  - global: `GET /library/recentlyAdded?X-Plex-Container-Size=<N>`
  - section: `GET /library/sections/<ID>/recentlyAdded?X-Plex-Container-Size=<N>`
- `sessions`
  - `GET /status/sessions`
- `metadata --rating-key KEY`
  - `GET /library/metadata/<KEY>`
- `refresh-section --section-id ID`
  - `GET /library/sections/<ID>/refresh`

## Typical Workflow

1. `ping` -> verify token/server.
2. `libraries` -> get section IDs.
3. `search` or `recently-added` -> find content.
4. `metadata` -> inspect selected item details.
5. `refresh-section` -> trigger scan when library changed on disk.
