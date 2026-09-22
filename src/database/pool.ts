import mariadb from 'mariadb';
import { env } from '../shared/env.js';

export const pool = mariadb.createPool({
  host: env.DB_HOST,
  port: env.DB_PORT,
  user: env.DB_USER,
  password: env.DB_PASSWORD,
  database: env.DB_NAME,
  connectionLimit: env.DB_CONNECTION_LIMIT,
  charset: 'utf8mb4',
  multipleStatements: false,
});

export async function closePool(): Promise<void> {
  await pool.end();
}
