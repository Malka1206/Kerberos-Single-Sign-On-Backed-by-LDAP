#!/usr/bin/env bash
# Shared helpers for the client-side tests. Sourced by each test, never run directly.
set -uo pipefail
export LC_ALL=C

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

DOMAIN="${DOMAIN:-lab.test}"
REALM="${REALM:-LAB.TEST}"
BASE_DN="${BASE_DN:-dc=lab,dc=test}"
CLIENT_FQDN="client1.${DOMAIN}"
LDAP_URI="ldaps://ldap.${DOMAIN}"
WEB_URL="http://web.${DOMAIN}:${WEB_PORT:-80}/"
SSSD_DN="cn=sssd,ou=services,${BASE_DN}"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)

pass() { echo "PASS: $1"; exit 0; }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; exit 1; }

# login USER PASSWORD -> fresh ticket for USER (silent), returns kinit's status
login() {
  kdestroy -q 2>/dev/null || true
  printf '%s\n' "$2" | kinit "$1@${REALM}" >/dev/null 2>&1
}

# ssh_gss USER HOST COMMAND... -> SSH with Kerberos only (never a password)
ssh_gss() {
  local user="$1" host="$2"; shift 2
  ssh "${SSH_OPTS[@]}" -o PreferredAuthentications=gssapi-with-mic \
      -o GSSAPIAuthentication=yes "${user}@${host}" "$@"
}
