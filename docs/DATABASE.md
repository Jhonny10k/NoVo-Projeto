# Banco de dados

## Multi-tenant
O tenant é identificado por `organization_id`. O acesso normal às tabelas de negócio é protegido por RLS e pelas funções `is_org_member` / `has_org_role`.

## Migrations

### `202608150001_initial_core.sql`
Fundação: profiles, organizations, membros, planos/assinaturas, catálogo, CRM, clientes, solicitações, orçamentos, tarefas, site, eventos e auditoria.

### `202608150002_commercial_core.sql`
Operações transacionais críticas:
- conversão lead → cliente;
- criação de orçamento com itens e total calculado no banco;
- liberação do link público;
- consulta pública por token;
- aceite/recusa/solicitação de alteração.

### `202608150003_platform_admin.sql`
`platform_admins` e RPCs administrativas globais, sempre condicionadas a `is_platform_admin()`.

### `202608150004_security_team_storage.sql`
- `rate_limit_windows`;
- RPC atômica `consume_rate_limit` reservada ao backend secreto;
- diretório seguro de membros;
- gestão de role/status com proteção do último proprietário;
- RPCs service-only para convites;
- trigger de ativação após confirmação de e-mail;
- bucket `organization-assets` com 5 MB e MIME restrito;
- policies de Storage isoladas pelo primeiro segmento do path.

### `202608150005_billing_mercadopago.sql`
- `billing_checkout_sessions`;
- `billing_webhook_events` com unicidade por evento do provider;
- campos de ciclo, valor contratado e status do provider em `subscriptions`;
- índice único para referência do provider;
- MRR real no dashboard admin.

### `202608150006_catalog_notifications.sql`
- unicidade case-insensitive de categoria por tenant;
- histórico `events` append-only para usuários autenticados;
- inserção direta de evento presa ao ator autenticado e a tipos operacionais permitidos;
- `notifications` materializadas por usuário;
- deduplicação por `(source_event_id, user_id)`;
- fan-out de notificações a partir de eventos comerciais reais;
- RPC estreita para marcar somente as próprias notificações como lidas.

## Dinheiro
Valores monetários críticos são armazenados em centavos (`bigint`). Totais de orçamento são calculados no PostgreSQL.

O billing salva `subscriptions.amount_cents`, evitando que uma alteração futura no preço do plano reescreva retroativamente o valor contratado. Para registros legados nulos, o dashboard possui fallback no preço do plano.

## Segurança
- nenhum tenant deve consultar dados de outro tenant diretamente;
- RPCs públicas retornam apenas os campos necessários;
- funções `service_*` não são executáveis por `anon`/`authenticated`;
- `billing_webhook_events` não possui policy de leitura para usuários comuns;
- `events` não possui policy de update/delete para usuários da aplicação;
- `notifications` não possui policy de update direto; `read_at` é alterado por RPC controlada;
- payloads sensíveis de integrações permanecem backend-only;
- ações críticas geram eventos ou `audit_logs`.

## Teste de isolamento
`npm run test:e2e` autentica duas contas de homologação pertencentes a organizações diferentes e prova que consultas cruzadas de organização e leads retornam listas vazias via RLS.

### `202608150031_security_definer_acl_hardening.sql`
- revoga `EXECUTE` público de helpers/triggers privilegiados iniciais;
- mantém funções públicas deliberadas separadas.

### `202608150032_data_api_explicit_grants.sql`
- explicita grants da Data API para projetos Supabase novos;
- `anon` recebe acesso direto somente a `plans`;
- `authenticated` recebe privilégios de tabela sempre subordinados à RLS;
- `service_role` mantém acesso server-side.

### `202608150033_security_advisor_hardening.sql`
- resultado do Security Advisor real;
- revoga EXECUTE `anon` por padrão em `SECURITY DEFINER`;
- allowlist das RPCs públicas;
- restringe `service_*` ao `service_role`;
- fixa `search_path`;
- remove `btree_gist` após confirmar ausência de dependências;
- revoga acesso direto de `authenticated` a tabelas internas.

### `202608150034_performance_advisor_hardening.sql`
- usa `(select auth.uid())` nas policies apontadas pelo Advisor;
- adiciona índices de FK nos fluxos mais relevantes;
- não remove índices classificados como “não usados” antes de existir workload real.

### `202608150035_temporal_automation_cron.sql`
- habilita `pg_cron`;
- agenda `platform-temporal-automations` a cada 5 minutos;
- executa `public.run_temporal_automations(now(), 500)`.

### `202608150036_unit_visibility_hardening.sql`

Restringe a leitura de `organization_units` e `list_enterprise_units()` ao escopo de unidade efetivamente acessível ao usuário. Owners/admins mantêm visão integral; membros restritos não veem unidades não atribuídas.


## Homologação remota do schema

Em 15/08/2026, as 36 migrations canônicas foram aplicadas a um Supabase novo (`kqrawaxfaahccrakqhrg`, `sa-east-1`).

Resultado:

- 51 tabelas públicas;
- 51 com RLS;
- 0 sem RLS;
- Security Advisor revisado e hardening aplicado;
- Performance Advisor revisado;
- Data API/ACL smoke testados;
- Supabase Cron ativo.

Detalhes: `docs/REMOTE_HOMOLOGATION.md`.

