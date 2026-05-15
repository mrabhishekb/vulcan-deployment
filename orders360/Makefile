
# Vulcan Snowflake local stack — self-contained under this directory.
#
# One command:  make up    (needs .env from env.example)
#
# Run the CLI via Docker image (no pip):  make vulcan-cli CMD="plan"
# Or paste the alias from:               make print-alias
#
# Share without the monorepo: copy this folder (Makefile, config.yaml, env.example,
# models/, semantics/, docker/*.yml). Pull images from your registry.
#
VULCAN_IMAGE ?= tmdcio/vulcan-snowflake:0.228.1.12-rc2

# Same as config.yaml (b2b_saas): transpiler + graphql by Docker DNS on network vulcan.
VULCAN_DOCKER_COMMON = docker run -it --rm --network=vulcan \
	-v "$$(pwd):/workspace" -w /workspace \
	--env-file .env \
	-e STATESTORE_HOST=statestore \
	-e STATESTORE_PORT=5432 \
	-e MINIO_ENDPOINT=http://minio:9000 \
	-e VULCAN__TRANSPILER__BASE_URL=http://vulcan-transpiler-api:8100 \
	-e VULCAN__GRAPHQL__BASE_URL=http://vulcan-graphql:3000 \
	$(VULCAN_IMAGE)

.PHONY: help up down network certs infra warehouse transpiler transpiler-down setup \
	vulcan-cli vulcan-api-docker vulcan-api-pip print-alias \
	vulcan-up vulcan-down proxy-up proxy-down infra-down all-down all-clean

DOCKER_COMPOSE = docker compose

help: ## Show targets
	@echo 'examples/try — Snowflake + Docker (portable: only this directory + .env)'
	@echo 'CLI image: $(VULCAN_IMAGE)'
	@echo ''
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'

print-alias: ## Print a shell alias (copy into ~/.zshrc); same image as docker-compose.vulcan.yml
	@printf '%s\n' 'alias vulcan='"'"'docker run -it --network=vulcan --rm -v "$$PWD:/workspace" -w /workspace --env-file .env -e STATESTORE_HOST=statestore -e STATESTORE_PORT=5432 -e MINIO_ENDPOINT=http://minio:9000 -e VULCAN__TRANSPILER__BASE_URL=http://vulcan-transpiler-api:8100 -e VULCAN__GRAPHQL__BASE_URL=http://vulcan-graphql:3000 '"$(VULCAN_IMAGE)"' vulcan'"'"''

vulcan-cli: ## Run vulcan in Docker: make vulcan-cli CMD="plan"  (needs .env + make setup)
	@test -f .env || (echo "Create .env from env.example" && exit 1)
	@test -n "$(CMD)" || (echo 'Usage: make vulcan-cli CMD="plan"   or   CMD="run"' && exit 1)
	$(VULCAN_DOCKER_COMMON) vulcan -p . $(CMD)

vulcan-api-docker: ## Vulcan API :8000 using $(VULCAN_IMAGE) (needs .env + infra + transpiler)
	@test -f .env || (echo "Create .env from env.example" && exit 1)
	docker run -it --rm --network=vulcan \
		-v "$$(pwd):/workspace" -w /workspace \
		--env-file .env \
		-e STATESTORE_HOST=statestore \
		-e STATESTORE_PORT=5432 \
		-e MINIO_ENDPOINT=http://minio:9000 \
		-e VULCAN__TRANSPILER__BASE_URL=http://vulcan-transpiler-api:8100 \
		-e VULCAN__GRAPHQL__BASE_URL=http://vulcan-graphql:3000 \
		-p 8000:8000 \
		$(VULCAN_IMAGE) vulcan -p . api --host 0.0.0.0 --port 8000

vulcan-api-pip: ## Vulcan API on host :8000 (local pip install vulcan; .env with STATESTORE_HOST=localhost)
	vulcan -p . api --host 0.0.0.0 --port 8000

up: ## One command: full stack (needs .env). Order: infra → transpiler → Vulcan → MySQL proxy
	@test -f .env || (echo "Create .env: cp env.example .env && edit SNOWFLAKE_*" && exit 1)
	$(MAKE) network
	$(MAKE) certs
	$(MAKE) infra
	$(MAKE) transpiler
	$(MAKE) vulcan-up
	$(MAKE) proxy-up
	@echo ""
	@echo "Ready: API http://localhost:8000/redoc  |  GraphQL http://localhost:3000"
	@echo "       Transpiler http://127.0.0.1:8100  |  MinIO http://localhost:9001"
	@echo "CLI:  make vulcan-cli CMD=\"plan\"   (uses $(VULCAN_IMAGE))"

