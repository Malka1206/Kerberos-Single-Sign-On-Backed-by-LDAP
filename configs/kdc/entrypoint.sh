#!/usr/bin/env bash
# First start: create the realm inside OpenLDAP and stash the service passwords.
# Every start: install the configuration, then run krb5kdc and kadmind.
set -euo pipefail

REALM="LAB.TEST"
BASE_DN="dc=lab,dc=test"
ADMIN_DN="cn=admin,${BASE_DN}"
KDC_DN="cn=kdc,ou=services,${BASE_DN}"
KADMIN_DN="cn=kadmin,ou=services,${BASE_DN}"
LDAP_URI="ldaps://ldap.lab.test"
SRC=/configs
STATE=/var/lib/krb5kdc
MARKER="${STATE}/.lab-initialized"

: "${LDAP_ADMIN_PASSWORD:?missing in .env}"
: "${KDC_BIND_PASSWORD:?missing in .env}"
: "${KADMIN_BIND_PASSWORD:?missing in .env}"
: "${KDC_MASTER_PASSWORD:?missing in .env}"

# ---------- Configuration ----------
mkdir -p /etc/ldap /etc/krb5kdc "$STATE"
printf 'TLS_CACERT /certs/ca.crt\nTLS_REQCERT demand\n' > /etc/ldap/ldap.conf
install -m 644 "$SRC/krb5.conf" /etc/krb5.conf
install -m 644 "$SRC/kdc.conf"  /etc/krb5kdc/kdc.conf
echo "*/admin@${REALM} *" > /etc/krb5kdc/kadm5.acl
touch /var/log/krb5kdc.log /var/log/kadmind.log

# ---------- Wait until LDAPS is up and the directory is loaded ----------
echo "[kdc] Waiting for ${LDAP_URI}..."
for _ in $(seq 1 60); do
  if ldapsearch -x -H "$LDAP_URI" -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" \
       -b "cn=kerberos,${BASE_DN}" -s base dn >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
ldapsearch -x -H "$LDAP_URI" -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" \
  -b "cn=kerberos,${BASE_DN}" -s base dn >/dev/null

# ---------- First start ----------
if [ ! -f "$MARKER" ]; then
  echo "[kdc] First start: creating realm ${REALM} in LDAP..."

  # Service passwords used by the KDC and kadmind to bind to LDAP
  rm -f "$STATE/service.keyfile"
  printf '%s\n%s\n' "$KDC_BIND_PASSWORD" "$KDC_BIND_PASSWORD" \
    | kdb5_ldap_util -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -H "$LDAP_URI" \
        stashsrvpw -f "$STATE/service.keyfile" "$KDC_DN"
  printf '%s\n%s\n' "$KADMIN_BIND_PASSWORD" "$KADMIN_BIND_PASSWORD" \
    | kdb5_ldap_util -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -H "$LDAP_URI" \
        stashsrvpw -f "$STATE/service.keyfile" "$KADMIN_DN"
  chmod 600 "$STATE/service.keyfile"

  # Realm container + master key stash
  kdb5_ldap_util -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -H "$LDAP_URI" \
    create -r "$REALM" -subtrees "ou=people,${BASE_DN}" -sscope sub \
    -s -P "$KDC_MASTER_PASSWORD"

  # Keytab for kadmind (kadmin/admin and kadmin/changepw)
  rm -f "$STATE/kadm5.keytab"
  kadmin.local -q "ktadd -k ${STATE}/kadm5.keytab kadmin/admin kadmin/changepw"
  chmod 600 "$STATE/kadm5.keytab"

  touch "$MARKER"
  echo "[kdc] Initialization complete."
fi

# ---------- Run both daemons ----------
echo "[kdc] Starting krb5kdc and kadmind..."
krb5kdc -n &
kadmind -nofork &
trap 'kill $(jobs -p) 2>/dev/null || true' TERM INT
wait -n
echo "[kdc] A daemon exited, stopping." >&2
kill $(jobs -p) 2>/dev/null || true
exit 1
