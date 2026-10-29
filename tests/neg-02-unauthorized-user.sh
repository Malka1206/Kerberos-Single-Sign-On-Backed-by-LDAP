#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Unauthorized user: carol is refused by SSH even with a valid ticket"

login carol "${CAROL_PASSWORD:?}" || fail "$T" "kinit carol failed (the ticket must be valid)"
klist 2>&1 | grep -q "krbtgt/${REALM}@${REALM}" || fail "$T" "carol has no valid ticket"
if out="$(ssh_gss carol "$CLIENT_FQDN" whoami 2>&1)"; then
  fail "$T" "carol got a session: ${out}"
fi
pass "$T"
