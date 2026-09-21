# marksfin-api

Backend API for **MarksFin**, a personal-finance web app.

This repository holds only the backend (Marco 0 / Fundação): a Fastify + TypeScript HTTP API,
Prisma ORM targeting a MariaDB-compatible MySQL database, Zod validation, and Vitest tests.

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
npm run db:generate
npm run db:migrate
npm run dev
```

The API will listen on the port configured in `.env` (default `3333`), with routes mounted
under `/api/v1`.

## Scripts

- `npm run dev` — run the API in watch mode
- `npm run build` — compile TypeScript to `dist`
- `npm start` — run the compiled API
- `npm run lint` — lint the codebase
- `npm run typecheck` — type-check without emitting
- `npm test` — run the test suite
- `npm run db:generate` — generate the Prisma client
- `npm run db:migrate` — run Prisma migrations in dev mode
