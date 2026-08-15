# Plataforma SaaS para PMEs

SaaS multi-tenant para pequenas e médias empresas brasileiras. O produto não usa métricas, integrações ou pagamentos simulados em produção.

## Stack
- Next.js + React + TypeScript + Tailwind
- Supabase Auth/PostgreSQL/RLS/Storage
- Mercado Pago Assinaturas via `BillingProvider`
- OpenAI via `AIProvider` server-side
- Resend para e-mail transacional via HTTP server-side + Webhook assinado
- WhatsApp Business Platform Cloud API via Meta
- Google Calendar OAuth + sincronização assíncrona por outbox
- Google Maps Geocoding v4 server-side
- API pública v1 + Webhooks outbound assinados
- White-label/domínios customizados via Vercel
- Multiunidade com escopo comercial por unidade
- Deploy preparado para Vercel

## Módulos já implementados em código
Auth/onboarding, multi-tenant/RBAC, planos/trial/billing/cupons, equipe, perfil/configurações, site/editor/templates, catálogo, CRM/clientes, orçamentos, tarefas, dashboard, notificações, Agenda/calendário, Automações V1, Analytics/UTM, Assistente IA, admin master, SEO, legal, contato, Automações temporais, e-mail transacional/outbox, WhatsApp oficial, Google Calendar/Maps, caixa de Atendimento, API pública/Webhooks, White-label e multiunidade.

## Desenvolvimento
```bash
npm install
cp .env.example .env.local
npm run dev
```

Aplique em ordem todas as migrations de `supabase/migrations/`.

## Gates
Os testes de invariantes desta revisão são atualizados a cada checkpoint; consulte `STATUS.md` para a contagem atual. Eles não substituem o gate completo:

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

Teste real de isolamento entre duas contas/organizações de homologação:
```bash
npm run test:e2e
```
As variáveis `E2E_*` devem apontar somente para ambiente de teste.

## Billing
Por padrão:
```env
BILLING_PROVIDER=disabled
```
Para Mercado Pago:
```env
BILLING_PROVIDER=mercadopago
MERCADO_PAGO_ACCESS_TOKEN=
MERCADO_PAGO_WEBHOOK_SECRET=
```
Webhook esperado:
```text
/api/billing/mercadopago/webhook
```
A aplicação nunca ativa assinatura apenas pelo retorno do navegador; a sincronização ocorre contra o provider/Webhook real.

## IA
A IA é opt-in por configuração e entitlement. A chave nunca vai ao cliente:
```env
AI_PROVIDER=openai
OPENAI_API_KEY=
OPENAI_MODEL=gpt-5.6
OPENAI_INPUT_PRICE_PER_1M_USD=
OPENAI_OUTPUT_PRICE_PER_1M_USD=
```
Sem `OPENAI_API_KEY`, os recursos informam indisponibilidade em vez de fabricar respostas. A aplicação registra uso e limites por tenant; prompts/respostas não são expostos no painel master.


## Comunicação
E-mail transacional usa Resend, WhatsApp usa a Cloud API da Meta e Google Calendar/Maps usam adapters server-side. Nenhum segredo vai ao navegador. E-mails automáticos e Calendar passam pelo `external_outbox` com retry/dead-letter. Consulte `docs/INTEGRATIONS.md` e `docs/SCHEDULER.md` antes de habilitar em produção.

O WhatsApp só fica `active` depois de validação real contra a Meta; mensagens livres respeitam a janela de atendimento e templates externos precisam estar aprovados no provider. Google Calendar só sincroniza quando o OAuth está ativo e o worker do outbox está agendado.

## Desenvolvedores
A API pública usa chaves opacas, escopos e quota horária. O contrato versionado está em `/api/v1/openapi.json`. Webhooks outbound usam assinatura HMAC, retry/dead-letter e reenfileiramento manual auditado. Consulte `docs/PUBLIC_API.md`.

## Segurança
- RLS como barreira no banco.
- Secret Key Supabase e chaves de providers somente server-side.
- Rate limiting persistente com identificadores em hash.
- Storage com limite/MIME e escrita por tenant.
- Ledger comercial append-only.
- Webhooks e ações críticas com idempotência/auditoria quando aplicável.

Consulte `STATUS.md`, `IMPLEMENTATION_PLAN.md` e `docs/` antes de classificar qualquer ambiente como produção.

## Integrações de automação

Zapier, Make e n8n reutilizam a API pública e Webhooks assinados existentes. Veja `docs/AUTOMATION_RECIPES.md` e `/desenvolvedores/receitas`.


## Homologação reproduzível

```bash
npm run verify:migrations
npm run homologate:local
```

Com credenciais de homologação configuradas:

```bash
npm run test:e2e:tenant
npm run test:e2e:units
```

Consulte `docs/HOMOLOGATION.md` e `FINAL_REPORT.md`. Etapas sem dependências/credenciais ficam como `blocked`, nunca como aprovadas.

## Checkpoint de homologação — 15/08/2026

- Supabase novo: `kqrawaxfaahccrakqhrg` (`sa-east-1`).
- 36 migrations canônicas aplicadas no PostgreSQL real.
- 51/51 tabelas públicas com RLS.
- Security/Performance Advisors revisados e hardening aplicado.
- E2E transacional de RLS multi-tenant/multiunidade: **16/16 verificações PASS**, sem resíduos no banco.
- Supabase Cron temporal ativo a cada 5 minutos.
- 148/148 testes locais passando.
- E2E via login real do Supabase Auth, providers externos, `npm install`, lint/typecheck/build e deploy Vercel ainda são gates pendentes.

Consulte `docs/REMOTE_HOMOLOGATION.md` e `FINAL_REPORT.md`.

## Branding

A marca exibida é configurável por `NEXT_PUBLIC_APP_NAME` e `NEXT_PUBLIC_APP_DESCRIPTION`. O nome técnico do Supabase/repositório não precisa ser a marca comercial. Consulte `docs/BRANDING.md`.

## GitHub / Vercel

O repositório deve ser a fonte de verdade. `.github/workflows/ci.yml` executa migrations, lint, typecheck, testes e build. Antes do deploy, use `npm run preflight:deploy`. O fluxo operacional está em `docs/GITHUB_VERCEL.md`.
