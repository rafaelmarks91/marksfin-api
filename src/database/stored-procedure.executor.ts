import type { PoolConnection } from 'mariadb';
import { performance } from 'node:perf_hooks';
import { DatabaseError, ProcedureError } from '../shared/errors.js';
import { pool } from './pool.js';

export interface PbdInput {
  sys_id?: string;
  pbd_id: string;
  pbd_versao?: string;
  space_id?: string | null;
  usuario_id?: string | null;
  [key: string]: unknown;
}

export interface ProcedureEnvelope<TData = unknown> {
  success: boolean;
  code: string;
  message: string;
  data: TData;
  errors: unknown[];
  meta: Record<string, unknown>;
  durationMs: number;
}

function parseJsonMaybe(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value) as unknown;
  } catch {
    return value;
  }
}

function normalizeProcedureOutput<TData>(raw: unknown, durationMs: number): ProcedureEnvelope<TData> {
  const parsed = parseJsonMaybe(raw);
  const source = parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : {};
  const successValue = source.success ?? source.sucesso;
  const success = successValue === true || successValue === 1 || successValue === 'true';
  const data = parseJsonMaybe(source.data ?? source.dados ?? {}) as TData;
  const errors = (source.errors ?? source.erros ?? []) as unknown[];
  const rawCode = source.code;
  const rawMessage = source.message ?? source.mensagem;
  const code = typeof rawCode === 'string' ? rawCode : success ? 'SUCCESS' : 'PROCEDURE_ERROR';
  const message =
    typeof rawMessage === 'string'
      ? rawMessage
      : success
        ? 'Operacao realizada.'
        : 'Procedure retornou erro.';
  const meta =
    source.meta && typeof source.meta === 'object' ? (source.meta as Record<string, unknown>) : {};

  return { success, code, message, data, errors, meta, durationMs };
}

export function extractProcedureOutput(rows: unknown): unknown {
  if (!Array.isArray(rows)) return rows;
  const resultSets = rows as unknown[];
  for (const resultSet of resultSets) {
    if (resultSet && typeof resultSet === 'object' && !Array.isArray(resultSet)) {
      const row = resultSet as Record<string, unknown>;
      if (row['@object_output'] !== undefined) return row['@object_output'];
      if (row.object_output !== undefined) return row.object_output;
    }
    if (!Array.isArray(resultSet)) continue;
    for (const row of resultSet as Array<Record<string, unknown>>) {
      if (row['@object_output'] !== undefined) return row['@object_output'];
      if (row.object_output !== undefined) return row.object_output;
    }
  }
  return undefined;
}

/**
 * Chama `sp_sys_execucao_pbd` — o único ponto de acesso a regra de negócio (ver ADR-001 em
 * architecture-decisions.md). Nunca executa SQL direto nas tabelas de negócio.
 */
export async function executePbd<TData = unknown>(
  input: PbdInput,
  context: { requestId?: string; logger?: { info: (obj: object, msg: string) => void; error: (obj: object, msg: string) => void } } = {},
): Promise<ProcedureEnvelope<TData>> {
  let connection: PoolConnection | undefined;
  const startedAt = performance.now();
  const payload = { sys_id: 'marksfin', pbd_versao: 'v1', ...input };

  try {
    connection = await pool.getConnection();
    await connection.query('CALL sp_sys_execucao_pbd(?, @object_output)', [JSON.stringify(payload)]);
    const rows = (await connection.query('SELECT @object_output AS object_output')) as unknown;
    const durationMs = Math.round(performance.now() - startedAt);
    const envelope = normalizeProcedureOutput<TData>(extractProcedureOutput(rows), durationMs);

    context.logger?.info(
      {
        requestId: context.requestId,
        pbdId: payload.pbd_id,
        durationMs,
        procedureSuccess: envelope.success,
      },
      'procedure executed',
    );

    if (!envelope.success) {
      throw new ProcedureError(envelope.code, envelope.message, envelope.errors);
    }

    return envelope;
  } catch (error) {
    if (error instanceof ProcedureError) throw error;
    context.logger?.error(
      {
        requestId: context.requestId,
        pbdId: payload.pbd_id,
        err: error,
        durationMs: Math.round(performance.now() - startedAt),
      },
      'database procedure failed',
    );
    throw new DatabaseError();
  } finally {
    connection?.release().catch(() => undefined);
  }
}

export async function checkDatabaseReady(): Promise<{ ok: boolean; durationMs: number }> {
  let connection: PoolConnection | undefined;
  const startedAt = performance.now();
  try {
    connection = await pool.getConnection();
    await connection.query('SELECT 1 AS ok');
    return { ok: true, durationMs: Math.round(performance.now() - startedAt) };
  } catch {
    return { ok: false, durationMs: Math.round(performance.now() - startedAt) };
  } finally {
    connection?.release().catch(() => undefined);
  }
}
