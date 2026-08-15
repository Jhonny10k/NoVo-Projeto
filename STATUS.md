# STATUS — 15/08/2026

## Situação

**MVP comercial + Fase 2 + Fase 3 avançada implementados; Supabase novo homologado estruturalmente em ambiente real. Ainda não classificado como pronto para produção.**

A base já cobre o núcleo SaaS multi-tenant, site/editor, CRM, orçamentos, Agenda, Automações, Analytics, IA, billing, comunicação oficial, Google Calendar/Maps, API pública, Webhooks outbound, White-label e multiunidade. Em 15/08/2026 foi criado um Supabase limpo (`kqrawaxfaahccrakqhrg`, região `sa-east-1`) e toda a cadeia atual foi aplicada no PostgreSQL real. RLS, ACLs, Data API, Security/Performance Advisors e Supabase Cron foram verificados. A classificação continua conservadora porque ainda faltam E2E com usuários Auth reais, providers externos, `npm install`, lint/typecheck/build oficiais e deploy Vercel reproduzido.

## Implementado

### Fundação, Auth e segurança
- Next.js App Router + React + TypeScript strict + Tailwind.
- Supabase Auth/PostgreSQL/RLS/Storage, proteção de rotas e server-only secrets.
- Cadastro, login, logout, confirmação, recuperação/redefinição de senha e onboarding.
- Multi-tenant por `organization_id`, RLS/RBAC e ledger `events` append-only.
- Rate limiting persistente com identificadores em hash.
- Uploads por tenant com limite/MIME.
- Auditoria para ações sensíveis.

### Planos, trial, billing e cupons
- Planos, preços, entitlements, limites e trial configuráveis pelo admin.
- Feature gates na interface/Server Actions e também no PostgreSQL.
- `BillingProvider` com modo disabled e Mercado Pago recorrente.
- Checkout pendente, Webhook assinado/idempotente e ativação somente após estado real do provider.
- MRR baseado no valor contratado.
- Cupons com validade/limites/plano e resgate somente após autorização real.

### Equipe, perfil, empresa e multiunidade
- `/equipe` com convite server-side e roles `owner/admin/sales/support/viewer`.
- Proteção do último owner.
- Perfil e preferências de notificação realmente aplicadas.
- Configurações comerciais/identidade/endereço/horário.
- `/unidades` com entitlement e quota por plano.
- Associação explícita de membros a unidades.
- Registros legados permanecem `unit_id = null` em escopo geral; não há migração arbitrária para filial.
- CRM, clientes, orçamentos, tarefas, Agenda, calendário, dashboard, timeline e notificações respeitam unidade acessível.
- Guards adicionais impedem fan-out de notificações/e-mails para usuário sem acesso à unidade do evento.

### Branding e CI/CD
- Marca comercial desacoplada de Supabase/repositório/migrations por `NEXT_PUBLIC_APP_NAME` e `NEXT_PUBLIC_APP_DESCRIPTION`.
- `OrçaZap` não é mais obrigatório na superfície do cliente; permanece apenas como nome histórico/técnico da homologação até definição da marca final.
- `.github/workflows/ci.yml` preparado para migrations → lint → typecheck → testes → build em Node 22.
- `npm run preflight:deploy` valida presença das variáveis essenciais sem imprimir valores de segredos.
- `docs/GITHUB_VERCEL.md` documenta importação GitHub → Preview Vercel → promoção para produção.

### Site, catálogo, templates, SEO e White-label
- Editor por blocos com rascunho separado do `published_snapshot`.
- Preview desktop/tablet/mobile e publicação explícita.
- Templates Oficina, Agrícola, Loja, Restaurante e Serviços.
- CRUD de categorias/produtos/serviços.
- SEO dinâmico, canonical, OpenGraph, Schema.org, robots e sitemap.
- White-label com branding por organização.
- Domínios customizados via API server-side da Vercel.
- Domínio só resolve publicamente quando `provider_verified=true` e o entitlement continua válido.
- Rewrite por host no `proxy.ts` para o slug verificado.

### CRM, clientes, orçamentos e tarefas
- Kanban/lista, etapas renomeáveis/reordenáveis e follow-up com timezone.
- Conversão lead → cliente transacional.
- Orçamentos com múltiplos itens e cálculo monetário no PostgreSQL.
- Link público com visualizar/aceitar/recusar/solicitar alteração.
- Layout A4 imprimível/Salvar como PDF nativo.
- Tarefas, prioridades, prazos e vínculos.
- Exportações CSV com neutralização de fórmulas.

### Dashboard, notificações e Admin master
- Dashboard “Hoje” com dados reais, comparação temporal e timezone.
- Notificações individuais por usuário e preferências.
- `/admin` protegido por `platform_admins`.
- Gestão de empresas, planos, preços, limites, entitlements e cupons.
- MRR e consumo global de IA sem expor prompts/respostas.

### Agenda, calendário e Automações
- Disponibilidade, duração, intervalo e conflito transacional.
- Agendamento interno e `/agendar/[slug]`.
- Calendário diário/semanal/mensal.
- Automações V1: gatilho → condição → ação, logs e idempotência.
- Gatilhos temporais `lead_no_response`, `customer_inactive` e `date_specific`.
- Worker temporal privado ao `service_role`, advisory lock e deduplicação por ciclo.

