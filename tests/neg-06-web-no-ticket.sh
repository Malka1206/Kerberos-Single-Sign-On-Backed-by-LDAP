#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="No ticket on the web: curl without credentials receives HTTP 401"

kdestroy -q 2>/dev/null || true
code="$(curl -s -o /dev/null -w '%{http_code}' "$WEB_URL")"
[ "$code" = "401" ] || fail "$T" "got HTTP ${code}"
pass "$T"
