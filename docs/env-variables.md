# Environment variables

The lab is configured through one file, `.env`, created from `.env.example` (`cp .env.example .env`). `.env` is git-ignored: it holds the lab passwords and must never be committed. Both machines use the same file, so copy the values you set on the Windows host into the VM's clone.

## Naming

| Variable | Purpose |
|---|---|
| `DOMAIN` | DNS domain of the lab. Server hostnames (`ldap`, `kdc`, `web`) and the client (`client1`) are built from it. |
| `REALM` | Kerberos realm, conventionally the domain in upper case. |
| `BASE_DN` | Root of the LDAP directory, derived from the domain. |

Change these three together or not at all: the LDIF files, the Kerberos configuration and the certificates all assume them to be consistent.

## Network

| Variable | Purpose |
|---|---|
| `HOST_IP` | Address at which the VM reaches the Windows host. It depends on the VirtualBox network mode in use, so set it to the host address as seen from the VM. `make hosts` writes it into the VM's hosts file for `ldap`, `kdc` and `web`. |

## Published ports

| Variable | Service |
|---|---|
| `KDC_PORT` | Kerberos KDC |
| `KPASSWD_PORT` | Password change service |
| `KADMIN_PORT` | Kerberos administration service |
| `LDAP_PORT` | LDAP |
| `LDAPS_PORT` | LDAP over TLS |
| `WEB_PORT` | Apache |

The defaults are the standard ports. Change one only if it is already in use on the host, and allow it through the host firewall.

## LDAP accounts

| Variable | Used by |
|---|---|
| `LDAP_ADMIN_PASSWORD` | Directory administrator, used only for provisioning. |
| `SSSD_BIND_PASSWORD` | Read-only account used by SSSD on the VM and by Apache for its group check. |

## Kerberos

| Variable | Used by |
|---|---|
| `KDC_BIND_PASSWORD` | Directory account of the KDC process. |
| `KADMIN_BIND_PASSWORD` | Directory account of the administration service. |
| `KDC_MASTER_PASSWORD` | Master key of the Kerberos database, used when the realm is created. |
| `ADMIN_PASSWORD` | Password of the `admin/admin` principal, used by `make client` to fetch the VM's host keytab. |

## Example users

| Variable | User |
|---|---|
| `ALICE_PASSWORD` | `alice` |
| `BOB_PASSWORD` | `bob` |
| `CAROL_PASSWORD` | `carol` |

These are the Kerberos passwords of the example users, also read by the test suite.

## Where each variable is needed

- **Windows host:** all variables.
- **VM:** `DOMAIN`, `REALM`, `HOST_IP`, `WEB_PORT`, `SSSD_BIND_PASSWORD`, `ADMIN_PASSWORD` and the three user passwords (the last ones only for `make test`).

Use a different strong password for each account, even in a lab.
