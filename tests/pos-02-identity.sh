#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Identity resolution: alice comes from LDAP with the correct groups"

entry="$(getent passwd alice)" || fail "$T" "getent passwd alice returned nothing"
grep -q '^alice:' /etc/passwd && fail "$T" "alice is a local user, not an LDAP one"
ids="$(id alice 2>&1)" || fail "$T" "id alice failed"
for g in ssh-users admins web-users; do
  printf '%s' "$ids" | grep -q "(${g})" || fail "$T" "missing group ${g}: ${ids}"
done
pass "$T"
