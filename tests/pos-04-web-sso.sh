#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Web SSO: curl --negotiate returns HTTP 200"

login alice "${ALICE_PASSWORD:?}" || fail "$T" "kinit failed"
code="$(curl -s -o /dev/null -w '%{http_code}' --negotiate -u : "$WEB_URL")"
[ "$code" = "200" ] || fail "$T" "got HTTP ${code}"
pass "$T"
