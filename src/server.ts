import { env } from './shared/env.js';
import { buildApp } from './app.js';

async function main() {
  const fastify = buildApp();

  try {
    await fastify.listen({ port: env.PORT, host: '0.0.0.0' });
    fastify.log.info(`MarksFin API listening on http://0.0.0.0:${env.PORT}`);
  } catch (error) {
    fastify.log.error(error);
    process.exit(1);
  }
}

main();
