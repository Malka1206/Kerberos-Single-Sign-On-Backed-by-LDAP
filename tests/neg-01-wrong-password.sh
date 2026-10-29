#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Wrong password: kinit fails (KDC log: make check-kdc-log on the host)"

kdestroy -q 2>/dev/null || true
if printf '%s\n' "wrong-password-on-purpose" | kinit "alice@${REALM}" >/dev/null 2>&1; then
  fail "$T" "kinit accepted a wrong password"
fi
klist >/dev/null 2>&1 && fail "$T" "a ticket exists after a failed kinit"
pass "$T"
