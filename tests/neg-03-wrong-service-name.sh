#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Wrong service name: GSSAPI fails when the FQDN is not used"

login alice "${ALICE_PASSWORD:?}" || fail "$T" "kinit failed"
# Control: the FQDN works with the same ticket.
ssh_gss alice "$CLIENT_FQDN" true >/dev/null 2>&1 || fail "$T" "the FQDN does not work, test is meaningless"
# Short name: the ticket would be for host/client1@${REALM}, which does not exist.
if ssh_gss alice client1 true >/dev/null 2>&1; then
  fail "$T" "GSSAPI succeeded with the short name"
fi
pass "$T"
