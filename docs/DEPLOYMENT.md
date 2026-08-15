# Deploy

## Estado da homologação em 15/08/2026

O Supabase de homologação já existe e foi validado:

- project ref: `kqrawaxfaahccrakqhrg`;
- região: `sa-east-1`;
- status verificado: `ACTIVE_HEALTHY`;
- 36 migrations canônicas aplicadas;
- 51/51 tabelas públicas com RLS;
- Security/Performance Advisors revisados;
- Supabase Cron temporal ativo a cada 5 minutos.

O deploy Vercel **ainda não foi executado**. O conector disponível nesta sessão apresentou incompatibilidade de schema para envio da árvore local, o CLI Vercel não está instalado e o registry npm não respondeu às tentativas de instalação. Não trate esse gate como concluído.

## 1. Supabase

Use o projeto homologado ou um ambiente novo criado a partir das mesmas 36 migrations.

Nunca coloque `SUPABASE_SECRET_KEY`/Service Role no navegador, repositório ou ZIP.

A URL do projeto homologado é:

```text
https://kqrawaxfaahccrakqhrg.supabase.co
```

A Publishable Key deve ser obtida no ambiente/secret manager e configurada em `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Ela não é gravada na documentação do projeto.

## 2. Migrations

A fonte de verdade é:

```text
supabase/migrations/
```

Aplique em ordem lexicográfica:

```text
202608150001_initial_core.sql
...
202608150035_temporal_automation_cron.sql
202608150036_unit_visibility_hardening.sql
```

Não pule migrations intermediárias e não altere produção manualmente.

As migrations `0033` e `0034` incorporam hardening encontrado pelos Advisors reais do Supabase. A `0035` configura o Cron das automações temporais. A `0036` fecha a visibilidade de unidades para membros restritos conforme o contrato E2E.

## 3. Variáveis da aplicação

Use `.env.example` como fonte atual.

### Núcleo obrigatório

```text
NEXT_PUBLIC_APP_URL
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
SUPABASE_SECRET_KEY
RATE_LIMIT_SALT
DEMO_MODE=false
```

### Billing / Mercado Pago

```text
BILLING_PROVIDER
MERCADO_PAGO_ACCESS_TOKEN
MERCADO_PAGO_WEBHOOK_SECRET
```

### IA

```text
AI_PROVIDER
OPENAI_API_KEY
OPENAI_MODEL
OPENAI_INPUT_PRICE_PER_1M_USD
OPENAI_OUTPUT_PRICE_PER_1M_USD
```

### Comunicação / integrações

```text
RESEND_API_KEY
RESEND_FROM_EMAIL
RESEND_WEBHOOK_SECRET
INTEGRATION_ENCRYPTION_KEY
WHATSAPP_VERIFY_TOKEN
WHATSAPP_APP_SECRET
WHATSAPP_GRAPH_VERSION
GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET
GOOGLE_MAPS_API_KEY
GOOGLE_REDIRECT_URI
OUTBOX_WORKER_SECRET
```

### API / White-label

```text
API_KEY_PEPPER
WEBHOOK_SECRET_ENCRYPTION_KEY
VERCEL_ACCESS_TOKEN
VERCEL_TEAM_ID
VERCEL_PROJECT_ID
```

Nunca use valores fictícios em produção apenas para fazer o build passar.

## 4. Auth

No Supabase Auth:

1. configure a URL HTTPS final;
2. libere `/auth/callback`;
3. libere o fluxo de convite que retorna a `/definir-senha`;
4. valide recuperação de senha;
5. só depois execute os E2E com usuários reais.

O banco já passou no smoke sem membership e em um E2E transacional de RLS com dois tenants e multiunidade (16/16). O E2E Auth real A/B continua obrigatório para validar GoTrue/JWT/PostgREST ponta a ponta.

## 5. Administrador master

Cadastre o usuário normalmente e inclua o UUID em `public.platform_admins` através de uma operação administrativa controlada.

Não existe autoelevação de privilégio na aplicação.

## 6. Supabase Cron

O ambiente homologado possui:

```text
job: platform-temporal-automations
schedule: */5 * * * *
command: select public.run_temporal_automations(now(), 500);
```

Em outro ambiente, valide `cron.job` e `cron.job_run_details` antes de considerar gatilhos temporais operacionais.

## 7. Worker do outbox

O endpoint esperado é:

```text
POST /api/internal/outbox/process
```

Proteja-o com `OUTBOX_WORKER_SECRET`.

Valide:

- claim com `FOR UPDATE SKIP LOCKED`;
- retry;
- dead-letter;
- idempotência;
- recovery de locks;
- provider real.

## 8. Mercado Pago

Somente habilite `BILLING_PROVIDER=mercadopago` após configurar sandbox.

Webhook esperado:

```text
https://SEU_DOMINIO/api/billing/mercadopago/webhook
```

Valide autorização, renovação, `past_due`, cancelamento e replay/idempotência antes do primeiro cliente pagante.

## 9. Resend / WhatsApp / Google

Valide separadamente:

- Resend: domínio, remetente, idempotência e Webhook assinado;
- WhatsApp Cloud API: App Secret, Verify Token, número, templates e status;
- Google Calendar: OAuth, refresh token criptografado, backfill e reconexão;
- Google Maps: API key server-side e restrita.

Nenhum provider deve ser marcado como conectado só porque as variáveis existem.

## 10. Vercel — sequência recomendada

1. criar/importar o projeto;
2. configurar todas as env vars necessárias;
3. executar **Preview Deployment**;
4. inspecionar build/runtime logs;
5. executar E2E/manual no preview;
6. somente então promover para Production.

Nesta sessão, o conector Vercel retornou uma incompatibilidade de contrato na ação de deploy: a interface exposta declarou zero parâmetros enquanto o runtime exigiu `target`, `name` e `files`. Nenhum deployment foi criado por essa tentativa.

## 11. Gates obrigatórios

Com dependências instaladas:

```bash
npm install
npm run lint
npm run typecheck
npm run test
npm run build
```

Estado atual:

- migrations: **PASS**
- testes Node: **148/148 PASS**
- lint: **BLOCKED por node_modules ausente**
- typecheck oficial: **BLOCKED**
- build oficial: **BLOCKED**
- Vercel preview: **BLOCKED**

## 12. E2E

Execute:

```bash
npm run test:e2e
npm run test:e2e:units
```

Os scripts existem, mas exigem usuários/organizações/unidades reais configurados no ambiente.

O teste deve falhar se:

- Tenant A ler dados de Tenant B;
- membro restrito de Unidade A ler Unidade B;
- usuários sem membership lerem dados do tenant.

## 13. Checklist manual

Antes de produção valide pelo navegador:

- cadastro + confirmação de e-mail;
- onboarding;
- convite/definição de senha;
- reset de senha;
- trial e entitlements;
- site rascunho → preview → publicação;
- uploads;
- lead/CRM/cliente;
- orçamento/link/resposta;
- Agenda pública/interna/calendário;
- automações event-driven e temporais;
- Analytics/UTM;
- Assistente IA;
- billing;
- e-mail;
- WhatsApp;
- Google;
- API pública;
- Webhooks outbound;
- White-label/domínio;
- multiunidade;
- painel master.

## 14. Produção

Só classifique o produto como **Pronto para lançamento** quando:

- `npm run check`/build estiver verde;
- E2E Auth/multiunidade estiver verde;
- providers críticos estiverem validados;
- preview estiver aprovado;
- deploy for reproduzível;
- `docs/LAUNCH_CHECKLIST.md` não tiver gates críticos pendentes.
