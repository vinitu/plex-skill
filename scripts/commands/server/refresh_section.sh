#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then
    echo "Usage: scripts/commands/server/refresh_section.sh [--base-url URL] [--token TOKEN] [--timeout SECONDS] --section-id ID"
    exit 0
fi

exec "${REPO_ROOT}/scripts/lib/plex_runtime.sh" refresh-section "$@"
