#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Non-admin sudo: bob can log in but cannot use sudo"

login bob "${BOB_PASSWORD:?}" || fail "$T" "kinit bob failed"
who="$(ssh_gss bob "$CLIENT_FQDN" whoami 2>&1)" || fail "$T" "bob cannot log in: ${who}"
[ "$who" = "bob" ] || fail "$T" "unexpected output: ${who}"
if printf '%s\n' "$BOB_PASSWORD" | ssh_gss bob "$CLIENT_FQDN" "sudo -S -p '' true" >/dev/null 2>&1; then
  fail "$T" "bob ran sudo"
fi
pass "$T"
