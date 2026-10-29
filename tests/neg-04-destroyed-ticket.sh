#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Destroyed ticket: after kdestroy, passwordless SSH no longer works"

login alice "${ALICE_PASSWORD:?}" || fail "$T" "kinit failed"
ssh_gss alice "$CLIENT_FQDN" true >/dev/null 2>&1 || fail "$T" "SSH failed even with a ticket"
kdestroy -q
if ssh_gss alice "$CLIENT_FQDN" true >/dev/null 2>&1; then
  fail "$T" "SSH still works without a ticket"
fi
pass "$T"
