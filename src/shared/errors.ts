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
