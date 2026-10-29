#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Anonymous LDAP access: an unauthenticated search is refused"

out="$(ldapsearch -x -LLL -H "$LDAP_URI" -b "$BASE_DN" '(objectClass=*)' dn 2>&1)" || true
printf '%s' "$out" | grep -q "Can't contact" && fail "$T" "LDAP server unreachable: ${out}"
printf '%s' "$out" | grep -q '^dn:' && fail "$T" "anonymous search returned entries"
pass "$T"
