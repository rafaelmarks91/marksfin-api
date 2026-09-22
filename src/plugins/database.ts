import fp from 'fastify-plugin';
import type { FastifyInstance } from 'fastify';
import { closePool, pool } from '../database/pool.js';
import { checkDatabaseReady, executePbd } from '../database/stored-procedure.executor.js';

export interface DatabaseDecoration {
  pool: typeof pool;
  executePbd: typeof executePbd;
  checkReady: typeof checkDatabaseReady;
}

declare module 'fastify' {
  interface FastifyInstance {
    db: DatabaseDecoration;
  }
}

export default fp(async function databasePlugin(fastify: FastifyInstance) {
  fastify.decorate('db', { pool, executePbd, checkReady: checkDatabaseReady });

  fastify.addHook('onClose', async () => {
    await closePool();
  });
});
