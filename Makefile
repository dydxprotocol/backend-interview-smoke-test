# Smoke test for the listener interview project. `make` runs everything.

COMPOSE ?= docker compose --progress quiet

.DEFAULT_GOAL := smoke
.PHONY: smoke check up verify down help

smoke: ## Host checks, image pull/build, start the stack, verify inside and from the host, tear down
	@start=$$(date +%s); \
	echo "==> 1/5 host prerequisites"; \
	./check.sh || { echo; echo "Fix the FAILed host checks above, then run 'make' again."; exit 1; }; \
	echo; echo "==> 2/5 pulling and building images (first run downloads about 2 GB; later runs are quick)"; \
	$(COMPOSE) build && $(COMPOSE) pull kafka redis forge || exit 1; \
	echo; echo "==> 3/5 starting anvil, kafka, redis"; \
	$(COMPOSE) up -d --wait --wait-timeout 180 anvil kafka redis || { $(COMPOSE) logs --tail=30; exit 1; }; \
	echo; echo "==> 4/5 in-container checks"; \
	echo "  forge: compiling and testing a solc 0.8.35 contract (amd64 image)"; \
	$(COMPOSE) run --rm -T forge > .forge.log 2>&1; st=$$?; \
	grep -E 'Compiling|Solc|Ran|PASS|FAIL|Error|passed|failed' .forge.log | sed 's/^/    /'; \
	if [ $$st -ne 0 ]; then echo; echo "  FAIL  forge (exit $$st); last lines of output:"; tail -n 40 .forge.log | sed 's/^/    /'; rm -f .forge.log; $(MAKE) --no-print-directory down; exit 1; fi; rm -f .forge.log; \
	echo "  smoke: rpc, kafka, redis round trips"; \
	$(COMPOSE) run --rm -T smoke || { $(MAKE) --no-print-directory down; exit 1; }; \
	echo; echo "==> 5/5 reachability from this machine"; \
	./host-verify.sh || { $(MAKE) --no-print-directory down; exit 1; }; \
	echo; echo "==> tearing down (images stay cached)"; \
	$(MAKE) --no-print-directory down; \
	echo; echo "ALL GOOD in $$(( $$(date +%s) - start ))s. You are ready for the interview project."

check: ## Host prerequisites only (no Docker containers started)
	@./check.sh

up: ## Start anvil, kafka, redis and leave them running
	$(COMPOSE) up -d --build --wait --wait-timeout 180 anvil kafka redis

verify: ## Run the in-container and host checks against a running stack
	$(COMPOSE) run --rm -T forge
	$(COMPOSE) run --rm -T smoke
	./host-verify.sh

down: ## Stop and remove everything this smoke test started
	@$(COMPOSE) down -v --remove-orphans >/dev/null 2>&1 || true

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make [target]\n\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  %-8s %s\n", $$1, $$2 }' $(MAKEFILE_LIST); echo
