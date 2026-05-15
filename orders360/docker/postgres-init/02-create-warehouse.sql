-- Separate logical DB for SQLMesh / Vulcan physical warehouse (config.yaml gateways.default.connection.database).
-- Runs only on first Postgres volume init (see docker-compose.infra.yml mount).
CREATE DATABASE warehouse;
