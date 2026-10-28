#!/usr/bin/env bash
# Creates the lab CA and the LDAP server certificate.
set -euo pipefail

export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

cd "$(dirname "$0")/.."


if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

DOMAIN="${DOMAIN:-lab.test}"
LDAP_FQDN="ldap.${DOMAIN}"
CERT_DIR="certs"

mkdir -p "$CERT_DIR"

if [ -f "$CERT_DIR/ca.crt" ] || [ -f "$CERT_DIR/ldap.crt" ]; then
  echo "[certs] Certificates already exist in $CERT_DIR/. Run 'make clean' first to regenerate."
  exit 0
fi

echo "[certs] Generating lab CA..."
openssl genrsa -out "$CERT_DIR/ca.key" 4096
openssl req -x509 -new -nodes \
  -key "$CERT_DIR/ca.key" \
  -sha256 -days 3650 \
  -subj "/O=Lab/CN=Lab Test CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out "$CERT_DIR/ca.crt"

echo "[certs] Generating LDAP server key and CSR for ${LDAP_FQDN}..."
openssl genrsa -out "$CERT_DIR/ldap.key" 2048
openssl req -new \
  -key "$CERT_DIR/ldap.key" \
  -subj "/O=Lab/CN=${LDAP_FQDN}" \
  -out "$CERT_DIR/ldap.csr"

cat > "$CERT_DIR/ldap.ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:${LDAP_FQDN}
EOF

echo "[certs] Signing server certificate with the lab CA..."
openssl x509 -req \
  -in "$CERT_DIR/ldap.csr" \
  -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
  -sha256 -days 825 \
  -extfile "$CERT_DIR/ldap.ext" \
  -out "$CERT_DIR/ldap.crt"

rm -f "$CERT_DIR/ldap.csr" "$CERT_DIR/ldap.ext" "$CERT_DIR/ca.srl"

# Restrictive permissions (effective on Linux/VM; largely a no-op on Windows filesystems)
chmod 600 "$CERT_DIR/ca.key" "$CERT_DIR/ldap.key" 2>/dev/null || true

echo "[certs] Done. Files in $CERT_DIR/:"
ls -1 "$CERT_DIR"
echo "[certs] Copy $CERT_DIR/ca.crt to the Kali VM by hand (see README section 9)."