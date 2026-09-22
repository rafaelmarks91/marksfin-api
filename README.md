# marksfin-api

Backend API for **MarksFin**, a personal-finance web app.

This repository holds only the backend (Marco 0 / Fundação): a Fastify + TypeScript HTTP API,
MariaDB (no ORM — all business logic lives in stored procedures, see
[architecture-decisions.md](./architecture-decisions.md)), Zod validation, and Vitest tests.

This is a polyrepo setup. The sibling repo `marksfin-app` holds the frontend, product docs, and
brand kit.

## Prerequisites

- Node.js (see `.nvmrc` for the pinned version)
- Docker (for running the local MariaDB database)

## Running locally

```bash
docker compose up -d
cp .env.example .env
npm install
npm run db:migrate
npm run dev
```

The API will listen on the port configured in `.env` (default `3333`), with routes mounted
under `/api/v1`. `npm run db:migrate` applies the versioned `.sql` files in
`src/database/migrations/` in order (schema, then the PBD executor infrastructure) — see
[backend-backlog.md](./backend-backlog.md) for which stored procedures still need to be written.

The `marksfin` database itself must exist before the first migration — it's a one-time step,
not part of the migration runner:

```sql
CREATE DATABASE marksfin CHARACTER SET utf8mb4;
```

Don't add an explicit `COLLATE` here — let it inherit the server's default. Stored procedure
local variables always use the server's default collation regardless of the database's, so
pinning a different one on the database causes `Illegal mix of collations` errors the moment a
procedure compares a variable against a table column (hit and fixed while validating this
migration against the shared server — see the commit history). `docker-compose.yml`'s MariaDB
image already creates the database this way via `MARIADB_DATABASE`, so local dev is unaffected.

## Scripts

- `npm run dev` — run the API in watch mode
- `npm run build` — compile TypeScript to `dist`
- `npm start` — run the compiled API
- `npm run deploy` / `npm run start:prod` — build and (re)start via PM2
- `npm run lint` — lint the codebase
- `npm run typecheck` — type-check without emitting
- `npm test` — run the test suite
- `npm run db:migrate` — apply pending `.sql` migrations

## Production: PM2 + Apache

This API is deployed the same way as the sibling `teraodonto-api` project on the shared
production server: PM2 keeps the compiled Node process alive, bound only to `127.0.0.1`, and a
local Apache vhost reverse-proxies the public domain to it. `docker-compose.yml` is a local
development convenience only (it just runs MariaDB) — it is not used in production.

Ports already in use by other apps on that server: `teraodonto-api` listens on `3000` and
`teraodonto-site` on `3001`. This API uses `3333` (`PORT` in `.env`) to avoid colliding with
either.

```bash
npm install
npm run build
pm2 start ecosystem.config.cjs
```

Apache example:

```apache
ProxyPass /api http://127.0.0.1:3333/api
ProxyPassReverse /api http://127.0.0.1:3333/api
RequestHeader set X-Forwarded-Proto "https"
```

Set `HOST=127.0.0.1` in the production `.env` so the API is only reachable through the local
Apache proxy, never directly from the internet.
