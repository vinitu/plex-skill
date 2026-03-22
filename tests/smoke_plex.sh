#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
SOURCE_SCRIPT="${REPO_ROOT}/scripts/lib/plex_runtime.sh"
SOURCE_COMMANDS_DIR="${REPO_ROOT}/scripts/commands"
FIXTURES_DIR="${TEST_DIR}/fixtures"
MOCK_CURL="${TEST_DIR}/mocks/mock_curl.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    [[ "${expected}" == "${actual}" ]] || fail "${message}: expected '${expected}', got '${actual}'"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "${haystack}" == *"${needle}"* ]] || fail "${message}: missing '${needle}'"
}

create_skill_root() {
    local root=""
    root="$(mktemp -d)"
    mkdir -p "${root}/scripts"
    mkdir -p "${root}/scripts/lib"
    mkdir -p "${root}/assets"
    cp "${SOURCE_SCRIPT}" "${root}/scripts/lib/plex_runtime.sh"
    cp -R "${SOURCE_COMMANDS_DIR}" "${root}/scripts/commands"
    chmod +x "${root}/scripts/lib/plex_runtime.sh"
    cp "${REPO_ROOT}/assets/env.example" "${root}/assets/env.example"
    printf 'PLEX_BASE_URL=http://env.example:32400\nPLEX_TOKEN=env-token\n' > "${root}/assets/env"
    echo "${root}"
}

run_cli() {
    local skill_root="$1"
    local command_path="$2"
    shift
    shift

    MOCK_CURL_FIXTURES_DIR="${FIXTURES_DIR}" \
    PLEX_CURL_BIN="${MOCK_CURL}" \
    "${skill_root}/${command_path}" "$@"
}

run_cli_capture() {
    local output_file="$1"
    local status_file="$2"
    local skill_root="$3"
    local command_path="$4"
    shift 4

    set +e
    run_cli "${skill_root}" "${command_path}" "$@" > "${output_file}" 2>&1
    printf '%s' "$?" > "${status_file}"
    set -e
}

assert_output_contains() {
    local output="$1"
    local needle="$2"
    local message="$3"
    assert_contains "${output}" "${needle}" "${message}"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "${haystack}" != *"${needle}"* ]] || fail "${message}: should not contain '${needle}'"
}

test_missing_config_returns_json_error() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""

    skill_root="$(create_skill_root)"
    rm -f "${skill_root}/assets/env"

    output_file="$(mktemp)"
    status_file="$(mktemp)"
    run_cli_capture "${output_file}" "${status_file}" "${skill_root}" "scripts/commands/server/ping.sh"
    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "1" "${status}" "missing config exit code"
    assert_output_contains "${output}" '"success":false' "missing config success flag"
    assert_output_contains "${output}" 'assets/env.example' "missing config error"

    rm -rf "${skill_root}" "${output_file}" "${status_file}"
}

test_placeholder_config_returns_json_error() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""

    skill_root="$(create_skill_root)"
    cp "${REPO_ROOT}/assets/env.example" "${skill_root}/assets/env"

    output_file="$(mktemp)"
    status_file="$(mktemp)"
    run_cli_capture "${output_file}" "${status_file}" "${skill_root}" "scripts/commands/server/ping.sh"
    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "1" "${status}" "placeholder config exit code"
    assert_output_contains "${output}" '"success":false' "placeholder config success flag"
    assert_output_contains "${output}" 'placeholder' "placeholder config error"

    rm -rf "${skill_root}" "${output_file}" "${status_file}"
}

test_flags_override_and_ping_success() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""
    local request_log=""

    skill_root="$(create_skill_root)"
    request_log="$(mktemp)"
    output_file="$(mktemp)"
    status_file="$(mktemp)"

    set +e
    MOCK_CURL_FIXTURES_DIR="${FIXTURES_DIR}" \
    MOCK_CURL_LOG="${request_log}" \
    PLEX_CURL_BIN="${MOCK_CURL}" \
    "${skill_root}/scripts/commands/server/ping.sh" \
        --base-url "http://127.0.0.1:32400/" \
        --token "secret" \
        > "${output_file}" 2>&1
    printf '%s' "$?" > "${status_file}"
    set -e

    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "0" "${status}" "ping exit code"
    assert_output_contains "${output}" '"success":true' "ping success flag"
    assert_output_contains "${output}" '"friendlyName":"Test Server"' "ping server name"
    assert_eq "GET http://127.0.0.1:32400/" "$(<"${request_log}")" "ping request url"

    rm -rf "${skill_root}" "${output_file}" "${status_file}" "${request_log}"
}

