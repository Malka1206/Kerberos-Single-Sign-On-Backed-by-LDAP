#!/usr/bin/env bash
# Installs the Kerberos client config, the web keytab and the site, then runs Apache.
set -euo pipefail

: "${SSSD_BIND_PASSWORD:?missing in .env}"

SRC=/configs

# ---------- Kerberos client configuration  ----------
cat > /etc/krb5.conf <<'EOF'
[libdefaults]
    default_realm = LAB.TEST
    dns_lookup_realm = false
    dns_lookup_kdc = false
    dns_canonicalize_hostname = false
    rdns = false

[realms]
    LAB.TEST = {
        kdc = kdc.lab.test
        admin_server = kdc.lab.test
    }

[domain_realm]
    .lab.test = LAB.TEST
    lab.test = LAB.TEST
EOF

# ---------- Service keytab ----------
if [ ! -s /keytabs/http.keytab ]; then
  echo "[web] Waiting for /keytabs/http.keytab (run 'make provision' on the host)..."
  for _ in $(seq 1 150); do
    [ -s /keytabs/http.keytab ] && break
    sleep 2
  done
fi
if [ ! -s /keytabs/http.keytab ]; then
  echo "[web] /keytabs/http.keytab not found after 5 minutes. Run 'make provision' and restart." >&2
  exit 1
fi
install -o www-data -g www-data -m 400 /keytabs/http.keytab /etc/apache2/http.keytab

# ---------- Site ----------
echo '<h1>Kerberos SSO: access granted</h1>' > /var/www/html/index.html
install -m 644 "$SRC/site.conf" /etc/apache2/sites-available/lab.conf
a2ensite lab >/dev/null

mkdir -p /var/run/apache2 /var/lock/apache2
chown www-data:www-data /var/run/apache2 /var/lock/apache2

apache2ctl configtest
echo "[web] Starting Apache..."
exec apache2ctl -D FOREGROUND
