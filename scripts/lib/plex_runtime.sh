#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DOTENV_PATH="${SKILL_ROOT}/.env"
DOTENV_EXAMPLE_PATH="${SKILL_ROOT}/.env.example"
EXAMPLE_BASE_URL="http://YOUR_PLEX_IP:32400"
EXAMPLE_TOKEN="YOUR_PLEX_TOKEN"
DISCOVER_BASE_URL="https://discover.provider.plex.tv"
CURL_BIN="${PLEX_CURL_BIN:-curl}"
JQ_BIN="${PLEX_JQ_BIN:-jq}"
TIMEOUT=20
BASE_URL=""
TOKEN=""
REQUEST_CONTENT_TYPE=""
REQUEST_ERROR=""

read -r -d '' JQ_COMMON <<'JQ' || true
def arr:
  if . == null then []
  elif type == "array" then .
  else [.] end;

def to_int_or_null:
  if . == null then null
  elif type == "number" then
    if isnan or isinfinite then null else . end
  elif type == "string" then
    try (
      tonumber
      | if type == "number" and (isnan or isinfinite) then null else . end
    ) catch null
  else null
  end;

def media_item:
  {
    type: (.type // null),
    ratingKey: (.ratingKey // null | to_int_or_null),
    title: (.title // null),
    year: (.year // null | to_int_or_null),
    librarySectionID: (.librarySectionID // null | to_int_or_null),
    librarySectionTitle: (.librarySectionTitle // null),
    parentTitle: (.parentTitle // null),
    grandparentTitle: (.grandparentTitle // null),
    summary: (.summary // null),
    duration: (.duration // null | to_int_or_null),
    viewCount: (.viewCount // null | to_int_or_null),
    addedAt: (.addedAt // null | to_int_or_null),
    lastViewedAt: (.lastViewedAt // null | to_int_or_null)
  };

def media_nodes:
  (
    (.MediaContainer.Directory | arr)
    + (.MediaContainer.Video | arr)
    + (.MediaContainer.Metadata | arr)
    + ((.MediaContainer.Hub | arr) | map(.Metadata | arr) | add // [])
  )
  | map(select((.title // .ratingKey // null) != null) | media_item);

def first_or_null:
  if . == null then null
  elif type == "array" then .[0]? // null
  else .
  end;
JQ

print_main_help() {
    cat <<'EOF'
Usage:
  plex-runtime [--base-url URL] [--token TOKEN] [--timeout SECONDS] <command> [options]

Commands:
  ping
  libraries
  search --query TEXT [--limit N]
  recently-added [--section-id ID] [--limit N]
  sessions
  metadata --rating-key KEY
  refresh-section --section-id ID
  watchlist [--filter movie|show] [--sort SORT]
EOF
}

print_command_help() {
    local command="${1:-}"
    case "${command}" in
        ping)
            echo "Usage: plex-runtime ping"
            ;;
        libraries)
            echo "Usage: plex-runtime libraries"
            ;;
        search)
            echo "Usage: plex-runtime search --query TEXT [--limit N]"
            ;;
        recently-added)
            echo "Usage: plex-runtime recently-added [--section-id ID] [--limit N]"
            ;;
        sessions)
            echo "Usage: plex-runtime sessions"
            ;;
        metadata)
            echo "Usage: plex-runtime metadata --rating-key KEY"
            ;;
        refresh-section)
            echo "Usage: plex-runtime refresh-section --section-id ID"
            ;;
        watchlist)
            echo "Usage: plex-runtime watchlist [--filter movie|show] [--sort SORT]"
            ;;
        *)
            print_main_help
            ;;
    esac
}

trim() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

json_error() {
    "${JQ_BIN}" -n --arg error "$1" '{success: false, error: $error}'
}

die_json() {
    json_error "$1"
    exit 1
}

ensure_command() {
    local command_name="$1"
    if [[ "${command_name}" == */* ]]; then
        [[ -x "${command_name}" ]] || die_json "Required command not found: ${command_name}"
        return
    fi

    command -v "${command_name}" >/dev/null 2>&1 || die_json "Required command not found: ${command_name}"
}

load_dotenv() {
    [[ -f "${DOTENV_PATH}" ]] || return 0

    local line=""
    local key=""
    local value=""

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        [[ -n "${line}" ]] || continue
        [[ "${line}" == \#* ]] && continue
        [[ "${line}" == *=* ]] || continue

        key="${line%%=*}"
        value="${line#*=}"
        key="$(trim "${key}")"
        value="$(trim "${value}")"

        if [[ -n "${value}" && "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
            value="${value:1:${#value}-2}"
        elif [[ -n "${value}" && "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
            value="${value:1:${#value}-2}"
        fi

        if [[ -z "${!key+x}" ]]; then
            export "${key}=${value}"
        fi
    done < "${DOTENV_PATH}"
}

normalize_base_url() {
    local value
    value="$(trim "${1-}")"

    if [[ -z "${value}" ]]; then
        die_json "PLEX_BASE_URL is required. Create .env from .env.example or pass --base-url."
    fi

    if [[ "${value}" == "${EXAMPLE_BASE_URL}" ]]; then
        die_json "PLEX_BASE_URL still uses the placeholder from .env.example. Replace it with your real Plex server URL."
    fi

    if [[ ! "${value}" =~ ^https?://[^[:space:]/][^[:space:]]*$ ]]; then
        die_json "PLEX_BASE_URL must be a full URL like http://192.168.107.236:32400"
    fi

    while [[ "${value}" == */ ]]; do
        value="${value%/}"
    done

    printf '%s' "${value}"
}

normalize_token() {
    local value
    value="$(trim "${1-}")"

    if [[ -z "${value}" ]]; then
        die_json "PLEX_TOKEN is required. Create .env from .env.example or pass --token."
    fi

    if [[ "${value}" == "${EXAMPLE_TOKEN}" ]]; then
        die_json "PLEX_TOKEN still uses the placeholder from .env.example. Replace it with your real Plex token."
    fi

    printf '%s' "${value}"
}

resolve_config() {
    local raw_base_url
    local raw_token
    local missing=()
    local missing_text=""

    raw_base_url="$(trim "${BASE_URL-}")"
    raw_token="$(trim "${TOKEN-}")"

    if [[ -z "${raw_base_url}" ]]; then
        missing+=("PLEX_BASE_URL")
    fi
    if [[ -z "${raw_token}" ]]; then
        missing+=("PLEX_TOKEN")
    fi

    if [[ "${#missing[@]}" -gt 0 ]]; then
        missing_text="$(printf '%s, ' "${missing[@]}")"
        missing_text="${missing_text%, }"

        if [[ -f "${DOTENV_PATH}" ]]; then
            die_json "Missing Plex configuration: ${missing_text}. Update ${DOTENV_PATH} or pass the matching CLI flag."
        fi
        die_json "Missing Plex configuration: ${missing_text}. Create ${DOTENV_PATH} from ${DOTENV_EXAMPLE_PATH}, export the variables, or pass --base-url/--token."
    fi

    BASE_URL="$(normalize_base_url "${raw_base_url}")"
    TOKEN="$(normalize_token "${raw_token}")"
}

urlencode() {
    "${JQ_BIN}" -nr --arg value "${1-}" '$value | @uri'
}

build_query() {
    local query=""
    local key=""
    local value=""

    while [[ $# -gt 1 ]]; do
        key="$1"
        value="$2"
        shift 2

        [[ -n "${value}" ]] || continue

        if [[ -z "${query}" ]]; then
            query="?"
        else
            query="${query}&"
        fi

        query="${query}${key}=$(urlencode "${value}")"
    done

    printf '%s' "${query}"
}

clean_error_text() {
    tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

request_json() {
    local url="$1"
    local path_label="$2"
    local method="${3:-GET}"
    local headers_file=""
    local body_file=""
    local stderr_file=""
    local http_code=""
    local body_snippet=""
    local stderr_text=""

    REQUEST_ERROR=""
    REQUEST_CONTENT_TYPE=""

    headers_file="$(mktemp)"
    body_file="$(mktemp)"
    stderr_file="$(mktemp)"

    if ! "${CURL_BIN}" \
        -sS \
        -X "${method}" \
        --connect-timeout "${TIMEOUT}" \
        --max-time "${TIMEOUT}" \
        -D "${headers_file}" \
        -o "${body_file}" \
        -H "Accept: application/json" \
        -H "X-Plex-Token: ${TOKEN}" \
        -H "X-Plex-Product: OpenClaw Plex Skill" \
        -H "X-Plex-Client-Identifier: openclaw-plex-skill" \
        -H "X-Plex-Platform: Linux" \
        "${url}" 2>"${stderr_file}"; then
        stderr_text="$(<"${stderr_file}")"
        REQUEST_ERROR="Connection failed for ${path_label}: $(printf '%s' "${stderr_text}" | clean_error_text)"
        rm -f "${headers_file}" "${body_file}" "${stderr_file}"
        return 1
    fi

    http_code="$(awk 'toupper($1) ~ /^HTTP/ { code=$2 } END { print code }' "${headers_file}")"
    REQUEST_CONTENT_TYPE="$(awk -F': *' 'tolower($1) == "content-type" { value=$2 } END { gsub(/\r/, "", value); print value }' "${headers_file}")"

    if [[ -n "${http_code}" && "${http_code}" =~ ^[0-9]+$ && "${http_code}" -ge 400 ]]; then
        body_snippet="$(head -c 300 "${body_file}" | clean_error_text)"
        REQUEST_ERROR="Plex API HTTP ${http_code} on ${path_label}: ${body_snippet}"
        rm -f "${headers_file}" "${body_file}" "${stderr_file}"
        return 1
    fi

    cat "${body_file}"
    rm -f "${headers_file}" "${body_file}" "${stderr_file}"
}

parse_json_response() {
    local path_label="$1"
    local jq_program="$2"
    local raw_json="$3"
    local result=""
    shift 3

    if ! result="$(printf '%s' "${raw_json}" | "${JQ_BIN}" "$@" "${jq_program}")"; then
        die_json "Invalid JSON response for ${path_label}"
    fi

    printf '%s\n' "${result}"
}

require_integer() {
    local name="$1"
    local value="$2"
    [[ "${value}" =~ ^-?[0-9]+$ ]] || die_json "${name} must be an integer"
}

run_ping() {
    local raw_json=""
    raw_json="$(request_json "${BASE_URL}/" "/")" || die_json "${REQUEST_ERROR}"
    parse_json_response "/" "${JQ_COMMON}
      (.MediaContainer // .) as \$root |
      {
        success: true,
        server: {
          friendlyName: (\$root.friendlyName // null),
          version: (\$root.version // null),
          machineIdentifier: (\$root.machineIdentifier // null),
          platform: (\$root.platform // null),
          updatedAt: (\$root.updatedAt // null | to_int_or_null)
        }
      }
    " "${raw_json}"
}

run_libraries() {
    local raw_json=""
    raw_json="$(request_json "${BASE_URL}/library/sections" "/library/sections")" || die_json "${REQUEST_ERROR}"
    parse_json_response "/library/sections" "${JQ_COMMON}
      [(.MediaContainer.Directory | arr)[] | {
        key: (.key // null | to_int_or_null),
        title: (.title // null),
        type: (.type // null),
        agent: (.agent // null),
        scanner: (.scanner // null),
        language: (.language // null),
        updatedAt: (.updatedAt // null | to_int_or_null),
        scannedAt: (.scannedAt // null | to_int_or_null)
      }] as \$items |
      {
        success: true,
        count: (\$items | length),
        libraries: \$items
      }
    " "${raw_json}"
}

run_search() {
    local query="$1"
    local limit="$2"
    local path="/search"
    local raw_json=""
    local request_url=""

    request_url="${BASE_URL}${path}$(build_query "query" "${query}" "X-Plex-Container-Size" "${limit}")"
    raw_json="$(request_json "${request_url}" "${path}")" || die_json "${REQUEST_ERROR}"
    parse_json_response "${path}" "${JQ_COMMON}
      (media_nodes | .[0:${limit}]) as \$items |
      {
        success: true,
        query: \$query,
        count: (\$items | length),
        items: \$items
      }
    " "${raw_json}" --arg query "${query}"
}

run_recently_added() {
    local section_id="${1-}"
    local limit="$2"
    local path="/library/recentlyAdded"
    local request_url=""
    local raw_json=""

    if [[ -n "${section_id}" ]]; then
        path="/library/sections/${section_id}/recentlyAdded"
    fi

    request_url="${BASE_URL}${path}$(build_query "X-Plex-Container-Start" "0" "X-Plex-Container-Size" "${limit}")"
    raw_json="$(request_json "${request_url}" "${path}")" || die_json "${REQUEST_ERROR}"
    parse_json_response "${path}" "${JQ_COMMON}
      (media_nodes | .[0:${limit}]) as \$items |
      {
        success: true,
        sectionId: ${section_id:-null},
        count: (\$items | length),
        items: \$items
      }
    " "${raw_json}"
}

run_sessions() {
    local raw_json=""
    raw_json="$(request_json "${BASE_URL}/status/sessions" "/status/sessions")" || die_json "${REQUEST_ERROR}"
    parse_json_response "/status/sessions" "${JQ_COMMON}
      (
        (.MediaContainer.Video | arr)
        + (.MediaContainer.Metadata | arr)
      ) as \$items |
      {
        success: true,
        count: (\$items | length),
        sessions: (
          \$items
          | map({
              ratingKey: (.ratingKey // null | to_int_or_null),
              title: (.title // null),
              type: (.type // null),
              year: (.year // null | to_int_or_null),
              username: ((.User | first_or_null | .title) // null),
              player: ((.Player | first_or_null | .product) // null),
              state: ((.Player | first_or_null | .state) // null)
            })
        )
      }
    " "${raw_json}"
}

run_metadata() {
    local rating_key="$1"
    local path="/library/metadata/${rating_key}"
    local raw_json=""

    raw_json="$(request_json "${BASE_URL}${path}" "${path}")" || die_json "${REQUEST_ERROR}"
    parse_json_response "${path}" "${JQ_COMMON}
      (media_nodes) as \$items |
      {
        success: true,
        ratingKey: ${rating_key},
        found: (\$items | length) > 0,
        items: \$items
      }
    " "${raw_json}"
}

run_refresh_section() {
    local section_id="$1"
    local path="/library/sections/${section_id}/refresh"

    request_json "${BASE_URL}${path}" "${path}" "GET" >/dev/null || die_json "${REQUEST_ERROR}"
    "${JQ_BIN}" -n --argjson sectionId "${section_id}" '{
      success: true,
      sectionId: $sectionId,
      message: "refresh triggered"
    }'
}

run_watchlist() {
    local filter="${1-}"
    local sort="${2-}"
    local request_url=""
    local raw_json=""
    local media_type=""
    local path="/library/sections/watchlist/all"

    case "${filter}" in
        "" ) media_type="" ;;
        movie) media_type="1" ;;
        show) media_type="2" ;;
        *) die_json "Invalid watchlist filter: ${filter}" ;;
    esac

    request_url="${DISCOVER_BASE_URL}${path}$(build_query \
        "includeCollections" "1" \
        "includeExternalMedia" "1" \
        "sort" "${sort}" \
        "type" "${media_type}")"

    raw_json="$(request_json "${request_url}" "${path}")" || die_json "${REQUEST_ERROR}"
    parse_json_response "${path}" "${JQ_COMMON}
      [(.MediaContainer.Metadata | arr)[] | {
        type: (.type // null),
        title: (.title // null),
        year: (.year // null | to_int_or_null),
        guid: (.guid // ((.Guid | arr | .[0]? | .id) // null)),
        ratingKey: (.ratingKey // null | to_int_or_null),
        summary: (
          (.summary // null)
          | if . == null or . == \"\" then null else .[0:200] end
        )
      }] as \$items |
      {
        success: true,
        count: (\$items | length),
        items: \$items
      }
    " "${raw_json}"
}

load_dotenv
BASE_URL="${PLEX_BASE_URL-}"
TOKEN="${PLEX_TOKEN-}"
ensure_command "${CURL_BIN}"
ensure_command "${JQ_BIN}"

COMMAND=""
COMMAND_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url)
            [[ $# -ge 2 ]] || die_json "Missing value for --base-url"
            BASE_URL="$2"
            shift 2
            ;;
        --token)
            [[ $# -ge 2 ]] || die_json "Missing value for --token"
            TOKEN="$2"
            shift 2
            ;;
        --timeout)
            [[ $# -ge 2 ]] || die_json "Missing value for --timeout"
            require_integer "--timeout" "$2"
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            if [[ -z "${COMMAND}" ]]; then
                print_main_help
                exit 0
            fi
            COMMAND_ARGS+=("$1")
            shift
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                COMMAND_ARGS+=("$1")
                shift
            done
            ;;
        -*)
            if [[ -z "${COMMAND}" ]]; then
                die_json "Unknown option: $1"
            fi
            COMMAND_ARGS+=("$1")
            shift
            ;;
        *)
            if [[ -z "${COMMAND}" ]]; then
                COMMAND="$1"
            else
                COMMAND_ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

[[ -n "${COMMAND}" ]] || {
    print_main_help
    exit 1
}

if [[ "${#COMMAND_ARGS[@]}" -gt 0 ]]; then
    set -- "${COMMAND_ARGS[@]}"
else
    set --
fi

case "${COMMAND}" in
    ping)
        [[ "${1-}" == "--help" || "${1-}" == "-h" ]] && { print_command_help "ping"; exit 0; }
        [[ $# -eq 0 ]] || die_json "Unknown argument for ping: $1"
        resolve_config
        run_ping
        ;;
    libraries)
        [[ "${1-}" == "--help" || "${1-}" == "-h" ]] && { print_command_help "libraries"; exit 0; }
        [[ $# -eq 0 ]] || die_json "Unknown argument for libraries: $1"
        resolve_config
        run_libraries
        ;;
    search)
        search_query=""
        search_limit="20"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --query)
                    [[ $# -ge 2 ]] || die_json "Missing value for --query"
                    search_query="$2"
                    shift 2
                    ;;
                --limit)
                    [[ $# -ge 2 ]] || die_json "Missing value for --limit"
                    require_integer "--limit" "$2"
                    search_limit="$2"
                    shift 2
                    ;;
                -h|--help)
                    print_command_help "search"
                    exit 0
                    ;;
                *)
                    die_json "Unknown argument for search: $1"
                    ;;
            esac
        done
        [[ -n "${search_query}" ]] || die_json "Missing required argument: --query"
        resolve_config
        run_search "${search_query}" "${search_limit}"
        ;;
    recently-added)
        recent_section_id=""
        recent_limit="10"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --section-id)
                    [[ $# -ge 2 ]] || die_json "Missing value for --section-id"
                    require_integer "--section-id" "$2"
                    recent_section_id="$2"
                    shift 2
                    ;;
                --limit)
                    [[ $# -ge 2 ]] || die_json "Missing value for --limit"
                    require_integer "--limit" "$2"
                    recent_limit="$2"
                    shift 2
                    ;;
                -h|--help)
                    print_command_help "recently-added"
                    exit 0
                    ;;
                *)
                    die_json "Unknown argument for recently-added: $1"
                    ;;
            esac
        done
        resolve_config
        run_recently_added "${recent_section_id}" "${recent_limit}"
        ;;
    sessions)
        [[ "${1-}" == "--help" || "${1-}" == "-h" ]] && { print_command_help "sessions"; exit 0; }
        [[ $# -eq 0 ]] || die_json "Unknown argument for sessions: $1"
        resolve_config
        run_sessions
        ;;
    metadata)
        metadata_rating_key=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --rating-key)
                    [[ $# -ge 2 ]] || die_json "Missing value for --rating-key"
                    require_integer "--rating-key" "$2"
                    metadata_rating_key="$2"
                    shift 2
                    ;;
                -h|--help)
                    print_command_help "metadata"
                    exit 0
                    ;;
                *)
                    die_json "Unknown argument for metadata: $1"
                    ;;
            esac
        done
        [[ -n "${metadata_rating_key}" ]] || die_json "Missing required argument: --rating-key"
        resolve_config
        run_metadata "${metadata_rating_key}"
        ;;
    refresh-section)
        refresh_section_id=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --section-id)
                    [[ $# -ge 2 ]] || die_json "Missing value for --section-id"
                    require_integer "--section-id" "$2"
                    refresh_section_id="$2"
                    shift 2
                    ;;
                -h|--help)
                    print_command_help "refresh-section"
                    exit 0
                    ;;
                *)
                    die_json "Unknown argument for refresh-section: $1"
                    ;;
            esac
        done
        [[ -n "${refresh_section_id}" ]] || die_json "Missing required argument: --section-id"
        resolve_config
        run_refresh_section "${refresh_section_id}"
        ;;
    watchlist)
        watchlist_filter=""
        watchlist_sort=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --filter)
                    [[ $# -ge 2 ]] || die_json "Missing value for --filter"
                    watchlist_filter="$2"
                    shift 2
                    ;;
                --sort)
                    [[ $# -ge 2 ]] || die_json "Missing value for --sort"
                    watchlist_sort="$2"
                    shift 2
                    ;;
                -h|--help)
                    print_command_help "watchlist"
                    exit 0
                    ;;
                *)
                    die_json "Unknown argument for watchlist: $1"
                    ;;
            esac
        done
        resolve_config
        run_watchlist "${watchlist_filter}" "${watchlist_sort}"
        ;;
    *)
        die_json "Unknown command: ${COMMAND}"
        ;;
esac
