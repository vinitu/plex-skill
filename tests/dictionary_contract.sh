#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

require_file() {
    local path="$1"
    [[ -f "${REPO_ROOT}/${path}" ]] || fail "missing file: ${path}"
}

require_exec() {
    local path="$1"
    [[ -x "${REPO_ROOT}/${path}" ]] || fail "file is not executable: ${path}"
}

require_text() {
    local path="$1"
    local pattern="$2"
    rg -q --fixed-strings "${pattern}" "${REPO_ROOT}/${path}" || fail "missing text '${pattern}' in ${path}"
}

require_file "AGENTS.md"
require_file "README.md"
require_file "SKILL.md"
require_file "Makefile"
require_file ".env.example"
require_file ".github/workflows/ci-main.yml"
require_file ".github/workflows/ci-pr.yml"
require_file "scripts/lib/plex_runtime.sh"
require_file "references/api-cheatsheet.md"
require_file "tests/smoke_plex.sh"
require_file "tests/dictionary_contract.sh"
require_file "tests/mocks/mock_curl.sh"

require_exec "scripts/lib/plex_runtime.sh"
require_exec "tests/mocks/mock_curl.sh"
require_text "README.md" ".env.example"
require_text "SKILL.md" ".env"
require_exec "scripts/commands/server/ping.sh"
require_exec "scripts/commands/server/libraries.sh"
require_exec "scripts/commands/server/search.sh"
require_exec "scripts/commands/server/recently_added.sh"
require_exec "scripts/commands/server/sessions.sh"
require_exec "scripts/commands/server/metadata.sh"
require_exec "scripts/commands/server/refresh_section.sh"
require_exec "scripts/commands/watchlist/list.sh"

require_text "AGENTS.md" "## Source Of Truth"
require_text "AGENTS.md" "## Public Interface"
require_text "AGENTS.md" "## Internal Implementation"
require_text "README.md" "## Repository layout"
require_text "README.md" "## Known limits"
require_text "README.md" "Package name:"
require_text "SKILL.md" "## Main Rule"
require_text "SKILL.md" "## Public Interface"
require_text "SKILL.md" "## JSON Contract"
require_text "SKILL.md" "## Operational Notes"
require_text "SKILL.md" "## Safety Boundaries"
require_text "README.md" "intentional deviation"
require_text "SKILL.md" "scripts/commands/server/ping.sh"
require_text "references/api-cheatsheet.md" ".env.example"
require_text ".github/workflows/ci-main.yml" "make compile"
require_text ".github/workflows/ci-pr.yml" "make compile"

bash "${REPO_ROOT}/scripts/commands/server/ping.sh" --help >/dev/null
bash "${REPO_ROOT}/scripts/commands/server/search.sh" --help >/dev/null
bash "${REPO_ROOT}/scripts/commands/server/recently_added.sh" --help >/dev/null
bash "${REPO_ROOT}/scripts/commands/server/metadata.sh" --help >/dev/null
bash "${REPO_ROOT}/scripts/commands/server/refresh_section.sh" --help >/dev/null
bash "${REPO_ROOT}/scripts/commands/watchlist/list.sh" --help >/dev/null

if git ls-files --error-unmatch .env >/dev/null 2>&1; then
    fail ".env must stay untracked"
fi

if [[ -e "${REPO_ROOT}/scripts/plex_cli.py" ]]; then
    fail "scripts/plex_cli.py must be removed"
fi

echo "Dictionary contract checks passed."
