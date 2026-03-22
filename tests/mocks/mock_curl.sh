#!/usr/bin/env bash

set -euo pipefail

headers_file=""
body_file=""
method="GET"
url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -X)
            method="$2"
            shift 2
            ;;
        -D)
            headers_file="$2"
            shift 2
            ;;
        -o)
            body_file="$2"
            shift 2
            ;;
        -H|--connect-timeout|--max-time)
            shift 2
            ;;
        -s|-S|-sS)
            shift
            ;;
        http://*|https://*)
            url="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ "${MOCK_CURL_MODE:-}" == "network_error" ]]; then
    echo "mock network error" >&2
    exit 7
fi

mock_http_code="${MOCK_CURL_HTTP_CODE:-200}"
mock_content_type="${MOCK_CURL_CONTENT_TYPE:-application/json}"
mock_body="${MOCK_CURL_BODY:-}"

[[ -n "${headers_file}" ]] || {
    echo "missing headers output" >&2
    exit 1
}

[[ -n "${body_file}" ]] || {
    echo "missing body output" >&2
    exit 1
}

fixture=""
if [[ "${url}" == "https://discover.provider.plex.tv/library/sections/watchlist/all"* ]]; then
    fixture="watchlist.json"
elif [[ "${url}" == "http://127.0.0.1:32400/" ]]; then
    fixture="ping.json"
elif [[ "${url}" == "http://env.example:32400/library/sections" ]]; then
    fixture="libraries.json"
elif [[ "${url}" == "http://env.example:32400/library/recentlyAdded"* ]]; then
    fixture="recently-added.json"
elif [[ "${url}" == "http://env.example:32400/library/sections/"*"/recentlyAdded"* ]]; then
    fixture="recently-added.json"
elif [[ "${url}" == "http://env.example:32400/status/sessions" ]]; then
    fixture="sessions.json"
elif [[ "${url}" == "http://env.example:32400/library/metadata/"* ]]; then
    fixture="metadata.json"
elif [[ "${url}" == "http://env.example:32400/search"* ]]; then
    fixture="search.json"
elif [[ "${url}" == "http://env.example:32400/library/sections/"*"/refresh" ]]; then
    fixture=""
else
    echo "unexpected url: ${url}" >&2
    exit 1
fi

if [[ -n "${MOCK_CURL_LOG:-}" ]]; then
    printf '%s %s\n' "${method}" "${url}" >> "${MOCK_CURL_LOG}"
fi

printf 'HTTP/1.1 %s Mock\r\nContent-Type: %s\r\n\r\n' "${mock_http_code}" "${mock_content_type}" > "${headers_file}"

if [[ -n "${mock_body}" ]]; then
    printf '%s' "${mock_body}" > "${body_file}"
elif [[ -n "${fixture}" ]]; then
    cp "${MOCK_CURL_FIXTURES_DIR}/${fixture}" "${body_file}"
else
    : > "${body_file}"
fi
