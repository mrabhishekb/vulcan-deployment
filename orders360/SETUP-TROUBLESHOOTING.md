# Vulcan project setup — issues and fixes

This document records common problems when bringing this bundle online (Docker, `config.yaml`, CLI, permissions) and what fixed them.

---

## 1. Docker: host ports already in use (`4000`, `15432`)

**Symptom:** `make up` fails with `failed to bind host port ... address already in use` for transpiler services.

**Cause:** Something else on your machine is listening on the same host ports Compose maps (Cube on `4000`, optional published Postgres on `15432`).

**Fix:** In `docker/docker-compose.transpiler.yml`, published ports use env defaults so you can avoid clashes:

- `SEMANTIC_HOST_PORT` (default `14000` instead of `4000`)
- `SEMANTIC_PG_HOST_PORT` (default `25432` instead of `15432`)

Override in the shell or `.env` if you need the original numbers on a free host.

---

## 2. Explorer lock icons on folders / read-only project files

**Symptom:** Cursor/VS Code shows a lock on folders or files; saving fails.

**Cause:** Files or directories owned by another user (e.g. different UID or security software), so your user cannot write.

**Fix:**

```bash
sudo chown -R "$USER:$USER" /path/to/vulcan-project
```

Reload the editor. If ownership keeps reverting, investigate what process creates files as another user and exclude the project folder from that tool if needed.

---

## 3. `PermissionError` on `.logs` or `.cache` (CLI or containers)

**Symptom:** Tracebacks opening `/workspace/.logs/...` or unlinking `.cache/model_definition/...`.

**Cause:**

- **Docker CLI:** The bind mount is your project; if the process in the image runs as a UID that does not match file ownership, logging or cache updates fail.
- **Mixed runs:** Root vs non-root or different UIDs recreate files with incompatible ownership.

**Fix:**

- Use `--user "$(id -u):$(id -g)"` on `docker run` (this repo’s `Makefile` / `print-alias` does that).
- Align ownership: `chown -R "$USER:$USER" .logs .cache` (or `sudo` if needed).
- Clear stale cache: `make vulcan-cache-clean` or `rm -rf .cache`.

---

## 4. `/workspace` vs your real project path

**Symptom:** Errors mention `/workspace` while you work on the host.

**Cause:** Inside the Vulcan image the project is mounted at `/workspace`. Host-only paths like `/workspace` at the OS root are unrelated.

**Fix:** Use the project directory on disk for permissions. If running the CLI only through Docker, rely on the bind mount `…/your-project:/workspace` and do not create a random `/workspace` tree on the host unless you know you need it.

---

## 5. `.env` format for Docker Compose / Vulcan

**Symptom:** Warnings like `The "SNOWFLAKE_ACCOUNT" variable is not set` though you “filled” `.env`, or services restart in a loop.

**Cause:** `.env` must be `KEY=value` lines. Pasting YAML from `docker-compose` (e.g. `SNOWFLAKE_ACCOUNT: ${SNOWFLAKE_ACCOUNT}`) is invalid for Compose variable substitution.

**Fix:** Use straight variable assignments, for example:

```env
SNOWFLAKE_ACCOUNT=your_account
SNOWFLAKE_USER=your_user
SNOWFLAKE_PASSWORD=your_password
SNOWFLAKE_WAREHOUSE=your_wh
SNOWFLAKE_DATABASE=your_db
DOCKER_UID=1000
DOCKER_GID=1000
```

Adjust `DOCKER_UID` / `DOCKER_GID` to match `id -u` and `id -g` on Linux so bind-mounted files stay writable for `vulcan-api` when using `user:` in Compose.

---

## 6. `exec vulcan-api id` fails (`executable file not found`)

**Symptom:** `exec vulcan-api id` returns `id: not found`.

**Cause:** The slim image may not ship `coreutils` `id`.

**Fix:** Use Python inside the container, or inspect the image user:

```bash
docker compose ... exec vulcan-api python -c "import os; print(os.getuid(), os.getgid())"
docker inspect <container-id> --format '{{.Config.User}}'
```

---

## 7. `config.yaml` rejected: extra fields (`display_name`, `users[].type`, semantics `description`)

**Symptom:** `Invalid project config` / Pydantic “Extra inputs are not permitted”.

**Cause:** The CLI schema does not allow those fields at those locations (e.g. top-level `display_name`, `users.type`, or `description` on semantic models where only the SQL `MODEL` block should carry descriptions).

