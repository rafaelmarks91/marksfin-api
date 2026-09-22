import { env } from './shared/env.js';
import { buildApp } from './app.js';

async function main() {
  const fastify = buildApp();

  try {
    await fastify.listen({ port: env.PORT, host: env.HOST });
    fastify.log.info(`MarksFin API listening on http://${env.HOST}:${env.PORT}`);
  } catch (error) {
    fastify.log.error(error);
    process.exit(1);
  }
}

main();
