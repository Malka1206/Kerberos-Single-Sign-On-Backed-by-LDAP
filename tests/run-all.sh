#!/usr/bin/env bash
# Runs every client-side test, prints PASS or FAIL for each and exits non-zero if any fails.
# Run as the normal user (not root), through: make test
set -uo pipefail

cd "$(dirname "$0")"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run the tests as a normal user, not root (use: make test)." >&2
  exit 1
fi

# The clock-skew test needs sudo: ask for the password once, up front.
sudo -v || { echo "sudo is required for the clock-skew test." >&2; exit 1; }

total=0
failed=0

run_group() {
  local title="$1" prefix="$2" t out
  echo
  echo "== ${title} =="
  for t in "${prefix}"-*.sh; do
    [ -e "$t" ] || continue
    total=$((total + 1))
    # Failed logins are expected in the negative tests: reset sshd's per-source penalty.
    sudo systemctl restart ssh >/dev/null 2>&1; sleep 1
    out="$(bash "$t" 2>&1)" && rc=0 || rc=$?
    printf '%s\n' "$out"
    [ "$rc" -eq 0 ] || failed=$((failed + 1))
  done
}

run_group "Positive tests" pos
run_group "Negative tests" neg
run_group "Security checks" sec

kdestroy -q 2>/dev/null || true

echo
echo "== Summary =="
echo "${total} tests, $((total - failed)) passed, ${failed} failed"
echo "(the KDC log check runs on the host: make check-kdc-log)"
[ "$failed" -eq 0 ]
