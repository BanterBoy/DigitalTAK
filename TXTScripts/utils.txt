#!/bin/bash
# utils.sh — shared helper functions for DigitalTAK Bash scripts
# Ryan Schilder - March 2026
#
# Source this file from other scripts:
#   SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/utils.sh"

# ------------------------------------------------------------------------------
# bash_quote VAL
# Wraps VAL in bash single-quotes, safe for passing as a shell argument.
# Any embedded single-quotes are correctly escaped as '\''.
# Example: bash_quote "it's a test" => 'it'\''s a test'
# ------------------------------------------------------------------------------
bash_quote() {
    local val="${1//\'/\'\\\'\'}"
    printf "'%s'" "$val"
}

# ------------------------------------------------------------------------------
# sed_replace_quote VAL
# Escapes VAL for safe embedding in a sed replacement string that uses '|'
# as the command delimiter.
# Special characters escaped: backslash, pipe, and ampersand.
# Dollar-sign ($) and backtick are NOT special in sed replacement strings and
# are left unmodified.
# Example: sed_replace_quote 'p&ss|w\ord' => 'p\&ss\|w\\ord'
# ------------------------------------------------------------------------------
sed_replace_quote() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/|/\\|/g' -e 's/&/\\&/g'
}

# ------------------------------------------------------------------------------
# wait_for_service SERVICE [TIMEOUT_SECONDS]
# Polls 'systemctl is-active' until SERVICE reports active or TIMEOUT expires.
# Prints progress every 10 seconds. Exits 1 on timeout.
# Default timeout: 300 seconds.
# ------------------------------------------------------------------------------
wait_for_service() {
    local service="$1"
    local timeout="${2:-300}"
    local elapsed=0
    echo "Waiting for '${service}' to become active (timeout ${timeout}s)..."
    while [ "$elapsed" -lt "$timeout" ]; do
        if sudo systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "'${service}' is active after ${elapsed}s."
            return 0
        fi
        sleep 10
        elapsed=$(( elapsed + 10 ))
        echo "  ${elapsed}/${timeout}s — waiting for '${service}'..."
    done
    echo "ERROR: '${service}' did not become active within ${timeout}s."
    return 1
}
