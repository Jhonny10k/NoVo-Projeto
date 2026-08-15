# Homologação e gates de produção

## Objetivo

Este documento define a ordem reproduzível para provar que o produto pode ser lançado. Nenhum gate bloqueado deve ser tratado como aprovado.

## 1. Validação local sem serviços externos

```bash
npm run verify:migrations
npm run test
npm run homologate:local
```

`homologate:local` gera `HOMOLOGATION_LOCAL.json` com `pass`, `fail` ou `blocked` por etapa.

Se `node_modules` não existir, `lint`, `typecheck` e `build` ficam explicitamente como `blocked`.

## 2. Supabase de homologação

### Estado verificado em 15/08/2026

Projeto limpo criado e homologado:

- nome: `OrçaZap`;
- project ref: `kqrawaxfaahccrakqhrg`;
- região: `sa-east-1`;
- PostgreSQL real;
- 36 migrations canônicas aplicadas;
- 51/51 tabelas públicas com RLS;
- 0 tabelas públicas sem RLS;
- Data API/ACL smoke testados;
- Security Advisor e Performance Advisor revisados;
- Cron `platform-temporal-automations` ativo a cada 5 minutos.

A aplicação das migrations no PostgreSQL real encontrou três defeitos que não apareciam nos testes textuais e que foram corrigidos na fonte antes da continuação: buffer da Agenda, alias SQL do Analytics e uma policy de Multiunidade com parêntese extra.

### E2E transacional RLS já executado

No projeto remoto foi executado um cenário temporário com dois tenants, owner/admin, membro `sales`, duas unidades e leads em escopos distintos. Resultado: **16/16 verificações PASS**, incluindo bloqueio de leitura e INSERT em unidade não atribuída. O cleanup foi confirmado com 0 usuários/organizações/memberships/planos temporários restantes.

### E2E Auth ainda obrigatório

1. Configure URLs de Auth e Storage.
2. Crie duas organizações de teste e duas contas pertencentes a tenants diferentes.
3. Configure um cenário multiunidade com um admin, um membro restrito, uma unidade permitida e outra bloqueada.

### E2E de isolamento de tenant

Configure:

```env
E2E_SUPABASE_URL=
E2E_SUPABASE_PUBLISHABLE_KEY=
E2E_USER_A_EMAIL=
E2E_USER_A_PASSWORD=
E2E_USER_B_EMAIL=
E2E_USER_B_PASSWORD=
```

Execute:

```bash
npm run test:e2e:tenant
```

Resultado obrigatório: A não lê organização/leads de B e B não lê organização/leads de A.

### E2E de isolamento por unidade

Configure também:

```env
E2E_UNIT_ADMIN_EMAIL=
E2E_UNIT_ADMIN_PASSWORD=
E2E_UNIT_MEMBER_EMAIL=
E2E_UNIT_MEMBER_PASSWORD=
E2E_UNIT_ALLOWED_ID=
E2E_UNIT_BLOCKED_ID=
```

Execute:

```bash
npm run test:e2e:units
```

Resultado obrigatório: admin vê as duas unidades; membro restrito vê a unidade atribuída e não lê a unidade bloqueada nem seus leads.

## 3. Dependências e build

Com acesso ao registry:

```bash
npm install
npm run lint
npm run typecheck
npm run test
npm run build
```

Todos os comandos precisam terminar com exit code 0.

## 4. Integrações externas

Homologue separadamente:

- Mercado Pago: checkout, autorização, renovação, atraso/falha, cancelamento, webhook e idempotência.
- Resend: domínio/remetente, envio, webhook assinado, delivered/bounce e retry.
- Meta WhatsApp: validação da conexão, Webhook HMAC, inbound, template aprovado, delivered/read/failed.
- OpenAI: chave real, limites mensais, timeout/retry, custo estimado e `store:false`.
- Google Calendar: OAuth, refresh, backfill, update/cancel e idempotência do Event ID.
- Google Maps: geocoding server-side com chave restrita.
- Vercel: deploy, domínio customizado, DNS e rewrite por host.
- API/Webhooks de clientes: escopos, quotas, assinatura HMAC, SSRF guard, retry/dead-letter.

## 5. Browser/mobile

Teste manualmente os fluxos críticos em pelo menos celular e desktop:

- cadastro/login/reset;
- onboarding;
- site público e formulário;
- CRM/lead/cliente;
- orçamento e aceite público;
- Agenda pública/interna;
- billing;
- equipe/unidades;
- editor/preview/publicação;
- admin.

## 6. Critério de lançamento

Só classificar como `Pronto para lançamento` quando:

- migrations aplicadas em homologação;
- RLS tenant e unidade comprovadas por E2E;
- integrações críticas validadas;
- `lint`, `typecheck`, `test` e `build` verdes;
- deploy reproduzido;
- checklist mobile/browser concluído;
- Termos e Privacidade revisados juridicamente.

## 7. Hardening SECURITY DEFINER e Data API

- `0031` endurece ACLs de helpers/triggers internos.
- `0032` explicita grants da Data API para o padrão atual do Supabase.
- `0033` aplica o resultado do Security Advisor: revoga `EXECUTE` anônimo por padrão em `SECURITY DEFINER`, reabre apenas RPCs públicas deliberadas, restringe funções `service_*` ao `service_role`, fixa `search_path` e remove `btree_gist` sem uso.
- `0034` aplica hardening do Performance Advisor com `(select auth.uid())` nas policies sinalizadas e índices de FK de maior impacto.
- `0035` agenda `run_temporal_automations` no Supabase Cron em `*/5 * * * *`.

Smoke remoto confirmado:

- `anon`: `SELECT` em `plans` = permitido;
- `anon`: `SELECT` em `organizations` = negado;
- `anon`: RPC pública `get_public_site` = permitida;
- `anon`: worker `service_claim_external_outbox` = negado;
- `authenticated` sem membership: 0 organizações visíveis;
- worker temporal manual: executou sem erro;
- Cron: job ativo.

## 8. Projeto remoto atual

O projeto anterior incompatível foi excluído pelo usuário. O ambiente atual de homologação é o projeto limpo `kqrawaxfaahccrakqhrg`. Consulte `docs/REMOTE_HOMOLOGATION.md` para o registro objetivo da execução real.
