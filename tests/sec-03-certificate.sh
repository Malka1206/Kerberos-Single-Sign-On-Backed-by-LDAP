#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Certificate validation: valid against the lab CA, refused without it"

pw="${SSSD_BIND_PASSWORD:?}"
[ -f certs/ca.crt ] || fail "$T" "certs/ca.crt not found"

# With the lab CA
LDAPTLS_CACERT="$PWD/certs/ca.crt" ldapwhoami -x -H "$LDAP_URI" -D "$SSSD_DN" \
  -y <(printf '%s' "$pw") >/dev/null 2>&1 || fail "$T" "TLS fails even with the lab CA"

# Without it: trust file that does not contain the lab CA
empty="$(mktemp)"
trap 'rm -f "$empty"' EXIT
if LDAPTLS_CACERT="$empty" LDAPTLS_CACERTDIR=/nonexistent ldapwhoami -x -H "$LDAP_URI" -D "$SSSD_DN" \
     -y <(printf '%s' "$pw") >/dev/null 2>&1; then
  fail "$T" "the connection succeeded without the lab CA"
fi
pass "$T"
