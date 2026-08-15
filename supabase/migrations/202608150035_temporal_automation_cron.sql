-- 2026-08-15 — Scheduler real das automações temporais no Supabase Cron.
-- O mesmo nome de job atualiza/substitui a definição anterior de forma idempotente.

create extension if not exists pg_cron;

select cron.schedule(
  'platform-temporal-automations',
  '*/5 * * * *',
  $$select public.run_temporal_automations(now(), 500);$$
);
