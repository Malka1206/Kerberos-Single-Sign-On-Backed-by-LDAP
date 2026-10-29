#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Privilege escalation: alice can run sudo"

login alice "${ALICE_PASSWORD:?}" || fail "$T" "kinit failed"
out="$(printf '%s\n' "$ALICE_PASSWORD" | ssh_gss alice "$CLIENT_FQDN" "sudo -S -p '' whoami" 2>&1)" \
  || fail "$T" "$out"
[ "$out" = "root" ] || fail "$T" "unexpected output: ${out}"
pass "$T"
