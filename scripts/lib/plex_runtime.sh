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
TIMEOUT=20
BASE_URL=""
TOKEN=""
REQUEST_ERROR=""
REQUEST_BODY=""
NORMALIZED_VALUE=""

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
        ping) echo "Usage: plex-runtime ping" ;;
        libraries) echo "Usage: plex-runtime libraries" ;;
        search) echo "Usage: plex-runtime search --query TEXT [--limit N]" ;;
        recently-added) echo "Usage: plex-runtime recently-added [--section-id ID] [--limit N]" ;;
        sessions) echo "Usage: plex-runtime sessions" ;;
        metadata) echo "Usage: plex-runtime metadata --rating-key KEY" ;;
        refresh-section) echo "Usage: plex-runtime refresh-section --section-id ID" ;;
        watchlist) echo "Usage: plex-runtime watchlist [--filter movie|show] [--sort SORT]" ;;
        *) print_main_help ;;
    esac
}

trim() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

normalize_spaces() {
    local value="${1-}"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//$'\t'/ }"
    while [[ "${value}" == *"  "* ]]; do
        value="${value//  / }"
    done
    printf '%s' "$(trim "${value}")"
}

json_escape() {
    local value="${1-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "${value}"
}

json_quote() {
    printf '"%s"' "$(json_escape "${1-}")"
}

json_string_or_null() {
    if [[ -z "${1+x}" || "${1}" == "__JSON_NULL__" ]]; then
        printf 'null'
    else
        json_quote "${1}"
    fi
}

json_number_or_null() {
    local value="${1-}"
    if [[ "${value}" =~ ^-?[0-9]+$ ]]; then
        printf '%s' "${value}"
    else
        printf 'null'
    fi
}

