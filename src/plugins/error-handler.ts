import fp from 'fastify-plugin';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import { AppError } from '../shared/errors.js';

interface ErrorEnvelope {
  error: {
    code: string;
    message: string;
    fields?: Record<string, string>;
    requestId: string;
  };
}

function zodErrorToFields(error: ZodError): Record<string, string> {
  const fields: Record<string, string> = {};

  for (const issue of error.issues) {
    const path = issue.path.join('.') || '(root)';
    fields[path] = issue.message;
  }

  return fields;
}

export default fp(async function errorHandlerPlugin(fastify: FastifyInstance) {
  fastify.setErrorHandler((error: unknown, request: FastifyRequest, reply: FastifyReply) => {
    request.log.error(error);

    if (error instanceof ZodError) {
      const envelope: ErrorEnvelope = {
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Revise os campos informados.',
          fields: zodErrorToFields(error),
          requestId: request.id,
        },
      };
      reply.status(400).send(envelope);
      return;
    }

    if (error instanceof AppError) {
      const envelope: ErrorEnvelope = {
        error: {
          code: error.code,
          message: error.message,
          ...(error.fields ? { fields: error.fields } : {}),
          requestId: request.id,
        },
      };
      reply.status(error.statusCode).send(envelope);
      return;
    }

    const envelope: ErrorEnvelope = {
      error: {
        code: 'INTERNAL_ERROR',
        message: 'Ocorreu um erro inesperado. Tente novamente mais tarde.',
        requestId: request.id,
      },
    };
    reply.status(500).send(envelope);
  });
});
