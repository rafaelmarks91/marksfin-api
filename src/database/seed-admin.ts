import argon2 from 'argon2';
import { randomUUID } from 'node:crypto';
import { closePool, pool } from './pool.js';

/**
 * Cria (ou promove) o primeiro administrador da plataforma. Não passa pelo fluxo normal de
 * convite — é o único jeito de existir um admin sem já ter um admin pra convidar alguém.
 * Roda uma vez por ambiente: `npm run db:seed-admin`. Lê ADMIN_NAME/ADMIN_EMAIL/ADMIN_PASSWORD
 * do ambiente — nunca hardcoded, nunca versionado.
 */
async function seedAdmin(): Promise<void> {
  const name = process.env.ADMIN_NAME;
  const email = process.env.ADMIN_EMAIL?.trim().toLowerCase();
  const password = process.env.ADMIN_PASSWORD;

  if (!name || !email || !password) {
    console.error('Defina ADMIN_NAME, ADMIN_EMAIL e ADMIN_PASSWORD no ambiente antes de rodar.');
    process.exitCode = 1;
    return;
  }

  if (password.length < 8) {
    console.error('ADMIN_PASSWORD precisa ter pelo menos 8 caracteres.');
    process.exitCode = 1;
    return;
  }

  const connection = await pool.getConnection();

  try {
    const existingRows = (await connection.query('SELECT id, is_admin FROM users WHERE email = ? LIMIT 1', [
      email,
    ])) as Array<{ id: string; is_admin: number }>;

    if (existingRows.length > 0) {
      const existing = existingRows[0];
      if (existing.is_admin) {
        console.info(`Usuario ${email} ja existe e ja e admin. Nada a fazer.`);
        return;
      }

      await connection.query('UPDATE users SET is_admin = TRUE WHERE id = ?', [existing.id]);
      console.info(`Usuario ${email} promovido a admin.`);
      return;
    }

    const passwordHash = await argon2.hash(password, { type: argon2.argon2id });
    const userId = randomUUID();
    const spaceId = randomUUID();
    const memberId = randomUUID();
    const spaceName = `Finanças de ${name}`;

    await connection.beginTransaction();

    await connection.query(
      'INSERT INTO users (id, name, email, password_hash, status, is_admin) VALUES (?, ?, ?, ?, ?, ?)',
      [userId, name, email, passwordHash, 'ACTIVE', true],
    );
    await connection.query(
      'INSERT INTO financial_spaces (id, name, currency, timezone) VALUES (?, ?, ?, ?)',
      [spaceId, spaceName, 'BRL', 'America/Sao_Paulo'],
    );
    await connection.query('INSERT INTO space_members (id, space_id, user_id, role) VALUES (?, ?, ?, ?)', [
      memberId,
      spaceId,
      userId,
      'OWNER',
    ]);

    await connection.commit();
    console.info(`Admin ${email} criado.`);
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    await connection.release();
    await closePool();
  }
}

await seedAdmin();
