export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: string;
  public readonly fields?: Record<string, string>;

  constructor(
    message: string,
    statusCode = 400,
    code = 'APP_ERROR',
    fields?: Record<string, string>,
  ) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.fields = fields;
  }
}

/** Uma stored procedure (PBD) retornou `success: false`. Ver ADR-001. */
export class ProcedureError extends AppError {
  public readonly procedureErrors: unknown[];

  constructor(code = 'PROCEDURE_ERROR', message = 'Procedure retornou erro.', procedureErrors: unknown[] = []) {
    super(message, 422, code);
    this.name = 'ProcedureError';
    this.procedureErrors = procedureErrors;
  }
}

/** Falha de infraestrutura ao acessar o banco (conexão, timeout) — não é erro de regra. */
export class DatabaseError extends AppError {
  constructor(message = 'Banco de dados indisponível.') {
    super(message, 503, 'DATABASE_ERROR');
    this.name = 'DatabaseError';
  }
}