### Analytics/UTM e IA
- `site_visits` com fingerprint pseudonimizado; IP/user-agent brutos não são persistidos.
- UTM associada aos leads do site.
- Funil, conversão, ticket, vendas, origem, séries e itens de maior valor com dados reais.
- `AIProvider` desacoplado, Responses API server-side, `store:false`, timeout/retry e limites por tenant.
- Copiloto, geração de copy, apoio ao orçamento, insights e sugestão de resposta.
- IA não envia mensagens nem altera dados críticos automaticamente.

### Comunicação e integrações oficiais
- Resend server-side + `Idempotency-Key`.
- `external_outbox` com claim concorrente, retry exponencial, stale-lock recovery e `dead_letter`.
- E-mails automáticos enfileirados por eventos reais, sem HTTP em trigger comercial.
- Webhook Resend validado sobre corpo bruto e deduplicado.
- WhatsApp Business Platform Cloud API com token AES-256-GCM, validação real e Webhook HMAC.
- Mensagem livre respeita janela de atendimento; fora dela exige template aprovado.
- `/atendimento` centraliza histórico real de e-mail/WhatsApp.
- Google Calendar OAuth offline, refresh server-side e Event ID determinístico.
- Agenda local é fonte de verdade; create/update/cancel/backfill passam pelo outbox.
- Google Maps Geocoding v4 somente no servidor.

### API pública para integrações
- `/desenvolvedores` para chaves e Webhooks.
- Chaves opacas `nd_live_...`; banco persiste HMAC-SHA256 com `PUBLIC_API_KEY_PEPPER`, nunca o segredo bruto.
- Escopos atuais: `leads:read`, `leads:write`, `customers:read`, `quotes:read`.
- Quota horária atômica no PostgreSQL por chave/plano.
- Endpoints:
  - `GET /api/v1/leads`
  - `POST /api/v1/leads`
  - `GET /api/v1/customers`
  - `GET /api/v1/quotes`
- Contrato versionado OpenAPI 3.1 em `GET /api/v1/openapi.json`.
- Respostas autenticadas incluem request ID e cabeçalhos de quota.
- Logs operacionais seguros para owner/admin: método, rota, escopo, status, duração, request ID e prefixo da chave; sem corpo, Authorization, IP ou segredo completo.

### Observabilidade de desenvolvedores e integrações genéricas
- `/admin` mostra saúde agregada da API, Webhooks e `external_outbox` sem expor payloads, credenciais ou corpos.
- Métricas incluem requests/erros, entregas, pending/retry/processing, dead letters, rotas mais usadas e volume por provider.
- `/desenvolvedores/receitas` documenta uso com Zapier, Make e n8n sobre a mesma API/Webhooks genéricos.
- `docs/AUTOMATION_RECIPES.md` mantém exemplos de homologação, HMAC, idempotência e tratamento de quota sem criar adapters paralelos.

### Webhooks outbound para clientes
- Entitlement/limite por plano; segredo HMAC criptografado e mostrado uma vez.
- Eventos de domínio são enfileirados no mesmo `external_outbox`.
- Assinatura `HMAC_SHA256(secret, timestamp + "." + raw_body)`.
- `X-ND-Event`, `X-ND-Delivery`, `X-ND-Timestamp`, `X-ND-Signature` e `Idempotency-Key`.
- SSRF guard exige HTTPS, bloqueia localhost/faixas privadas/reservadas e IPv4-mapped IPv6 privados.
- Entrega idempotente por endpoint + evento.
- Retry automático + `dead_letter`.
- Retry manual disponível somente para entrega `failed` cujo job esteja em `dead_letter`; reutiliza o mesmo job/entrega e gera `audit_logs`.

## Testes e verificação

- **240 arquivos no projeto.**
- **135 arquivos TypeScript/TSX em `src/`.**
- **36 migrations SQL canônicas incrementais.**
- **148/148 testes locais passando.**
- E2E transacional remoto de RLS executado no PostgreSQL real: **16/16 verificações PASS** entre dois tenants, admin/membro restrito e duas unidades; cleanup confirmado com 0 resíduos.
- `npm run test:e2e:tenant` continua reservado ao fluxo via login real do Supabase Auth quando as credenciais E2E estiverem configuradas.
- `npm run test:e2e:units` continua reservado ao fluxo via tokens reais do Supabase Auth para repetir o cenário multiunidade pela Data API.
- `npm run verify:migrations` valida sequência, ausência de `DROP TABLE` e presença de RLS nos núcleos tenant.
- `npm run homologate:local` gera `HOMOLOGATION_LOCAL.json` e mantém gates indisponíveis como `blocked`.
- Varredura TypeScript global não mostrou erros focados de parser, variável antes da atribuição ou os erros estruturais TS2345/TS18047/TS18004 que já haviam sido corrigidos.
- O `tsc` global ainda produz milhares de diagnósticos de imports/JSX porque `node_modules` não está instalado; isso **não** é tratado como typecheck aprovado.