json_bool() {
    if [[ "${1-}" == "true" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

json_error() {
    printf '{"success":false,"error":%s}\n' "$(json_quote "$1")"
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

    NORMALIZED_VALUE="${value}"
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

    NORMALIZED_VALUE="${value}"
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

    normalize_base_url "${raw_base_url}"
    BASE_URL="${NORMALIZED_VALUE}"
    normalize_token "${raw_token}"
    TOKEN="${NORMALIZED_VALUE}"
}

urlencode() {
    local value="${1-}"
    local encoded=""
    local char=""
    local i=0

    for ((i = 0; i < ${#value}; i++)); do
        char="${value:i:1}"
        case "${char}" in
            [a-zA-Z0-9.~_-]) encoded+="${char}" ;;
            *)
                printf -v char_code '%%%02X' "'${char}"
                encoded+="${char_code}"
                ;;
        esac
    done

    printf '%s' "${encoded}"
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
    normalize_spaces "$1"
}

normalize_json_text() {
    normalize_spaces "$1"
}

extract_json_string() {
    local json="$1"
    local key="$2"
    if [[ "${json}" =~ \"${key}\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

extract_json_raw() {
    local json="$1"
    local key="$2"
    if [[ "${json}" =~ \"${key}\"[[:space:]]*:[[:space:]]*([^,}\]]+) ]]; then
        printf '%s' "$(trim "${BASH_REMATCH[1]}")"
        return 0
    fi
    return 1
}

extract_json_integer() {
    local json="$1"
    local key="$2"
    local value=""

    if value="$(extract_json_string "${json}" "${key}")"; then
        :
    elif value="$(extract_json_raw "${json}" "${key}")"; then
        :
    else
        return 1
    fi

    [[ "${value}" =~ ^-?[0-9]+$ ]] || return 1
    printf '%s' "${value}"
}

extract_json_scalar_or_null() {
    local json="$1"
    local key="$2"

    if extract_json_string "${json}" "${key}" >/dev/null; then
        extract_json_string "${json}" "${key}"
        return 0
    fi
    if extract_json_raw "${json}" "${key}" >/dev/null; then
        extract_json_raw "${json}" "${key}"
        return 0
    fi
    printf '__JSON_NULL__'
}

find_literal_index() {
    local haystack="$1"
    local needle="$2"
    local prefix=""

    prefix="${haystack%%"${needle}"*}"
    [[ "${prefix}" != "${haystack}" ]] || return 1
    printf '%s' "${#prefix}"
}

extract_json_block_after_key() {
    local json="$1"
    local key="$2"
    local open_char="$3"
    local close_char="$4"
    local needle="\"${key}\""
    local key_index=""
    local rest=""
    local i=0
    local char=""
    local start_index=-1
    local block=""
    local depth=0
    local in_string="false"
    local escaped="false"

    key_index="$(find_literal_index "${json}" "${needle}")" || return 1
    rest="${json:key_index + ${#needle}}"

    for ((i = 0; i < ${#rest}; i++)); do
        char="${rest:i:1}"
        if [[ "${char}" == "${open_char}" ]]; then
            start_index="${i}"
            break
        fi
    done

    [[ "${start_index}" -ge 0 ]] || return 1

    rest="${rest:start_index}"
    for ((i = 0; i < ${#rest}; i++)); do
        char="${rest:i:1}"
        block+="${char}"

        if [[ "${escaped}" == "true" ]]; then
            escaped="false"
            continue
        fi

        if [[ "${char}" == "\\" && "${in_string}" == "true" ]]; then
            escaped="true"
            continue
        fi

        if [[ "${char}" == '"' ]]; then
            if [[ "${in_string}" == "true" ]]; then
                in_string="false"
            else
                in_string="true"
            fi
            continue
        fi

        if [[ "${in_string}" == "true" ]]; then
            continue
        fi

        if [[ "${char}" == "${open_char}" ]]; then
            depth=$((depth + 1))
        elif [[ "${char}" == "${close_char}" ]]; then
            depth=$((depth - 1))
            if [[ "${depth}" -eq 0 ]]; then
                printf '%s' "${block}"
                return 0
            fi
        fi
    done

    return 1
}

split_json_array_objects() {
    local array_json="$1"
    local inner="${array_json:1:${#array_json}-2}"
    local i=0
    local char=""
    local item=""
    local depth=0
    local in_string="false"
    local escaped="false"
    local started="false"

    for ((i = 0; i < ${#inner}; i++)); do
        char="${inner:i:1}"

        if [[ "${started}" == "false" ]]; then
            [[ "${char}" == "{" ]] || continue
            started="true"
            depth=1
            item="{"
            continue
        fi

        item+="${char}"

        if [[ "${escaped}" == "true" ]]; then
            escaped="false"
            continue
        fi

        if [[ "${char}" == "\\" && "${in_string}" == "true" ]]; then
            escaped="true"
            continue
        fi

        if [[ "${char}" == '"' ]]; then
            if [[ "${in_string}" == "true" ]]; then
                in_string="false"
            else
                in_string="true"
            fi
            continue
        fi

        if [[ "${in_string}" == "true" ]]; then
            continue
        fi

        if [[ "${char}" == "{" ]]; then
            depth=$((depth + 1))
        elif [[ "${char}" == "}" ]]; then
            depth=$((depth - 1))
            if [[ "${depth}" -eq 0 ]]; then
                printf '%s\n' "${item}"
                item=""
                started="false"
            fi
        fi
    done
}

json_array_from_lines() {
    local lines=("$@")
    local json="["
    local i=0

    for ((i = 0; i < ${#lines[@]}; i++)); do
        [[ -n "${lines[i]}" ]] || continue
        if [[ "${json}" != "[" ]]; then
            json+=","
        fi
        json+="${lines[i]}"
    done
    json+="]"
    printf '%s' "${json}"
}

build_media_item_json() {
    local obj="$1"
    local type="__JSON_NULL__"
    local rating_key=""
    local title="__JSON_NULL__"
    local year=""
    local library_section_id=""
    local library_section_title="__JSON_NULL__"
    local parent_title="__JSON_NULL__"
    local grandparent_title="__JSON_NULL__"
    local summary="__JSON_NULL__"
    local duration=""
    local view_count=""
    local added_at=""
    local last_viewed_at=""

    type="$(extract_json_scalar_or_null "${obj}" "type")"
    title="$(extract_json_scalar_or_null "${obj}" "title")"
    library_section_title="$(extract_json_scalar_or_null "${obj}" "librarySectionTitle")"
    parent_title="$(extract_json_scalar_or_null "${obj}" "parentTitle")"
    grandparent_title="$(extract_json_scalar_or_null "${obj}" "grandparentTitle")"
    summary="$(extract_json_scalar_or_null "${obj}" "summary")"
    rating_key="$(extract_json_integer "${obj}" "ratingKey" || true)"
    year="$(extract_json_integer "${obj}" "year" || true)"
    library_section_id="$(extract_json_integer "${obj}" "librarySectionID" || true)"
    duration="$(extract_json_integer "${obj}" "duration" || true)"
    view_count="$(extract_json_integer "${obj}" "viewCount" || true)"
    added_at="$(extract_json_integer "${obj}" "addedAt" || true)"
    last_viewed_at="$(extract_json_integer "${obj}" "lastViewedAt" || true)"

    printf '{'
    printf '"type":%s,' "$(json_string_or_null "${type}")"
    printf '"ratingKey":%s,' "$(json_number_or_null "${rating_key}")"
    printf '"title":%s,' "$(json_string_or_null "${title}")"
    printf '"year":%s,' "$(json_number_or_null "${year}")"
    printf '"librarySectionID":%s,' "$(json_number_or_null "${library_section_id}")"
    printf '"librarySectionTitle":%s,' "$(json_string_or_null "${library_section_title}")"
    printf '"parentTitle":%s,' "$(json_string_or_null "${parent_title}")"
    printf '"grandparentTitle":%s,' "$(json_string_or_null "${grandparent_title}")"
    printf '"summary":%s,' "$(json_string_or_null "${summary}")"
    printf '"duration":%s,' "$(json_number_or_null "${duration}")"
    printf '"viewCount":%s,' "$(json_number_or_null "${view_count}")"
    printf '"addedAt":%s,' "$(json_number_or_null "${added_at}")"
    printf '"lastViewedAt":%s' "$(json_number_or_null "${last_viewed_at}")"
    printf '}'
}

collect_media_items() {
    local json="$1"
    local limit="$2"
    local items=()
    local count=0
    local array_json=""
    local obj=""
    local hub_array=""
    local hub_obj=""
    local hub_metadata=""

    for key in Directory Video Metadata; do
        if array_json="$(extract_json_block_after_key "${json}" "${key}" "[" "]" 2>/dev/null)"; then
            while IFS= read -r obj; do
                [[ -n "${obj}" ]] || continue
                if [[ -n "${limit}" && "${count}" -ge "${limit}" ]]; then
                    break 2
                fi
                items+=("$(build_media_item_json "${obj}")")
                count=$((count + 1))
            done < <(split_json_array_objects "${array_json}")
        fi
    done

    if [[ -z "${limit}" || "${count}" -lt "${limit}" ]]; then
        if hub_array="$(extract_json_block_after_key "${json}" "Hub" "[" "]" 2>/dev/null)"; then
            while IFS= read -r hub_obj; do
                [[ -n "${hub_obj}" ]] || continue
                if hub_metadata="$(extract_json_block_after_key "${hub_obj}" "Metadata" "[" "]" 2>/dev/null)"; then
                    while IFS= read -r obj; do
                        [[ -n "${obj}" ]] || continue
                        if [[ -n "${limit}" && "${count}" -ge "${limit}" ]]; then
                            break 3
                        fi
                        items+=("$(build_media_item_json "${obj}")")
                        count=$((count + 1))
                    done < <(split_json_array_objects "${hub_metadata}")
                fi
            done < <(split_json_array_objects "${hub_array}")
        fi
    fi

    json_array_from_lines "${items[@]}"
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
    local header_line=""

    REQUEST_ERROR=""
    REQUEST_BODY=""

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
        REQUEST_ERROR="Connection failed for ${path_label}: $(clean_error_text "${stderr_text}")"
        rm -f "${headers_file}" "${body_file}" "${stderr_file}"
        return 1
    fi

    while IFS= read -r header_line || [[ -n "${header_line}" ]]; do
        header_line="${header_line%$'\r'}"
        if [[ "${header_line}" == HTTP/* ]]; then
            http_code="${header_line#HTTP/* }"
            http_code="${http_code%% *}"
        fi
    done < "${headers_file}"

    if [[ -n "${http_code}" && "${http_code}" =~ ^[0-9]+$ && "${http_code}" -ge 400 ]]; then
        body_snippet="$(<"${body_file}")"
        body_snippet="${body_snippet:0:300}"
        REQUEST_ERROR="Plex API HTTP ${http_code} on ${path_label}: $(clean_error_text "${body_snippet}")"
        rm -f "${headers_file}" "${body_file}" "${stderr_file}"
        return 1
    fi

    REQUEST_BODY="$(<"${body_file}")"
    rm -f "${headers_file}" "${body_file}" "${stderr_file}"
}

require_integer() {
    local name="$1"
    local value="$2"
    [[ "${value}" =~ ^-?[0-9]+$ ]] || die_json "${name} must be an integer"
}

run_ping() {
    local raw_json=""
    local json=""
    local friendly_name="__JSON_NULL__"
    local version="__JSON_NULL__"
    local machine_identifier="__JSON_NULL__"
    local platform="__JSON_NULL__"
    local updated_at=""

    request_json "${BASE_URL}/" "/" || die_json "${REQUEST_ERROR}"
    raw_json="${REQUEST_BODY}"
    json="$(normalize_json_text "${raw_json}")"
    friendly_name="$(extract_json_scalar_or_null "${json}" "friendlyName")"
    version="$(extract_json_scalar_or_null "${json}" "version")"
    machine_identifier="$(extract_json_scalar_or_null "${json}" "machineIdentifier")"
    platform="$(extract_json_scalar_or_null "${json}" "platform")"
    updated_at="$(extract_json_integer "${json}" "updatedAt" || true)"

    printf '{"success":true,"server":{"friendlyName":%s,"version":%s,"machineIdentifier":%s,"platform":%s,"updatedAt":%s}}\n' \
        "$(json_string_or_null "${friendly_name}")" \
        "$(json_string_or_null "${version}")" \
        "$(json_string_or_null "${machine_identifier}")" \
        "$(json_string_or_null "${platform}")" \
        "$(json_number_or_null "${updated_at}")"
}

run_libraries() {
    local raw_json=""
    local json=""
    local array_json=""
    local items=()
    local obj=""
    local key=""
    local title=""
    local type=""
    local agent=""
    local scanner=""
    local language=""
    local updated_at=""
    local scanned_at=""

    request_json "${BASE_URL}/library/sections" "/library/sections" || die_json "${REQUEST_ERROR}"
    raw_json="${REQUEST_BODY}"
    json="$(normalize_json_text "${raw_json}")"

    if array_json="$(extract_json_block_after_key "${json}" "Directory" "[" "]" 2>/dev/null)"; then
        while IFS= read -r obj; do
            [[ -n "${obj}" ]] || continue
            key="$(extract_json_integer "${obj}" "key" || true)"
            title="$(extract_json_scalar_or_null "${obj}" "title")"
            type="$(extract_json_scalar_or_null "${obj}" "type")"
            agent="$(extract_json_scalar_or_null "${obj}" "agent")"
            scanner="$(extract_json_scalar_or_null "${obj}" "scanner")"
            language="$(extract_json_scalar_or_null "${obj}" "language")"
            updated_at="$(extract_json_integer "${obj}" "updatedAt" || true)"
            scanned_at="$(extract_json_integer "${obj}" "scannedAt" || true)"
            items+=("{\"key\":$(json_number_or_null "${key}"),\"title\":$(json_string_or_null "${title}"),\"type\":$(json_string_or_null "${type}"),\"agent\":$(json_string_or_null "${agent}"),\"scanner\":$(json_string_or_null "${scanner}"),\"language\":$(json_string_or_null "${language}"),\"updatedAt\":$(json_number_or_null "${updated_at}"),\"scannedAt\":$(json_number_or_null "${scanned_at}")}")
        done < <(split_json_array_objects "${array_json}")
    fi

    printf '{"success":true,"count":%s,"libraries":%s}\n' "${#items[@]}" "$(json_array_from_lines "${items[@]}")"
}

run_search() {
    local query="$1"
    local limit="$2"
    local path="/search"
    local raw_json=""
    local request_url=""
    local items_json=""
    local count=0

    request_url="${BASE_URL}${path}$(build_query "query" "${query}" "X-Plex-Container-Size" "${limit}")"
    request_json "${request_url}" "${path}" || die_json "${REQUEST_ERROR}"
    raw_json="${REQUEST_BODY}"
    items_json="$(collect_media_items "$(normalize_json_text "${raw_json}")" "${limit}")"
    count="$(count_json_objects_in_array "${items_json}")"

    printf '{"success":true,"query":%s,"count":%s,"items":%s}\n' "$(json_quote "${query}")" "${count}" "${items_json}"
}

run_recently_added() {
    local section_id="${1-}"
    local limit="$2"
    local path="/library/recentlyAdded"
    local request_url=""
    local raw_json=""
    local items_json=""
    local count=0

    if [[ -n "${section_id}" ]]; then
        path="/library/sections/${section_id}/recentlyAdded"
    fi

    request_url="${BASE_URL}${path}$(build_query "X-Plex-Container-Start" "0" "X-Plex-Container-Size" "${limit}")"
    request_json "${request_url}" "${path}" || die_json "${REQUEST_ERROR}"
    raw_json="${REQUEST_BODY}"
    items_json="$(collect_media_items "$(normalize_json_text "${raw_json}")" "${limit}")"
    count="$(count_json_objects_in_array "${items_json}")"

    printf '{"success":true,"sectionId":%s,"count":%s,"items":%s}\n' "$(json_number_or_null "${section_id}")" "${count}" "${items_json}"
}

run_sessions() {
    local raw_json=""
    local json=""
    local items=()
    local array_json=""
    local obj=""
    local user_obj=""
    local player_obj=""
    local rating_key=""
    local title=""
    local type=""
    local year=""
    local username=""
    local player=""
    local state=""

    request_json "${BASE_URL}/status/sessions" "/status/sessions" || die_json "${REQUEST_ERROR}"
    raw_json="${REQUEST_BODY}"
    json="$(normalize_json_text "${raw_json}")"

    for key in Video Metadata; do
        if array_json="$(extract_json_block_after_key "${json}" "${key}" "[" "]" 2>/dev/null)"; then
            while IFS= read -r obj; do
                [[ -n "${obj}" ]] || continue
                rating_key="$(extract_json_integer "${obj}" "ratingKey" || true)"
                title="$(extract_json_scalar_or_null "${obj}" "title")"
                type="$(extract_json_scalar_or_null "${obj}" "type")"
                year="$(extract_json_integer "${obj}" "year" || true)"
                username="__JSON_NULL__"
                player="__JSON_NULL__"
                state="__JSON_NULL__"
                if user_obj="$(extract_json_block_after_key "${obj}" "User" "{" "}" 2>/dev/null)"; then
                    username="$(extract_json_scalar_or_null "${user_obj}" "title")"
                fi
                if player_obj="$(extract_json_block_after_key "${obj}" "Player" "{" "}" 2>/dev/null)"; then
                    player="$(extract_json_scalar_or_null "${player_obj}" "product")"
                    state="$(extract_json_scalar_or_null "${player_obj}" "state")"
                fi
                items+=("{\"ratingKey\":$(json_number_or_null "${rating_key}"),\"title\":$(json_string_or_null "${title}"),\"type\":$(json_string_or_null "${type}"),\"year\":$(json_number_or_null "${year}"),\"username\":$(json_string_or_null "${username}"),\"player\":$(json_string_or_null "${player}"),\"state\":$(json_string_or_null "${state}")}")
            done < <(split_json_array_objects "${array_json}")
        fi
    done

    printf '{"success":true,"count":%s,"sessions":%s}\n' "${#items[@]}" "$(json_array_from_lines "${items[@]}")"
}

run_metadata() {
    local rating_key="$1"
    local path="/library/metadata/${rating_key}"
    local raw_json=""
    local items_json=""
    local count=0
    local found="false"

    request_json "${BASE_URL}${path}" "${path}" || die_json "${REQUEST_ERROR}"
    raw_json="${REQUEST_BODY}"
    items_json="$(collect_media_items "$(normalize_json_text "${raw_json}")" "")"
    count="$(count_json_objects_in_array "${items_json}")"
    [[ "${count}" -gt 0 ]] && found="true"

    printf '{"success":true,"ratingKey":%s,"found":%s,"items":%s}\n' "${rating_key}" "$(json_bool "${found}")" "${items_json}"
}

run_refresh_section() {
    local section_id="$1"
    local path="/library/sections/${section_id}/refresh"

    request_json "${BASE_URL}${path}" "${path}" "GET" >/dev/null || die_json "${REQUEST_ERROR}"
    printf '{"success":true,"sectionId":%s,"message":"refresh triggered"}\n' "${section_id}"
}

run_watchlist() {
    local filter="${1-}"
    local sort="${2-}"
    local request_url=""
    local raw_json=""
    local json=""
    local media_type=""
    local path="/library/sections/watchlist/all"
    local array_json=""
    local items=()
    local obj=""
    local type=""
    local title=""
    local year=""
    local guid=""
    local summary=""
    local rating_key=""

    case "${filter}" in
        "") media_type="" ;;
        movie) media_type="1" ;;
        show) media_type="2" ;;
        *) die_json "Invalid watchlist filter: ${filter}" ;;
    esac

    request_url="${DISCOVER_BASE_URL}${path}$(build_query \
        "includeCollections" "1" \
        "includeExternalMedia" "1" \
        "sort" "${sort}" \
        "type" "${media_type}")"

    request_json "${request_url}" "${path}" || die_json "${REQUEST_ERROR}"
    raw_json="${REQUEST_BODY}"
    json="$(normalize_json_text "${raw_json}")"

    if array_json="$(extract_json_block_after_key "${json}" "Metadata" "[" "]" 2>/dev/null)"; then
        while IFS= read -r obj; do
            [[ -n "${obj}" ]] || continue
            type="$(extract_json_scalar_or_null "${obj}" "type")"
            title="$(extract_json_scalar_or_null "${obj}" "title")"
            year="$(extract_json_integer "${obj}" "year" || true)"
            guid="$(extract_json_scalar_or_null "${obj}" "guid")"
            if [[ "${guid}" == "__JSON_NULL__" ]]; then
                guid="$(extract_json_scalar_or_null "${obj}" "id")"
            fi
            summary="$(extract_json_scalar_or_null "${obj}" "summary")"
            if [[ "${summary}" != "__JSON_NULL__" && ${#summary} -gt 200 ]]; then
                summary="${summary:0:200}"
            fi
            rating_key="$(extract_json_integer "${obj}" "ratingKey" || true)"
            items+=("{\"type\":$(json_string_or_null "${type}"),\"title\":$(json_string_or_null "${title}"),\"year\":$(json_number_or_null "${year}"),\"guid\":$(json_string_or_null "${guid}"),\"ratingKey\":$(json_number_or_null "${rating_key}"),\"summary\":$(json_string_or_null "${summary}")}")
        done < <(split_json_array_objects "${array_json}")
    fi

    printf '{"success":true,"count":%s,"items":%s}\n' "${#items[@]}" "$(json_array_from_lines "${items[@]}")"
}

count_json_objects_in_array() {
    local array_json="$1"
    local count=0
    local _
    while IFS= read -r _; do
        [[ -n "${_}" ]] || continue
        count=$((count + 1))
    done < <(split_json_array_objects "${array_json}")
    printf '%s' "${count}"
}

load_dotenv
BASE_URL="${PLEX_BASE_URL-}"
TOKEN="${PLEX_TOKEN-}"
ensure_command "${CURL_BIN}"

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
