import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('branding is centralized and environment-driven', () => {
  const brand = read('src/lib/brand.ts');
  const layout = read('src/app/layout.tsx');
  const header = read('src/components/marketing/header.tsx');
  const footer = read('src/components/marketing/footer.tsx');
  const openapi = read('src/lib/public-api/openapi.ts');
  const env = read('.env.example');

  assert.match(brand, /NEXT_PUBLIC_APP_NAME/);
  assert.match(brand, /NEXT_PUBLIC_APP_DESCRIPTION/);
  assert.match(layout, /APP_NAME/);
  assert.match(layout, /APP_DESCRIPTION/);
  assert.match(header, /APP_NAME/);
  assert.match(footer, /APP_NAME/);
  assert.match(openapi, /APP_NAME/);
  assert.match(env, /NEXT_PUBLIC_APP_NAME=/);
  assert.match(env, /NEXT_PUBLIC_APP_DESCRIPTION=/);
});

test('customer-facing runtime does not hardcode the historical OrçaZap brand', () => {
  const runtimeFiles = [
    'src/app/layout.tsx',
    'src/components/marketing/header.tsx',
    'src/components/marketing/footer.tsx',
    'src/lib/brand.ts',
    'src/lib/public-api/openapi.ts',
  ];

  for (const path of runtimeFiles) {
    assert.doesNotMatch(read(path), /OrçaZap/i, `${path} must not hardcode historical branding`);
  }
});

test('GitHub CI enforces migrations, lint, typecheck, tests and build', () => {
  const ci = read('.github/workflows/ci.yml');

  assert.match(ci, /npm run verify:migrations/);
  assert.match(ci, /npm run lint/);
  assert.match(ci, /npm run typecheck/);
  assert.match(ci, /npm test/);
  assert.match(ci, /npm run build/);
  assert.match(ci, /node-version:\s*22/);
});

test('deploy preflight lists missing variable names without printing secret values', async () => {
  const { spawnSync } = await import('node:child_process');
  const result = spawnSync(process.execPath, ['scripts/deploy-preflight.mjs'], {
    cwd: new URL('..', import.meta.url),
    env: {
      ...process.env,
      NEXT_PUBLIC_APP_NAME: 'Marca Teste',
      NEXT_PUBLIC_APP_URL: 'https://preview.example.com',
      NEXT_PUBLIC_SUPABASE_URL: 'https://example.supabase.co',
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'publishable-test-value',
      SUPABASE_SECRET_KEY: 'super-secret-test-value',
      RATE_LIMIT_SALT: 'rate-secret-test-value',
      BILLING_PROVIDER: 'disabled',
    },
    encoding: 'utf8',
  });

  assert.equal(result.status, 0);
  const parsed = JSON.parse(result.stdout);
  assert.equal(parsed.status, 'ready_for_build');
  assert.doesNotMatch(result.stdout, /super-secret-test-value/);
  assert.doesNotMatch(result.stdout, /rate-secret-test-value/);
  assert.doesNotMatch(result.stdout, /publishable-test-value/);
});
