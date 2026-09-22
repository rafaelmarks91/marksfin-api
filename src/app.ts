import type { IncomingMessage } from 'node:http';
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import { env } from './shared/env.js';
import errorHandlerPlugin from './plugins/error-handler.js';
import databasePlugin from './plugins/database.js';
import healthRoutes from './modules/health/health.routes.js';

function genReqId(req: IncomingMessage): string {
  const incoming = req.headers['x-request-id'];

  if (typeof incoming === 'string' && incoming.length > 0) {
    return incoming;
  }

  if (Array.isArray(incoming) && incoming.length > 0 && incoming[0]) {
    return incoming[0];
  }

  return `req_${randomUUID()}`;
}

function resolveAppOrigin(): boolean | string | string[] {
  if (env.APP_ORIGIN === '*') {
    if (env.NODE_ENV !== 'development') {
      // Never fall back to a wildcard origin outside of development.
      return false;
    }
    return true;
  }

  const origins = env.APP_ORIGIN.split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);

  return origins.length > 1 ? origins : origins[0];
}

export function buildApp() {
  const fastify = Fastify({
    genReqId,
    logger: {
      level: env.NODE_ENV === 'test' ? 'silent' : 'info',
    },
  });

  fastify.register(cors, {
    origin: resolveAppOrigin(),
  });

  fastify.register(errorHandlerPlugin);
  fastify.register(databasePlugin);

  fastify.register(
    async (instance) => {
      instance.register(healthRoutes);
    },
    { prefix: '/api/v1' },
  );

  return fastify;
}
