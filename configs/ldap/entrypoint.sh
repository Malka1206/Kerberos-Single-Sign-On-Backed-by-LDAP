#!/usr/bin/env bash
set -euo pipefail

BASE_DN="dc=lab,dc=test"
ADMIN_DN="cn=admin,${BASE_DN}"
CONF=/etc/ldap/slapd.d
TLS_DIR=/etc/ldap/tls
SRC=/configs
MARKER=/var/lib/ldap/.lab-initialized

: "${LDAP_ADMIN_PASSWORD:?missing in .env}"
: "${SSSD_BIND_PASSWORD:?missing in .env}"
: "${KDC_BIND_PASSWORD:?missing in .env}"
: "${KADMIN_BIND_PASSWORD:?missing in .env}"

# ---------- TLS files ----------
install -d -o openldap -g openldap -m 750 "$TLS_DIR"
install -o openldap -g openldap -m 644 /certs/ca.crt   "$TLS_DIR/ca.crt"
install -o openldap -g openldap -m 644 /certs/ldap.crt "$TLS_DIR/ldap.crt"
install -o openldap -g openldap -m 600 /certs/ldap.key "$TLS_DIR/ldap.key"

mkdir -p /var/run/slapd
chown -R openldap:openldap /var/run/slapd /var/lib/ldap "$CONF"

start_local() {
  slapd -h "ldapi:///" -u openldap -g openldap -F "$CONF"
  for _ in $(seq 1 30); do
    ldapwhoami -Y EXTERNAL -H ldapi:/// -Q >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "[ldap] slapd did not start" >&2
  exit 1
}

stop_local() {
  local pid
  pid="$(cat /var/run/slapd/slapd.pid)"
  kill "$pid"
  while kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
}

if [ ! -f "$MARKER" ]; then
  echo "[ldap] First start: configuring slapd..."
  start_local

  # ---- 1. Kerberos schema ----
  KRB_LDIF=""
  for f in /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif.gz \
           /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif; do
    [ -f "$f" ] && KRB_LDIF="$f" && break
  done
  if [ -z "$KRB_LDIF" ]; then
    echo "[ldap] Kerberos schema LDIF not found. Package doc dir contains:" >&2
    ls -l /usr/share/doc/krb5-kdc-ldap/ >&2
    exit 1
  fi
  zcat -f "$KRB_LDIF" | ldapadd -Y EXTERNAL -H ldapi:/// -Q

  # ---- 2. Global settings: TLS, anonymous bind off, local SSF ----
  ldapmodify -Y EXTERNAL -H ldapi:/// -Q <<LDIF
dn: cn=config
changetype: modify
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: ${TLS_DIR}/ca.crt
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: ${TLS_DIR}/ldap.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: ${TLS_DIR}/ldap.key
-
replace: olcLocalSSF
olcLocalSSF: 256
-
replace: olcDisallows
olcDisallows: bind_anon
LDIF

  # ---- 3. Database: suffix, admin, authentication required, encryption required ----
  ADMIN_HASH="$(slappasswd -s "$LDAP_ADMIN_PASSWORD")"
  ldapmodify -Y EXTERNAL -H ldapi:/// -Q <<LDIF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: ${BASE_DN}
-
replace: olcRootDN
olcRootDN: ${ADMIN_DN}
-
replace: olcRootPW
olcRootPW: ${ADMIN_HASH}
-
replace: olcRequires
olcRequires: authc
-
replace: olcSecurity
olcSecurity: ssf=128
-
replace: olcDbIndex
olcDbIndex: objectClass eq
olcDbIndex: uid eq
olcDbIndex: uidNumber eq
olcDbIndex: gidNumber eq
olcDbIndex: memberUid eq
olcDbIndex: krbPrincipalName eq,pres,sub
LDIF

  # ---- 4. Access rules ----
  ldapmodify -Y EXTERNAL -H ldapi:/// -Q -f "$SRC/acl.ldif"

  # ---- 5. Data (service-account hashes are substituted into base.ldif) ----
  SSSD_HASH="$(slappasswd -s "$SSSD_BIND_PASSWORD")"
  KDC_HASH="$(slappasswd -s "$KDC_BIND_PASSWORD")"
  KADMIN_HASH="$(slappasswd -s "$KADMIN_BIND_PASSWORD")"

  sed -e "s|@SSSD_HASH@|${SSSD_HASH}|" \
      -e "s|@KDC_HASH@|${KDC_HASH}|" \
      -e "s|@KADMIN_HASH@|${KADMIN_HASH}|" \
      "$SRC/base.ldif" \
    | ldapadd -x -H ldapi:/// -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"

  for f in users.ldif groups.ldif; do
    ldapadd -x -H ldapi:/// -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -f "$SRC/$f"
  done

  stop_local
  touch "$MARKER"
  echo "[ldap] Initialization complete."
fi

echo "[ldap] Starting slapd (ldap, ldaps, ldapi)..."
exec slapd -h "ldap:/// ldaps:/// ldapi:///" -u openldap -g openldap -F "$CONF" -d 256
