#!/usr/bin/env bash
# Configures the Kali VM as the Linux client. Run through make, from the repo root:
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "[client] Run this script as root (make calls sudo for you)." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

DOMAIN="${DOMAIN:-lab.test}"
REALM="${REALM:-LAB.TEST}"
CLIENT_FQDN="client1.${DOMAIN}"
CFG="configs/client"
MODE="${1:-client}"

# ---------------------------------------------------------------------------
# hosts: hostname and /etc/hosts entries
# ---------------------------------------------------------------------------
do_hosts() {
  : "${HOST_IP:?missing in .env}"

  echo "[client] Setting the hostname to ${CLIENT_FQDN}"
  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$CLIENT_FQDN"
  else
    echo "$CLIENT_FQDN" > /etc/hostname
    hostname "$CLIENT_FQDN"
  fi

  echo "[client] Updating /etc/hosts (backup: /etc/hosts.lab-backup)"
  cp -n /etc/hosts /etc/hosts.lab-backup
  # Remove our previous block and any other 127.0.1.1 line: sshd derives its service
  # name from the first name of the local address, which must be client1.lab.test.
  sed -i -e '/^# BEGIN lab.test$/,/^# END lab.test$/d' -e '/^127\.0\.1\.1[[:space:]]/d' /etc/hosts
  cat >> /etc/hosts <<EOF
# BEGIN lab.test
127.0.1.1 ${CLIENT_FQDN} client1
${HOST_IP} ldap.${DOMAIN} kdc.${DOMAIN} web.${DOMAIN}
# END lab.test
EOF
  getent hosts "ldap.${DOMAIN}" "kdc.${DOMAIN}" "web.${DOMAIN}" "$CLIENT_FQDN"
}