## Banco

Migrations atuais: `202608150001_initial_core.sql` até `202608150036_unit_visibility_hardening.sql`.

Nenhuma migration incremental usa `DROP TABLE`.

## Homologação Supabase real concluída

- Projeto novo: `OrçaZap` (`kqrawaxfaahccrakqhrg`), `sa-east-1`.
- **36 migrations canônicas** aplicadas; o conector registra chunks técnicos adicionais apenas para transportar migrations muito grandes.
- PostgreSQL real expôs e permitiu corrigir 3 defeitos de migration que a validação textual não detectava: buffer da Agenda, alias do Analytics e sintaxe de policy multiunidade.
- O contrato E2E multiunidade encontrou um 4º defeito de autorização: `organization_units` e `list_enterprise_units()` deixavam membro restrito ver unidades não atribuídas; corrigido na migration `0036`.
- **51/51 tabelas públicas com RLS habilitado; 0 sem RLS.**
- Data API validada: `anon` lê planos ativos, não possui `SELECT` em organizações/CRM e não executa workers internos.
- Usuário `authenticated` sem membership enxerga **0 organizações**.
- Security Advisor revisado; `anon` mantém EXECUTE somente nas RPCs públicas deliberadas.
- Performance Advisor revisado; índices essenciais de FK e policies com `(select auth.uid())` foram adicionados.
- Supabase Cron `platform-temporal-automations` ativo em `*/5 * * * *`.
- Smoke manual do worker temporal executado sem erro (`processed: 0` com base vazia).

## Ainda obrigatório antes do lançamento

- Repetir o isolamento já aprovado no banco usando **dois usuários Auth reais** em tenants diferentes, via GoTrue/PostgREST.
- Repetir o cenário de **multiunidade** com admin e membro restrito usando tokens Auth reais.
- Definir comercialmente **qual plano/tier habilitará `multi_unit`**; hoje a capability existe e é configurável por entitlement, mas os 3 planos ativos vêm com `multi_unit=false`.
- Validar cadastro/login/convite/reset/Storage e Agenda pública pelo frontend conectado ao Supabase novo.
- Validar Mercado Pago sandbox: autorização, renovação, falha/atraso, cancelamento e Webhooks.
- Validar OpenAI com chave real, limites, timeout e custos controlados.
- Configurar worker HTTP do `external_outbox` e observar retry/dead-letter em provider real.
- Configurar Resend + domínio + Webhook real.
- Configurar Meta WhatsApp Cloud API + Webhook + templates/status.
- Configurar Google Calendar OAuth/backfill e Google Maps key restrita.
- Configurar Vercel e validar domínio white-label/DNS.
- Homologar API pública e Webhooks outbound via HTTP real.
- Concluir `npm install`.
- Executar `npm run lint`, `npm run typecheck`, `npm run test` e `npm run build` com dependências instaladas.
- Publicar a base no repositório GitHub autorizado, deixar o CI verde e reproduzir Preview/produção na Vercel; o conector desta sessão ainda não enxerga a instalação do repositório e a ação direta de deploy expõe um contrato inconsistente.
- Reproduzir testes browser/mobile reais no Preview aprovado.
- Revisar Termos/Privacidade juridicamente.

## Próximos passos de código

1. ampliar a API pública somente conforme necessidades reais (novos recursos/escopos sem quebrar v1);
2. ampliar observabilidade somente quando os gates reais revelarem necessidades concretas;
3. usar as receitas Zapier/Make/n8n já documentadas sobre API/Webhooks genéricos;
4. continuar hardening de multiunidade em integrações e rotinas assíncronas quando surgirem casos reais;
5. priorizar correções que surgirem nos gates reais de Supabase/Next/Vercel antes de ampliar superfície funcional.

Consulte também `FINAL_REPORT.md`, `docs/HOMOLOGATION.md`, `docs/PUBLIC_API.md`, `docs/INTEGRATIONS.md`, `docs/SCHEDULER.md`, `docs/DATABASE.md` e `docs/LAUNCH_CHECKLIST.md`.

## GitHub / Vercel — checkpoint final

- Repositório oficial identificado: `Jhonny10k/NoVo-Projeto` (público, branch `main`).
- Checkout local inicializado e commitado em `main`: `7e37a2f feat: production-ready SaaS platform baseline`.
- O app GitHub no ChatGPT está com permissão **Allow all actions**, porém a instalação GitHub retornada pelo conector ainda está vazia; por isso operações de escrita no repositório retornam HTTP 403.
- Push Git direto também está bloqueado neste ambiente por DNS (`github.com` não resolve), então não existe credencial parcial nem upload incompleto.
- A equipe Vercel conectada é `jhonny10ks-projects`; o conector ainda retorna 0 projetos e `novo-projeto`/`NoVo-Projeto` retornam 404, apesar do projeto ter sido criado na interface segundo o usuário.
- Nenhum deployment vazio/falso foi criado.
- Próximo passo externo: a instalação GitHub precisa incluir `NoVo-Projeto`; em seguida o commit local pode ser publicado e importado/conectado ao projeto correto da Vercel.

