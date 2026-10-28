SHELL := bash

-include .env
export

.PHONY: certs up provision check-kdc-log down clean hosts client test

# ---------- Host (Windows, Git Bash) ----------
certs:
	@echo "TODO: generate CA and server certificates"

up:
	@echo "TODO: build and start the Docker services"

provision:
	@echo "TODO: load LDIF data, create realm, create and link principals"

check-kdc-log:
	@echo "TODO: verify failed logins are recorded in the KDC log"

down:
	@echo "TODO: stop the services"

clean:
	@echo "TODO: remove containers, volumes and generated secrets"

# ---------- Client (Kali VM) ----------
hosts:
	@echo "TODO: add lab hostnames to the hosts file"

client:
	@echo "TODO: configure SSSD, SSH, Kerberos and sudo"

test:
	@echo "TODO: run the end-to-end test suite"