# ---------------------------------------------------------------------------
# client: packages, CA, Kerberos, SSSD, SSH, sudo, host keytab
# ---------------------------------------------------------------------------
do_client() {
  : "${SSSD_BIND_PASSWORD:?missing in .env}"
  : "${ADMIN_PASSWORD:?missing in .env}"

  [ -f certs/ca.crt ] || { echo "[client] certs/ca.crt not found. Copy it from the host first." >&2; exit 1; }
  getent hosts "kdc.${DOMAIN}" >/dev/null || { echo "[client] Lab hostnames do not resolve. Run 'make hosts' first." >&2; exit 1; }

  echo "[client] Installing packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    sssd sssd-ldap sssd-krb5 libpam-sss libnss-sss libpam-modules \
    krb5-user ldap-utils openssh-server sudo curl ca-certificates

  echo "[client] Trusting the lab CA"
  install -m 644 certs/ca.crt /usr/local/share/ca-certificates/lab-ca.crt
  update-ca-certificates >/dev/null

  echo "[client] Kerberos client configuration"
  install -m 644 "$CFG/krb5.conf" /etc/krb5.conf

  echo "[client] Host keytab for host/${CLIENT_FQDN}"
  if klist -k /etc/krb5.keytab 2>/dev/null | grep -q "host/${CLIENT_FQDN}@${REALM}"; then
    echo "[client] Keytab already present, skipping"
  else
    printf '%s\n' "$ADMIN_PASSWORD" \
      | kadmin -p "admin/admin@${REALM}" -q "ktadd -k /etc/krb5.keytab host/${CLIENT_FQDN}"
    chmod 600 /etc/krb5.keytab
  fi

  echo "[client] SSSD configuration"
  pw_esc="$(printf '%s' "$SSSD_BIND_PASSWORD" | sed -e 's/[\\&|]/\\&/g')"
  sed "s|@SSSD_BIND_PASSWORD@|${pw_esc}|" "$CFG/sssd.conf" > /etc/sssd/sssd.conf
  chown root:root /etc/sssd/sssd.conf
  chmod 600 /etc/sssd/sssd.conf

  echo "[client] Name service and PAM (SSSD, home directory on first login)"
  for db in passwd group; do
    grep -Eq "^${db}:.*\bsss\b" /etc/nsswitch.conf || sed -i "s/^${db}:.*/& sss/" /etc/nsswitch.conf
  done
  pam-auth-update --enable sss mkhomedir

  echo "[client] SSH (GSSAPI and PAM)"
  install -d /etc/ssh/sshd_config.d /etc/ssh/ssh_config.d
  grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/' /etc/ssh/sshd_config \
    || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
  grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/ssh_config.d/' /etc/ssh/ssh_config \
    || sed -i '1i Include /etc/ssh/ssh_config.d/*.conf' /etc/ssh/ssh_config
  install -m 644 "$CFG/sshd_lab.conf" /etc/ssh/sshd_config.d/lab-kerberos.conf
  install -m 644 "$CFG/ssh_lab.conf"  /etc/ssh/ssh_config.d/lab-kerberos.conf
  sshd -t

  echo "[client] sudo rule for the admins group"
  install -m 440 "$CFG/sudoers-admins" /etc/sudoers.d/lab-admins
  visudo -cf /etc/sudoers.d/lab-admins >/dev/null

  echo "[client] Restarting services"
  systemctl stop sssd 2>/dev/null || true
  rm -rf /var/lib/sss/db/* /var/lib/sss/mc/*
  systemctl enable --now sssd
  systemctl enable --now ssh
  systemctl restart ssh

  echo "[client] Checking that LDAP users resolve"
  for _ in $(seq 1 15); do
    getent passwd alice >/dev/null 2>&1 && break
    sleep 1
  done
  getent passwd alice
  id alice
}

# ---------------------------------------------------------------------------
# clean: remove everything this script added 
# ---------------------------------------------------------------------------
do_clean() {
  echo "[client] Removing the lab configuration (packages are kept)"
  export DEBIAN_FRONTEND=noninteractive

  # Ticket caches of the example users
  rm -f /tmp/krb5cc_10001 /tmp/krb5cc_10002 /tmp/krb5cc_10003

  # SSSD, name service and PAM
  systemctl disable --now sssd 2>/dev/null || true
  rm -f /etc/sssd/sssd.conf
  rm -rf /var/lib/sss/db/* /var/lib/sss/mc/*
  pam-auth-update --remove sss mkhomedir 2>/dev/null || true
  sed -i -E '/^(passwd|group):/ s/[[:space:]]+sss\b//' /etc/nsswitch.conf

  # SSH drop-ins and sudo rule
  rm -f /etc/ssh/sshd_config.d/lab-kerberos.conf /etc/ssh/ssh_config.d/lab-kerberos.conf
  systemctl restart ssh 2>/dev/null || true
  rm -f /etc/sudoers.d/lab-admins

  # Kerberos client files and host keytab
  rm -f /etc/krb5.keytab /etc/krb5.conf

  # Lab CA
  rm -f /usr/local/share/ca-certificates/lab-ca.crt
  update-ca-certificates --fresh >/dev/null

  # Home directories created on first login
  rm -rf /home/alice /home/bob /home/carol

  # /etc/hosts and the original hostname
  if [ -f /etc/hosts.lab-backup ]; then
    orig="$(awk '$1=="127.0.1.1"{print $2; exit}' /etc/hosts.lab-backup)"
    cp /etc/hosts.lab-backup /etc/hosts
    rm -f /etc/hosts.lab-backup
    if [ -n "${orig:-}" ]; then
      if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$orig"
      else
        echo "$orig" > /etc/hostname
        hostname "$orig"
      fi
    fi
  else
    sed -i '/^# BEGIN lab.test$/,/^# END lab.test$/d' /etc/hosts
  fi
}

case "$MODE" in
  hosts)  do_hosts ;;
  client) do_client ;;
  clean)  do_clean ;;
  *) echo "Usage: $0 {hosts|client|clean}" >&2; exit 1 ;;
esac
echo "[client] Done ($MODE)."
