import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { closePool, pool } from './pool.js';

function splitStatements(source: string): string[] {
  const statements: string[] = [];
  let delimiter = ';';
  let buffer = '';

  for (const line of source.split(/\r?\n/)) {
    const directive = line.trim().match(/^DELIMITER\s+(.+)$/i);
    if (directive) {
      delimiter = directive[1] ?? ';';
      continue;
    }

    buffer += `${line}\n`;
    if (!buffer.trimEnd().endsWith(delimiter)) continue;

    const statement = buffer.trimEnd().slice(0, -delimiter.length).trim();
    if (statement) statements.push(statement);
    buffer = '';
  }

  if (buffer.trim()) statements.push(buffer.trim());
  return statements;
}

export async function runMigrations(): Promise<void> {
  const directory = path.dirname(fileURLToPath(import.meta.url));
  const migrationsDirectory = path.join(directory, 'migrations');
  const files = (await readdir(migrationsDirectory)).filter((file) => file.endsWith('.sql')).sort();
  const connection = await pool.getConnection();

  try {
    for (const file of files) {
      const source = await readFile(path.join(migrationsDirectory, file), 'utf8');
      for (const statement of splitStatements(source)) await connection.query(statement);
      console.info(`Migration aplicada: ${file}`);
    }
  } finally {
    await connection.release();
    await closePool();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await runMigrations();
}
