#!/usr/bin/env bash
# Creates the user principals (linked to their existing LDAP entries) and the
# service principals (SSH host and web). Run on the Windows host in Git Bash,
# with the kdc container running.
set -euo pipefail

# Git Bash (MSYS) must not rewrite arguments that look like paths
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

DOMAIN="${DOMAIN:-lab.test}"
REALM="${REALM:-LAB.TEST}"
BASE_DN="${BASE_DN:-dc=lab,dc=test}"
KEYTAB_DIR="keytabs"

: "${ALICE_PASSWORD:?missing in .env}"
: "${BOB_PASSWORD:?missing in .env}"
: "${CAROL_PASSWORD:?missing in .env}"
: "${ADMIN_PASSWORD:?missing in .env}"

kadm() {
  docker compose exec -T kdc kadmin.local -q "$1"
}

principal_exists() {
  local out
  out="$(kadm "getprinc $1" 2>&1 || true)"
  grep -q "^Principal: $1\$" <<<"$out"
}

# add_user <uid> <password>: principal stored inside the existing LDAP user entry
add_user() {
  local user="$1" pw="$2" princ="$1@${REALM}"
  if principal_exists "$princ"; then
    echo "[provision] $princ already exists, skipping creation"
  else
    echo "[provision] Creating $princ (linked to uid=${user},ou=people,${BASE_DN})"
    printf '%s\n%s\n' "$pw" "$pw" \
      | docker compose exec -T kdc kadmin.local -q \
          "addprinc -x dn=uid=${user},ou=people,${BASE_DN} ${princ}"
  fi
  # Pre-authentication is mandatory: the client must prove it knows the password
  # before the KDC returns anything encrypted with the user's key.
  kadm "modprinc +requires_preauth ${princ}"
}

# add_service <principal>: random key, no password
add_service() {
  local princ="$1"
  if principal_exists "$princ"; then
    echo "[provision] $princ already exists, skipping"
    return
  fi
  echo "[provision] Creating $princ"
  kadm "addprinc -randkey ${princ}"
}

echo "[provision] User principals"
add_user alice "$ALICE_PASSWORD"
add_user bob   "$BOB_PASSWORD"
add_user carol "$CAROL_PASSWORD"

# admin/admin: used by the VM to fetch its host keytab (the ACL limits it to host/* keys)
echo "[provision] Admin principal"
ADMIN_PRINC="admin/admin@${REALM}"
if principal_exists "$ADMIN_PRINC"; then
  echo "[provision] $ADMIN_PRINC already exists, skipping creation"
else
  echo "[provision] Creating $ADMIN_PRINC"
  printf '%s\n%s\n' "$ADMIN_PASSWORD" "$ADMIN_PASSWORD" \
    | docker compose exec -T kdc kadmin.local -q "addprinc ${ADMIN_PRINC}"
fi
kadm "modprinc +requires_preauth ${ADMIN_PRINC}"

echo "[provision] Service principals"
SSH_PRINC="host/client1.${DOMAIN}@${REALM}"
WEB_PRINC="HTTP/web.${DOMAIN}@${REALM}"
add_service "$SSH_PRINC"
add_service "$WEB_PRINC"

# The Apache container needs its own keytab. Export it to ./keytabs (git-ignored).
mkdir -p "$KEYTAB_DIR"
if [ -f "$KEYTAB_DIR/http.keytab" ]; then
  echo "[provision] $KEYTAB_DIR/http.keytab already exists, skipping"
else
  echo "[provision] Exporting the web keytab to $KEYTAB_DIR/http.keytab"
  docker compose exec -T kdc bash -c "rm -f /tmp/http.keytab"
  kadm "ktadd -k /tmp/http.keytab ${WEB_PRINC}"
  docker compose cp kdc:/tmp/http.keytab "$KEYTAB_DIR/http.keytab"
  docker compose exec -T kdc bash -c "rm -f /tmp/http.keytab"
  chmod 600 "$KEYTAB_DIR/http.keytab" 2>/dev/null || true
fi

echo "[provision] Principals in the realm:"
kadm "listprincs"
