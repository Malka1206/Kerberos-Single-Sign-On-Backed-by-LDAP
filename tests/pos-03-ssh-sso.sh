#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Passwordless SSH: after kinit, alice reaches ${CLIENT_FQDN} without a prompt"

login alice "${ALICE_PASSWORD:?}" || fail "$T" "kinit failed"
who="$(ssh_gss alice "$CLIENT_FQDN" whoami 2>&1)" || fail "$T" "$who"
[ "$who" = "alice" ] || fail "$T" "unexpected output: ${who}"
pass "$T"
