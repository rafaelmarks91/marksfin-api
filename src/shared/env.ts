import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().int().positive().default(3333),
  APP_ORIGIN: z.string().default('*'),
  DB_HOST: z.string().min(1, 'DB_HOST is required'),
  DB_PORT: z.coerce.number().int().positive().default(3306),
  DB_USER: z.string().min(1, 'DB_USER is required'),
  DB_PASSWORD: z.string().default(''),
  DB_NAME: z.string().default('marksfin'),
  DB_CONNECTION_LIMIT: z.coerce.number().int().positive().default(10),
  SESSION_SECRET: z.string().min(16, 'SESSION_SECRET must have at least 16 characters'),
  INVITATION_TOKEN_TTL_HOURS: z.coerce.number().int().positive().default(168),
  PASSWORD_RESET_TTL_MINUTES: z.coerce.number().int().positive().default(30),
  SMTP_HOST: z.string().optional(),
  SMTP_PORT: z.string().optional(),
  SMTP_USER: z.string().optional(),
  SMTP_PASSWORD: z.string().optional(),
  MAIL_FROM: z.string().optional(),
});

export type Env = z.infer<typeof envSchema>;

function parseEnv(): Env {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    const issues = result.error.issues
      .map((issue) => `  - ${issue.path.join('.')}: ${issue.message}`)
      .join('\n');

    console.error(`Invalid environment variables:\n${issues}`);
    process.exit(1);
  }

  return result.data;
}

export const env = parseEnv();
