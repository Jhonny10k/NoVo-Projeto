# GitHub + Vercel — publicação e deploy

## Objetivo

O repositório GitHub deve ser a fonte de verdade do código. A Vercel deve importar o repositório e gerar Preview antes de qualquer promoção para produção.

## Branding

A marca comercial não depende do nome do repositório nem do projeto Supabase.

- `NEXT_PUBLIC_APP_NAME`: marca exibida ao cliente.
- `NEXT_PUBLIC_APP_DESCRIPTION`: descrição pública padrão.
- O nome histórico `OrçaZap` pode permanecer apenas como identificação técnica da homologação Supabase até uma eventual renomeação administrativa.

## GitHub

O workflow `.github/workflows/ci.yml` executa, nesta ordem:

1. instalação de dependências;
2. verificação da cadeia de migrations;
3. lint;
4. typecheck;
5. testes;
6. build.

Nenhum segredo real deve ser commitado. Segredos de E2E ou providers devem ser adicionados em GitHub Actions Secrets somente quando esses jobs forem habilitados.

## Vercel

Criar primeiro um Preview importando o repositório GitHub. Configurar as variáveis abaixo no projeto Vercel antes de validar fluxos autenticados.

### Core obrigatório

- `NEXT_PUBLIC_APP_NAME`
- `NEXT_PUBLIC_APP_DESCRIPTION`
- `NEXT_PUBLIC_APP_URL`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SECRET_KEY`
- `RATE_LIMIT_SALT`
- `DEMO_MODE=false`
- `BILLING_PROVIDER=disabled` enquanto Mercado Pago não estiver homologado

### Integrações opcionais por módulo

- Mercado Pago: `MERCADO_PAGO_ACCESS_TOKEN`, `MERCADO_PAGO_WEBHOOK_SECRET`
- Resend: `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `RESEND_FROM_NAME`, `RESEND_WEBHOOK_SECRET`
- OpenAI: `OPENAI_API_KEY`, `OPENAI_MODEL`
- Outbox/segredos: `OUTBOX_WORKER_SECRET`, `INTEGRATION_ENCRYPTION_KEY`
- Meta: `META_GRAPH_API_VERSION`, `META_WHATSAPP_APP_SECRET`, `META_WHATSAPP_VERIFY_TOKEN`
- Google: `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `GOOGLE_CALENDAR_REDIRECT_URI`, `GOOGLE_MAPS_API_KEY`
- API pública: `PUBLIC_API_KEY_PEPPER`
- White-label: `VERCEL_ACCESS_TOKEN`, `VERCEL_PROJECT_ID`

## Preflight

Antes de um build/deploy:

```bash
npm run preflight:deploy
```

O comando informa somente nomes de variáveis ausentes e contagens. Ele nunca imprime valores de segredos.

## Depois do primeiro Preview

1. definir `NEXT_PUBLIC_APP_URL` com a URL do ambiente correspondente;
2. adicionar a URL de callback/redirect no Supabase Auth;
3. testar cadastro, confirmação, login, recuperação e logout;
4. executar E2E de dois tenants e multiunidade por JWT/PostgREST;
5. verificar logs do Preview;
6. somente depois promover para produção.
