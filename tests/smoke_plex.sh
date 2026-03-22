#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
SOURCE_SCRIPT="${REPO_ROOT}/scripts/lib/plex_runtime.sh"
SOURCE_COMMANDS_DIR="${REPO_ROOT}/scripts/commands"
FIXTURES_DIR="${TEST_DIR}/fixtures"
MOCK_CURL="${TEST_DIR}/mocks/mock_curl.sh"
JQ_BIN="${PLEX_JQ_BIN:-$(command -v jq)}"

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
    cp "${SOURCE_SCRIPT}" "${root}/scripts/lib/plex_runtime.sh"
    cp -R "${SOURCE_COMMANDS_DIR}" "${root}/scripts/commands"
    chmod +x "${root}/scripts/lib/plex_runtime.sh"
    cp "${REPO_ROOT}/.env.example" "${root}/.env.example"
    printf 'PLEX_BASE_URL=http://env.example:32400\nPLEX_TOKEN=env-token\n' > "${root}/.env"
    echo "${root}"
}

run_cli() {
    local skill_root="$1"
    local command_path="$2"
    shift
    shift

    MOCK_CURL_FIXTURES_DIR="${FIXTURES_DIR}" \
    PLEX_CURL_BIN="${MOCK_CURL}" \
    PLEX_JQ_BIN="${JQ_BIN}" \
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

test_missing_config_returns_json_error() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""

    skill_root="$(create_skill_root)"
    rm -f "${skill_root}/.env"

    output_file="$(mktemp)"
    status_file="$(mktemp)"
    run_cli_capture "${output_file}" "${status_file}" "${skill_root}" "scripts/commands/server/ping.sh"
    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "1" "${status}" "missing config exit code"
    assert_eq "false" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.success')" "missing config success flag"
    assert_contains "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.error')" ".env.example" "missing config error"

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
    PLEX_JQ_BIN="${JQ_BIN}" \
    "${skill_root}/scripts/commands/server/ping.sh" \
        --base-url "http://127.0.0.1:32400/" \
        --token "secret" \
        > "${output_file}" 2>&1
    printf '%s' "$?" > "${status_file}"
    set -e

    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "0" "${status}" "ping exit code"
    assert_eq "true" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.success')" "ping success flag"
    assert_eq "Test Server" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.server.friendlyName')" "ping server name"
    assert_eq "GET http://127.0.0.1:32400/" "$(<"${request_log}")" "ping request url"

    rm -rf "${skill_root}" "${output_file}" "${status_file}" "${request_log}"
}

test_python_cli_ping_success() {
    local skill_root=""
    local output_file=""
    local status_file=""
    local output=""
    local status=""
    local request_log=""

    skill_root="$(create_skill_root)"
    cp "${REPO_ROOT}/scripts/plex_cli.py" "${skill_root}/scripts/plex_cli.py"
    request_log="$(mktemp)"
    output_file="$(mktemp)"
    status_file="$(mktemp)"

    set +e
    MOCK_CURL_FIXTURES_DIR="${FIXTURES_DIR}" \
    MOCK_CURL_LOG="${request_log}" \
    PLEX_CURL_BIN="${MOCK_CURL}" \
    PLEX_JQ_BIN="${JQ_BIN}" \
    python3 "${skill_root}/scripts/plex_cli.py" \
        --base-url "http://127.0.0.1:32400/" \
        --token "secret" \
        ping \
        > "${output_file}" 2>&1
    printf '%s' "$?" > "${status_file}"
    set -e

    output="$(<"${output_file}")"
    status="$(<"${status_file}")"

    assert_eq "0" "${status}" "python cli ping exit code"
    assert_eq "true" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.success')" "python cli ping success flag"
    assert_eq "Test Server" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.server.friendlyName')" "python cli ping server name"
    assert_eq "GET http://127.0.0.1:32400/" "$(<"${request_log}")" "python cli ping request url"

    rm -rf "${skill_root}" "${output_file}" "${status_file}" "${request_log}"
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

    assert_eq "true" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.success')" "libraries success flag"
    assert_eq "1" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.count')" "libraries count"
    assert_eq "Movies" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.libraries[0].title')" "libraries title"
    assert_eq "GET http://env.example:32400/library/sections" "$(<"${request_log}")" "libraries request url"

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

    assert_eq "true" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.success')" "watchlist success flag"
    assert_eq "null" "$(printf '%s' "${output}" | "${JQ_BIN}" -r '.items[0].ratingKey')" "watchlist rating key"
    assert_contains "${request_line}" "https://discover.provider.plex.tv/library/sections/watchlist/all" "watchlist endpoint"
    assert_contains "${request_line}" "sort=titleSort%3Aasc" "watchlist sort param"
    assert_contains "${request_line}" "type=1" "watchlist media type param"

    rm -rf "${skill_root}" "${request_log}"
}

test_missing_config_returns_json_error
test_flags_override_and_ping_success
test_python_cli_ping_success
test_env_file_loaded_for_libraries
test_watchlist_uses_discover_endpoint_and_sanitizes_rating_key

echo "All tests passed."