test_requests_use_insecure_curl_by_default() {
    local skill_root=""
    local output=""
    local request_log=""
    local curl_wrapper=""
    local flag_log=""

    skill_root="$(create_skill_root)"
    request_log="$(mktemp)"
    flag_log="$(mktemp)"
    curl_wrapper="$(mktemp)"

    cat > "${curl_wrapper}" <<EOF
#!/usr/bin/env bash
flag_found=0
for arg in "\$@"; do
    if [[ "\$arg" == "-k" ]]; then
        flag_found=1
        break
    fi
done
printf '%s' "\$flag_found" > "${flag_log}"
exec "${MOCK_CURL}" "\$@"
EOF
    chmod +x "${curl_wrapper}"

    cat > "${skill_root}/assets/env" <<EOF
PLEX_BASE_URL=http://env.example:32400
PLEX_TOKEN=env-token
PLEX_CURL_BIN=${curl_wrapper}
EOF

    output="$(
        MOCK_CURL_FIXTURES_DIR="${FIXTURES_DIR}" \
        MOCK_CURL_LOG="${request_log}" \
        "${skill_root}/scripts/commands/server/ping.sh" \
            --base-url "http://127.0.0.1:32400/" \
            --token "secret"
    )"

    assert_output_contains "${output}" '"success":true' "default insecure curl success flag"
    assert_eq "1" "$(<"${flag_log}")" "default insecure curl flag"
    assert_eq "GET http://127.0.0.1:32400/" "$(<"${request_log}")" "default insecure request url"

    rm -rf "${skill_root}" "${request_log}" "${curl_wrapper}" "${flag_log}"
}

test_env_file_loaded_for_libraries() {
    local skill_root=""
    local output=""
    local request_log=""

    skill_root="$(create_skill_root)"
    request_log="$(mktemp)"
    output="$(
        MOCK_CURL_LOG="${request_log}" \
        run_cli "${skill_root}" "scripts/commands/server/libraries.sh"
    )"

    assert_output_contains "${output}" '"success":true' "libraries success flag"
    assert_output_contains "${output}" '"count":1' "libraries count"
    assert_output_contains "${output}" '"title":"Movies"' "libraries title"
    assert_eq "GET http://env.example:32400/library/sections" "$(<"${request_log}")" "libraries request url"

    rm -rf "${skill_root}" "${request_log}"
}

test_search_returns_query_and_encoded_request() {
    local skill_root=""
    local output=""
    local request_log=""

    skill_root="$(create_skill_root)"
    request_log="$(mktemp)"
    output="$(
        MOCK_CURL_LOG="${request_log}" \
        run_cli "${skill_root}" "scripts/commands/server/search.sh" --query "Alien (1979)" --limit 5
    )"

    assert_output_contains "${output}" '"success":true' "search success flag"
    assert_output_contains "${output}" '"query":"Alien (1979)"' "search echoes query"
    assert_output_contains "${output}" '"count":1' "search count"
    assert_output_contains "${output}" '"title":"Alien"' "search item title"
    assert_contains "$(<"${request_log}")" "query=Alien%20%281979%29" "search request query encoding"
    assert_contains "$(<"${request_log}")" "X-Plex-Container-Size=5" "search request limit"

    rm -rf "${skill_root}" "${request_log}"
}

test_recently_added_section_route_and_section_id() {
    local skill_root=""
    local output=""
    local request_log=""

    skill_root="$(create_skill_root)"
    request_log="$(mktemp)"
    output="$(
        MOCK_CURL_LOG="${request_log}" \
        run_cli "${skill_root}" "scripts/commands/server/recently_added.sh" --section-id 3 --limit 2
    )"

    assert_output_contains "${output}" '"success":true' "recently-added success flag"
    assert_output_contains "${output}" '"sectionId":3' "recently-added section id"
    assert_output_contains "${output}" '"count":1' "recently-added count"
    assert_contains "$(<"${request_log}")" "/library/sections/3/recentlyAdded" "recently-added section route"
    assert_contains "$(<"${request_log}")" "X-Plex-Container-Size=2" "recently-added limit"

    rm -rf "${skill_root}" "${request_log}"
}

test_sessions_returns_session_fields() {
    local skill_root=""
    local output=""

    skill_root="$(create_skill_root)"
    output="$(run_cli "${skill_root}" "scripts/commands/server/sessions.sh")"

    assert_output_contains "${output}" '"success":true' "sessions success flag"
    assert_output_contains "${output}" '"count":1' "sessions count"
    assert_output_contains "${output}" '"username":"demo-user"' "sessions username"
    assert_output_contains "${output}" '"player":"Plex Web"' "sessions player"
    assert_output_contains "${output}" '"state":"playing"' "sessions state"

    rm -rf "${skill_root}"
}

test_metadata_returns_found_item() {
    local skill_root=""
    local output=""

    skill_root="$(create_skill_root)"
    output="$(run_cli "${skill_root}" "scripts/commands/server/metadata.sh" --rating-key 12345)"

    assert_output_contains "${output}" '"success":true' "metadata success flag"
    assert_output_contains "${output}" '"ratingKey":12345' "metadata rating key"
    assert_output_contains "${output}" '"found":true' "metadata found flag"
    assert_output_contains "${output}" '"title":"Alien"' "metadata title"

    rm -rf "${skill_root}"
}

