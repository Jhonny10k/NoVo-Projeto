# Homologação remota — Supabase

Data: 15/08/2026

## Projeto homologado

- Nome: `OrçaZap`
- Project ref: `kqrawaxfaahccrakqhrg`
- Região: `sa-east-1`
- URL: `https://kqrawaxfaahccrakqhrg.supabase.co`
- Status: `ACTIVE_HEALTHY`
- PostgreSQL: 17.6.1.155

A chave publicável existe e foi verificada pelo conector, mas **não é gravada neste relatório/ZIP**. `SUPABASE_SECRET_KEY`/Service Role também não é exportada nem inventada.

## Resultado geral

**PASS estrutural do Supabase + PASS do E2E transacional de RLS / E2E via login real do Supabase Auth ainda pendente.**

A cadeia completa da plataforma foi executada contra PostgreSQL hospedado. As migrations canônicas locais permanecem a fonte de verdade.

### Migrations canônicas

- primeira: `202608150001_initial_core.sql`
- última: `202608150036_unit_visibility_hardening.sql`
- total: **36 migrations canônicas**
- sequência verificada: `0001`–`0036`
- `DROP TABLE` incremental: **não encontrado**

## Defeitos encontrados pela homologação real

O PostgreSQL real encontrou três defeitos de migration que não haviam sido detectados pela validação textual:

1. **Agenda** — referência inválida ao buffer em `create_appointment`; corrigido na migration fonte `0011`.
2. **Analytics** — alias `day` conflitava com o parser do PostgreSQL 17; alterado para `day_value` em `0013`.
3. **Multiunidade** — erro de sintaxe na policy de memberships por unidade; corrigido em `0026`.

Depois, o contrato E2E multiunidade encontrou um quarto defeito de autorização:

4. **Visibilidade de unidades** — `organization_units_select_member` e `list_enterprise_units()` permitiam que um membro restrito visse unidades não atribuídas. A migration `0036_unit_visibility_hardening` passou a usar `can_access_unit_scope(...)` tanto na policy quanto na RPC.

Todos os problemas ganharam regressão local antes da aplicação remota.

## RLS e Data API

Verificação remota:

- tabelas públicas: **51**
- RLS habilitado: **51**
- RLS ausente: **0**

Smoke de privilégios:

- `anon` pode selecionar `public.plans`: **sim**
- `anon` pode selecionar `public.organizations`: **não**
- `authenticated` pode selecionar `external_outbox` diretamente: **não**
- `anon` pode executar `get_public_site(text)`: **sim**
- `anon` pode executar worker interno do outbox: **não**
- papel `authenticated` com usuário sem membership enxerga organizações: **0**

## E2E transacional de isolamento

Foi executado no PostgreSQL real um cenário temporário com:

- Tenant A e Tenant B;
- owner/admin do Tenant A;
- membro `sales` restrito do Tenant A;
- owner do Tenant B;
- duas unidades no Tenant A (`allowed` e `blocked`);
- uma unidade no Tenant B;
- leads distribuídos entre os escopos;
- entitlement `multi_unit` ativado apenas em plano temporário de teste.

Resultado: **16/16 verificações PASS**.

Validado na prática:

- admin vê as duas unidades e os dois leads do próprio tenant;
- membro restrito vê apenas a unidade atribuída;
- membro restrito vê apenas o lead da unidade atribuída;
- unidade e lead bloqueados retornam 0 linhas para o membro;
- tentativa de `INSERT` em lead da unidade bloqueada é negada;
- Tenant B não lê dados do Tenant A;
- `list_enterprise_units()` respeita o mesmo escopo de unidade.

Cleanup pós-teste confirmado:

```json
{"auth_users":0,"organizations":0,"memberships":0,"temp_plans":0}
```

Esse E2E valida PostgreSQL/RLS/roles reais. Ele **não substitui** o gate de autenticação via GoTrue, senha, JWT e PostgREST.

## Security Advisor

A migration `0033_security_advisor_hardening` corrigiu ACLs herdadas, `search_path` e extensão pública desnecessária. Após a migration `0036`, o Advisor foi executado novamente e não surgiu novo alerta crítico decorrente da mudança.

Os WARNs restantes de `SECURITY DEFINER` correspondem às RPCs públicas intencionais ou RPCs autenticadas que validam `auth.uid()`, papel, tenant e entitlement internamente. Tabelas internas com RLS sem policy permanecem deny-by-default.

Referência do Advisor: https://supabase.com/docs/guides/database/database-linter

## Performance Advisor

O Advisor foi executado novamente após `0036`. Permanecem somente avisos `INFO` de FKs secundárias sem índice e índices ainda não utilizados — esperado num banco novo sem workload real. Nenhum índice foi removido sem evidência de tráfego.

Referência: https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

## Supabase Cron

Migration `0035_temporal_automation_cron` mantém o job:

- nome: `platform-temporal-automations`
- schedule: `*/5 * * * *`
- comando: `select public.run_temporal_automations(now(), 500);`
- ativo: **sim**

Smoke manual do worker: `processed: 0`, resultado esperado para a base vazia.

## Testes locais

- migrations: **36/36** em sequência
- suíte Node: **148/148 PASS**
- runner local: `partial` apenas porque `node_modules`, credenciais E2E Auth e providers externos não estão disponíveis neste container

## O que ainda não foi provado

Ainda precisa ser exercitado através do Auth/frontend real:

- cadastro e confirmação de e-mail;
- reset de senha;
- convites de equipe;
- repetir isolamento Tenant A/B com **tokens Auth reais**;
- repetir multiunidade com admin/membro restrito via Auth + PostgREST;
- decisão comercial pendente: os 3 planos ativos mantêm `multi_unit=false`; a capability pode ser habilitada por entitlement, mas nenhum tier Enterprise/preço foi definido no escopo atual.
- Storage pelo cliente;
- Agenda/formulários públicos pelo app.

Também permanecem externos ao Supabase:

- Mercado Pago;
- Resend;
- Meta WhatsApp;
- OpenAI;
- Google;
- Vercel/build/deploy.

## Conclusão

O banco está aplicado, auditado e agora possui também **prova transacional real de isolamento multi-tenant e multiunidade**. O próximo gate é o mesmo cenário através do Supabase Auth/Data API, seguido de dependências/build e preview Vercel.
