#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T="Read-only account: the SSSD account cannot write and cannot read Kerberos attributes"

pw="${SSSD_BIND_PASSWORD:?}"
user_dn="uid=alice,ou=people,${BASE_DN}"

# Can read identity data
out="$(ldapsearch -x -LLL -H "$LDAP_URI" -D "$SSSD_DN" -y <(printf '%s' "$pw") \
        -b "$user_dn" -s base '*' 2>&1)" || fail "$T" "SSSD account cannot read alice: ${out}"
printf '%s' "$out" | grep -q '^uidNumber:' || fail "$T" "uidNumber not readable"

# Cannot read Kerberos attributes
printf '%s' "$out" | grep -qi '^krb' && fail "$T" "Kerberos attributes are readable"

# Cannot write
mod="$(ldapmodify -x -H "$LDAP_URI" -D "$SSSD_DN" -y <(printf '%s' "$pw") 2>&1 <<EOF
dn: ${user_dn}
changetype: modify
replace: description
description: written-by-test
EOF
)" && fail "$T" "the SSSD account modified an entry"
printf '%s' "$mod" | grep -qi 'insufficient access' || fail "$T" "write refused for another reason: ${mod}"
pass "$T"
