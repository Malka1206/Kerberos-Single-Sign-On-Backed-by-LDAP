SHELL := bash

-include .env
export

.PHONY: certs up provision check-kdc-log down clean hosts client test

# ---------- Host ----------
certs:
	@bash scripts/gen-certs.sh

up: certs
	@docker compose up -d --build
	@echo "Services started. The web service waits for its keytab: run 'make provision' next."

provision:
	@bash scripts/provision-principals.sh

check-kdc-log:
	@export MSYS_NO_PATHCONV=1; \
	pattern='PREAUTH_FAILED|Preauthentication failed'; \
	before=$$(docker compose exec -T kdc grep -cE "$$pattern" /var/log/krb5kdc.log || true); \
	docker compose exec -T kdc bash -c 'echo wrong-password-on-purpose | kinit alice' >/dev/null 2>&1 || true; \
	sleep 1; \
	after=$$(docker compose exec -T kdc grep -cE "$$pattern" /var/log/krb5kdc.log || true); \
	if [ "$${after:-0}" -gt "$${before:-0}" ]; then \
	  docker compose exec -T kdc grep -E "$$pattern" /var/log/krb5kdc.log | tail -n 2; \
	  echo "PASS: the failed login was recorded in the KDC log"; \
	else \
	  echo "FAIL: no new pre-authentication failure in the KDC log"; exit 1; \
	fi

down:
	@docker compose down

clean:
	@docker compose down -v --remove-orphans
	@rm -rf certs keytabs
	@echo "Containers, volumes and generated secrets removed."

# ---------- Client (Kali VM) ----------
hosts:
	@echo "TODO: add lab hostnames to the hosts file"

client:
	@echo "TODO: configure SSSD, SSH, Kerberos and sudo"

test:
	@echo "TODO: run the end-to-end test suite"
