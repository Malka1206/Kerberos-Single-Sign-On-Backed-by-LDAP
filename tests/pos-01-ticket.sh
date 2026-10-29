#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Ticket acquisition: kinit gives a TGT for alice@${REALM}"

login alice "${ALICE_PASSWORD:?}" || fail "$T" "kinit failed"
klist 2>&1 | grep -q "krbtgt/${REALM}@${REALM}" || fail "$T" "no TGT in klist"
klist 2>&1 | grep -q "Default principal: alice@${REALM}" || fail "$T" "wrong principal in klist"
pass "$T"