**Fix:** Put narrative text in `description` / metadata as allowed, align `users` with the documented schema (or comment out), remove disallowed `description` keys from `semantics/*.yml`, and put model descriptions in the `.sql` `MODEL (...)` block where applicable.

---

## 8. Linter rules “could not be found” (`RequireChecksForModels`, etc.)

**Symptom:** `Error: Rule requirechecksformodels could not be found`.

**Cause:** Rule names in `config.yaml` don’t exist in the Vulcan image version you run (often newer docs vs older `tmdcio/vulcan-snowflake` tag).

**Fix:** Trim `linter.warn_rules` to rules that exist for that image, or upgrade the image. A minimal safe entry used in this repo was `NoMissingAudits` only.

---

## 9. Postgres hostnames: `docker-warehouse-1`, `docker-statestore-1`, `statestore`

**Symptom:** `could not translate host name` when connecting.

**Cause:** Placeholder hostnames that don’t match any Compose **service name** on the `vulcan` network.

**Fix:** Use the real service name from `docker/docker-compose.infra.yml` — **`statestore`** — for both execution warehouse and state when using that Postgres, with `env_var(...)` fallbacks documented in `config.yaml`. Do not rely on non-existent `docker-*-1` names unless your own Compose defines them.

---

## 10. Connection timeout to `statestore:5432` from the CLI container

**Symptom:** DNS resolves but TCP times out.

**Cause:** Bridge/firewall quirks or Postgres not ready; sometimes routing via the **host-published** port works better.

**Fix:** Makefile adds `--add-host=host.docker.internal:host-gateway`. Optionally set **`VULCAN_STATESTORE_HOST=host.docker.internal`** and **`VULCAN_STATESTORE_PORT=5431`** in `.env` (matches host port mapping in infra compose). Ensure `make infra` is up and Postgres is healthy.

---

## 11. Warehouse works in “info” but warehouse fails while state succeeds (split env)

**Symptom:** State connection OK; warehouse DNS or auth fails.

**Cause:** **`connection`** and **`state_connection`** used different env var names, so one path could resolve `127.0.0.1:5431` and the other still used `statestore`.

**Fix:** Use the **same** host/port resolution for both blocks (see current `config.yaml`: `VULCAN_STATESTORE_*` with fallback to `STATESTORE_*`). When running CLI **on the host**, set e.g. `VULCAN_STATESTORE_HOST=127.0.0.1` and `VULCAN_STATESTORE_PORT=5431` for both.

---

## 12. `FATAL: database "warehouse" does not exist`

**Symptom:** Data warehouse connection fails; state DB works.

**Cause:** `config.yaml` sets `gateways.default.connection.database` to **`warehouse`**, but only **`statestore`** was created by default Postgres init.

**Fix:**

- One-time: `make warehouse-db` (runs `CREATE DATABASE warehouse` against the statestore container), **or**
- Manually: `psql` to `localhost:5431` and `CREATE DATABASE warehouse;`

New installs: `docker/postgres-init/02-create-warehouse.sql` runs on **first** empty volume when the init mount is present.

---

## 13. Snowflake vs Postgres as execution warehouse

**Symptom:** Confusion after switching examples between Snowflake credentials and local Postgres.

**Cause:** This bundle can target either; `.env` may list `SNOWFLAKE_*` while `config.yaml` uses Postgres for local modeling.

**Fix:** Keep **`model_defaults.dialect`** aligned with the **`gateways.default.connection.type`** you actually use. For local Docker Postgres, use `postgres` and the `warehouse` + `statestore` databases on **`statestore`**. For Snowflake-only flows, follow the image and docs for Snowflake gateway settings (and expect SQL/dialect differences in models).

---

## Quick command checklist

| Step | Command |
|------|---------|
| Network | `make network` |
| Infra (Postgres + MinIO) | `make infra` |
| Create `warehouse` DB | `make warehouse-db` |
| Clear model cache | `make vulcan-cache-clean` |
| Print `vulcan` Docker alias | `make print-alias` |
| Run CLI in Docker | `make vulcan-cli CMD="info"` |

---

## Optional: `minio-init` naming

The infra compose file uses a volume key spelled `objeststore` (typo). It works as long as it is consistent; renaming would require a one-time migration of named volumes—only do that if you are comfortable cleaning Docker volumes.

---

*Generated from setup debugging. Adjust versions and paths to match your machine and image tags.*
