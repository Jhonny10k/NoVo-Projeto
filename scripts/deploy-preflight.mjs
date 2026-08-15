#!/usr/bin/env node

const groups = {
  core: [
    'NEXT_PUBLIC_APP_NAME',
    'NEXT_PUBLIC_APP_URL',
    'NEXT_PUBLIC_SUPABASE_URL',
    'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
    'SUPABASE_SECRET_KEY',
    'RATE_LIMIT_SALT',
  ],
  billing: ['MERCADO_PAGO_ACCESS_TOKEN', 'MERCADO_PAGO_WEBHOOK_SECRET'],
  email: ['RESEND_API_KEY', 'RESEND_FROM_EMAIL', 'RESEND_WEBHOOK_SECRET'],
  ai: ['OPENAI_API_KEY'],
  integrations: ['INTEGRATION_ENCRYPTION_KEY', 'OUTBOX_WORKER_SECRET'],
  whatsapp: ['META_GRAPH_API_VERSION', 'META_WHATSAPP_APP_SECRET', 'META_WHATSAPP_VERIFY_TOKEN'],
  google: ['GOOGLE_OAUTH_CLIENT_ID', 'GOOGLE_OAUTH_CLIENT_SECRET', 'GOOGLE_MAPS_API_KEY'],
  publicApi: ['PUBLIC_API_KEY_PEPPER'],
  whiteLabel: ['VERCEL_ACCESS_TOKEN', 'VERCEL_PROJECT_ID'],
};

const has = (key) => Boolean(process.env[key]?.trim());
const summarize = (keys) => ({
  configured: keys.filter(has),
  missing: keys.filter((key) => !has(key)),
});

const result = Object.fromEntries(
  Object.entries(groups).map(([name, keys]) => [name, summarize(keys)]),
);

const coreReady = result.core.missing.length === 0;
const billingEnabled = (process.env.BILLING_PROVIDER || 'disabled') !== 'disabled';
const billingReady = !billingEnabled || result.billing.missing.length === 0;

const output = {
  status: coreReady && billingReady ? 'ready_for_build' : 'blocked',
  coreReady,
  billingEnabled,
  billingReady,
  groups: Object.fromEntries(
    Object.entries(result).map(([name, value]) => [name, {
      configuredCount: value.configured.length,
      missing: value.missing,
    }]),
  ),
};

console.log(JSON.stringify(output, null, 2));
process.exitCode = output.status === 'ready_for_build' ? 0 : 1;