test_refresh_section_returns_success_envelope() {
    local skill_root=""
    local output=""
    local request_log=""

    skill_root="$(create_skill_root)"
    request_log="$(mktemp)"
    output="$(
        MOCK_CURL_LOG="${request_log}" \
        run_cli "${skill_root}" "scripts/commands/server/refresh_section.sh" --section-id 2
    )"

    assert_output_contains "${output}" '"success":true' "refresh success flag"
    assert_output_contains "${output}" '"sectionId":2' "refresh section id"
    assert_output_contains "${output}" '"message":"refresh triggered"' "refresh message"
    assert_eq "GET http://env.example:32400/library/sections/2/refresh" "$(<"${request_log}")" "refresh request url"

    rm -rf "${skill_root}" "${request_log}"
}

test_watchlist_uses_discover_endpoint_and_sanitizes_rating_key() {
    local skill_root=""
    local output=""
    local request_log=""
    local request_line=""

    skill_root="$(create_skill_root)"
    request_log="$(mktemp)"
    output="$(
        MOCK_CURL_LOG="${request_log}" \
        run_cli "${skill_root}" "scripts/commands/watchlist/list.sh" --filter movie --sort titleSort:asc
    )"
    request_line="$(<"${request_log}")"

    assert_output_contains "${output}" '"success":true' "watchlist success flag"
    assert_output_contains "${output}" '"ratingKey":null' "watchlist rating key"
    assert_contains "${request_line}" "https://discover.provider.plex.tv/library/sections/watchlist/all" "watchlist endpoint"
    assert_contains "${request_line}" "sort=titleSort%3Aasc" "watchlist sort param"
    assert_contains "${request_line}" "type=1" "watchlist media type param"

    rm -rf "${skill_root}" "${request_log}"
}

test_invalid_watchlist_filter_returns_json_error() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""

    skill_root="$(create_skill_root)"
    output_file="$(mktemp)"
    status_file="$(mktemp)"
    run_cli_capture "${output_file}" "${status_file}" "${skill_root}" "scripts/commands/watchlist/list.sh" --filter album
    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "1" "${status}" "invalid watchlist filter exit code"
    assert_output_contains "${output}" '"success":false' "invalid watchlist filter success flag"
    assert_output_contains "${output}" 'Invalid watchlist filter' "invalid watchlist filter error"

    rm -rf "${skill_root}" "${output_file}" "${status_file}"
}

test_missing_search_query_returns_json_error() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""

    skill_root="$(create_skill_root)"
    output_file="$(mktemp)"
    status_file="$(mktemp)"
    run_cli_capture "${output_file}" "${status_file}" "${skill_root}" "scripts/commands/server/search.sh"
    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "1" "${status}" "missing search query exit code"
    assert_output_contains "${output}" '"success":false' "missing search query success flag"
    assert_output_contains "${output}" 'Missing required argument: --query' "missing search query error"

    rm -rf "${skill_root}" "${output_file}" "${status_file}"
}

test_network_error_returns_json_error() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""

    skill_root="$(create_skill_root)"
    output_file="$(mktemp)"
    status_file="$(mktemp)"

    set +e
    MOCK_CURL_MODE="network_error" \
    MOCK_CURL_FIXTURES_DIR="${FIXTURES_DIR}" \
    PLEX_CURL_BIN="${MOCK_CURL}" \
    "${skill_root}/scripts/commands/server/ping.sh" > "${output_file}" 2>&1
    printf '%s' "$?" > "${status_file}"
    set -e

    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "1" "${status}" "network error exit code"
    assert_output_contains "${output}" '"success":false' "network error success flag"
    assert_output_contains "${output}" 'Connection failed for /' "network error message"
    assert_output_contains "${output}" 'mock network error' "network stderr message"

    rm -rf "${skill_root}" "${output_file}" "${status_file}"
}

test_http_error_returns_json_error() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""

    skill_root="$(create_skill_root)"
    output_file="$(mktemp)"
    status_file="$(mktemp)"

    set +e
    MOCK_CURL_HTTP_CODE="404" \
    MOCK_CURL_BODY='{"error":"missing"}' \
    MOCK_CURL_FIXTURES_DIR="${FIXTURES_DIR}" \
    PLEX_CURL_BIN="${MOCK_CURL}" \
    "${skill_root}/scripts/commands/server/ping.sh" \
        --base-url "http://127.0.0.1:32400/" \
        --token "secret" \
        > "${output_file}" 2>&1
    printf '%s' "$?" > "${status_file}"
    set -e

    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "1" "${status}" "http error exit code"
    assert_output_contains "${output}" '"success":false' "http error success flag"
    assert_output_contains "${output}" 'Plex API HTTP 404 on /' "http error message"
    assert_output_contains "${output}" 'missing' "http error body"

    rm -rf "${skill_root}" "${output_file}" "${status_file}"
}

test_missing_config_returns_json_error
test_placeholder_config_returns_json_error
test_flags_override_and_ping_success
test_requests_use_insecure_curl_by_default
test_env_file_loaded_for_libraries
test_search_returns_query_and_encoded_request
test_recently_added_section_route_and_section_id
test_sessions_returns_session_fields
test_metadata_returns_found_item
test_refresh_section_returns_success_envelope
test_watchlist_uses_discover_endpoint_and_sanitizes_rating_key
test_invalid_watchlist_filter_returns_json_error
test_missing_search_query_returns_json_error
test_network_error_returns_json_error
test_http_error_returns_json_error

echo "All tests passed."
