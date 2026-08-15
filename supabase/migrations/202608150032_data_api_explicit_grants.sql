-- 2026-08-15 — Compatibilidade com novos projetos Supabase/Data API.
-- Desde 2026, novas tabelas podem não receber grants implícitos para anon/authenticated.
-- RLS continua sendo a camada de autorização por linha; estes grants apenas tornam
-- as tabelas deliberadamente alcançáveis pelo PostgREST/supabase-js.

-- Nenhuma tabela fica diretamente exposta ao visitante anônimo por padrão.
revoke all privileges on all tables in schema public from anon;

-- A página pública de planos consulta a tabela diretamente; a policy existente
-- plans_public_read limita a active = true.
grant select on table public.plans to anon;

-- Usuários autenticados usam o Data API em vários módulos. Todas as tabelas da
-- aplicação possuem RLS; tabelas internas sem policies permanecem deny-by-default.
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Workers/backend usam service_role e precisam operar as tabelas internas.
grant all privileges on all tables in schema public to service_role;

-- Mantém o mesmo comportamento para tabelas criadas por migrations futuras.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant all privileges on tables to service_role;
