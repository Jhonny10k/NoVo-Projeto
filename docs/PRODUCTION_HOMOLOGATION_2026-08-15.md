# Homologação de Produção — 15/08/2026

## Estado atual

A aplicação está publicada e conectada ao Supabase real. O checkpoint desta data foi executado contra a produção pública `https://no-vo-projeto.vercel.app` e contra o projeto Supabase `kqrawaxfaahccrakqhrg`.

## Gates aprovados

- GitHub Actions CI: instalação, migrations, lint, typecheck, testes e `next build` aprovados.
- 148/148 testes automatizados aprovados.
- 37 migrations canônicas no repositório; migration `0037_foreign_key_indexes` aplicada no Supabase real.
- Production Smoke permanente aprovado.
- `/`, `/login`, `/cadastro`, `/planos`, `/api/v1/openapi.json` e `/robots.txt` respondem corretamente.
- `/planos` lê os três planos reais do Supabase: Essencial, Profissional e IA; o fallback de ambiente não configurado não aparece.
- Data API pública do Supabase validada com Publishable Key.
- GoTrue/Auth real atingido via HTTP: password grant inválido retorna `invalid_credentials`, conforme esperado.
- O formulário real de `/login` foi submetido em produção por Next Server Action e retornou `erro=credenciais`, comprovando o caminho Vercel → rate-limit → Supabase Secret Key/admin RPC → Supabase Auth.
- `/dashboard` sem sessão redireciona para `/login`.
- Headers de segurança validados: HSTS, `X-Frame-Options: DENY` e `X-Content-Type-Options: nosniff`.
- Logs do Supabase Auth confirmaram as requisições de homologação ao endpoint `/token`.
- O smoke não criou usuários de teste: consulta em `auth.users` retornou 0 usuários com padrão `e2e-%@example.com`.
- E2E transacional prévio de RLS multi-tenant/multiunidade: 16/16 verificações aprovadas, com cleanup 0.

## Performance

O Supabase Performance Advisor inicialmente reportou foreign keys sem índice de cobertura. A migration 0037 adicionou índices seguros usando `CREATE INDEX IF NOT EXISTS`, incluindo índices compostos para FKs com `organization_id, unit_id`.

Após a migration, o Advisor deixou de reportar `unindexed_foreign_keys`. Permanecem apenas avisos `unused_index` de nível INFO. Esses índices não foram removidos porque a base ainda possui pouca carga real; ausência de uso neste estágio não demonstra que sejam desnecessários.

## Segurança

Todas as tabelas públicas permanecem com RLS habilitado. O Security Advisor mantém avisos conhecidos e deliberados:

- tabelas internas deny-by-default com RLS e sem policy direta;
- RPCs públicas `SECURITY DEFINER` necessárias para site, orçamento e agendamento públicos;
- RPCs autenticadas `SECURITY DEFINER` que aplicam verificações internas de usuário, tenant, role e entitlement.

Esses avisos não foram silenciados artificialmente e devem continuar sendo revisados quando a superfície do produto mudar.

## O que este checkpoint não afirma

O teste de Auth deliberadamente não cria uma conta real nem desativa confirmação de e-mail. Portanto, embora conectividade GoTrue, login inválido, rate-limit, Secret Key e proteção de rotas estejam comprovados, um ciclo completo com **usuário confirmado real + JWT válido + onboarding no navegador** ainda requer um endereço de homologação autorizado ou SMTP próprio.

Providers externos continuam dependentes de credenciais e homologação próprias antes de habilitação comercial: Mercado Pago, Resend/SMTP, Meta WhatsApp, Google Calendar/Maps e OpenAI.

## Commits de referência

- `8bfb4ed074690a6f28c73e1af230fdfc3e145f5c` — estabilização de build/lint/types.
- `5c7abfad5425baba9c7e982cb65c63c4ebdd43ce` — smoke de Auth e runtime protegido.
- `980b30df15dd269f65279395f9c787037f4c49a3` — migration 0037 de índices de foreign keys.

## Classificação

**Infraestrutura, banco, build, produção pública e caminhos básicos de Auth estão homologados.** O produto ainda deve manter gates explícitos para providers externos e para o primeiro fluxo completo com usuário real confirmado antes de classificar todos os recursos comerciais como plenamente homologados.
