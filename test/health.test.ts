import { describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';

describe('GET /api/v1/health', () => {
  it('returns 200 with status ok', async () => {
    const app = buildApp();

    const response = await app.inject({
      method: 'GET',
      url: '/api/v1/health',
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.status).toBe('ok');

    await app.close();
  });
});
