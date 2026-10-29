#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Clock skew: kinit fails with 'Clock skew too great' (clock shifted by 10 minutes)"

start="$(date +%s)"
SECONDS=0
restore() { sudo date -s "@$((start + SECONDS))" >/dev/null 2>&1; }
trap restore EXIT INT TERM

kdestroy -q 2>/dev/null || true
sudo date -s "@$((start + 600))" >/dev/null || fail "$T" "could not change the clock (sudo)"

out="$(printf '%s\n' "${ALICE_PASSWORD:?}" | kinit "alice@${REALM}" 2>&1)" && rc=0 || rc=$?
restore
trap - EXIT INT TERM

[ "$rc" -ne 0 ] || fail "$T" "kinit succeeded with a shifted clock"
printf '%s' "$out" | grep -q 'Clock skew too great' || fail "$T" "unexpected error: ${out}"
pass "$T"
