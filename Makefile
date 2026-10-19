# Day-to-day quality gate. Run `make` before every commit/PR.
.PHONY: all fmt check validate test

all: check validate test

fmt:
	terraform fmt -recursive

check:
	terraform fmt -check -recursive

validate:
	cd module && terraform init -backend=false -input=false >/dev/null && terraform validate
	for env in live/dev live/prod; do \
	  (cd $$env && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; \
	done

test:
	cd module && terraform init -backend=false -input=false >/dev/null && terraform test