down: all-down ## Alias: stop everything

certs: ## TLS for MySQL proxy + vulcan-mysql (docker/ssl/)
	@mkdir -p docker/ssl
	@if [ -f docker/ssl/server.crt ] && [ -f docker/ssl/server.key ]; then \
		echo "docker/ssl/server.crt present — skip"; \
	else \
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
			-keyout docker/ssl/server.key -out docker/ssl/server.crt \
			-subj "/CN=vulcan-mysql" 2>/dev/null; \
		echo "Created docker/ssl/server.crt"; \
	fi

network: ## Docker network vulcan
	@docker network create vulcan 2>/dev/null || true

infra: network ## PostgreSQL statestore + MinIO
	$(DOCKER_COMPOSE) -p vulcan-statestore -f docker/docker-compose.infra.yml up -d --quiet-pull

warehouse: ## Not used — warehouse is Snowflake (SNOWFLAKE_* in .env)
	@echo "Use Snowflake; set SNOWFLAKE_* in .env (see env.example)."

transpiler: network ## Transpiler API :8100, semantic :4000
	VERSION=$${VERSION:-0.0.0-exp.02} $(DOCKER_COMPOSE) -p vulcan-transpiler -f docker/docker-compose.transpiler.yml up -d --quiet-pull
	@echo "Transpiler: http://127.0.0.1:8100"

transpiler-down: ## Stop transpiler
	$(DOCKER_COMPOSE) -p vulcan-transpiler -f docker/docker-compose.transpiler.yml down

setup: network infra transpiler ## Statestore + MinIO + transpiler (then: make vulcan-up or vulcan-api-docker)
	@echo "Optional: make vulcan-up && make proxy-up  (proxy needs vulcan-mysql running)"

vulcan-up: ## Vulcan API + GraphQL + MySQL containers (needs .env + make certs). Image: VERSION in compose
	@test -f .env || (echo "Create .env from env.example (SNOWFLAKE_* required)." && exit 1)
	@test -f docker/ssl/server.crt || ($(MAKE) certs)
	VERSION=$${VERSION:-0.228.1.12-rc2} $(DOCKER_COMPOSE) -f docker/docker-compose.vulcan.yml --env-file .env up -d
	@echo "vulcan-api: http://localhost:8000/redoc"

vulcan-down: ## Stop Vulcan API stack
	@if [ -f .env ]; then VERSION=$${VERSION:-0.228.1.12-rc2} $(DOCKER_COMPOSE) -f docker/docker-compose.vulcan.yml --env-file .env down; \
	else VERSION=$${VERSION:-0.228.1.12-rc2} $(DOCKER_COMPOSE) -f docker/docker-compose.vulcan.yml down; fi

proxy-up: network certs ## MySQL proxy :3306 (after vulcan-mysql is up, for BI tools)
	MYSQL_VERSION=$${MYSQL_VERSION:-0.0.0-exp.04} $(DOCKER_COMPOSE) -p vulcan-proxy -f docker/docker-compose.proxy.yml up -d --quiet-pull

proxy-down: ## Stop MySQL proxy
	$(DOCKER_COMPOSE) -p vulcan-proxy -f docker/docker-compose.proxy.yml down

infra-down: ## Stop statestore + minio
	$(DOCKER_COMPOSE) -p vulcan-statestore -f docker/docker-compose.infra.yml down

all-down: proxy-down vulcan-down transpiler-down infra-down ## Stop all compose stacks
	@echo "Stopped."

all-clean: all-down ## Remove volumes (destructive)
	@$(DOCKER_COMPOSE) -p vulcan-proxy -f docker/docker-compose.proxy.yml down -v 2>/dev/null || true
	@$(DOCKER_COMPOSE) -p vulcan-transpiler -f docker/docker-compose.transpiler.yml down -v 2>/dev/null || true
	@$(DOCKER_COMPOSE) -p vulcan-statestore -f docker/docker-compose.infra.yml down -v 2>/dev/null || true
	@$(DOCKER_COMPOSE) -f docker/docker-compose.vulcan.yml down -v 2>/dev/null || true
	@echo "Volumes removed where applicable."
