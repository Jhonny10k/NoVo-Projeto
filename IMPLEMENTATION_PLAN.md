# IMPLEMENTATION PLAN — Plataforma SaaS para PMEs brasileiras

## 0. Estado da auditoria inicial

### Material disponível
- `PROMPT.txt`: especificação funcional e técnica mestre.
- Nenhum repositório/código-fonte existente foi anexado nesta execução.
- Portanto, esta implementação parte de uma base **greenfield**, preservando o princípio de não inventar integrações nem dados de produção.

### Premissas obrigatórias
1. Produto real, multi-tenant e comercializável.
2. PT-BR e BRL na V1.
3. Next.js + React + TypeScript + Tailwind CSS.
4. Supabase PostgreSQL/Auth/Storage/RLS.
5. Deploy alvo: Vercel.
6. Segurança e integridade dos dados têm prioridade sobre visual.
7. Nenhuma funcionalidade falsa; integrações externas ficam desabilitadas até configuração real.
8. Toda alteração de schema ocorre por migration.

## 1. Arquitetura proposta

### Aplicação
- Next.js App Router.
- Server Components por padrão.
- Client Components somente quando interação no navegador for necessária.
- Server Actions/API Routes para mutações e integrações.
- Camadas separadas: `app` → `features` → `services` → `repositories` → `supabase`.

### Multi-tenant
- `organizations` como raiz do tenant.
- `organization_members` vincula usuário ↔ organização ↔ papel.
- Todas as entidades comerciais recebem `organization_id`.
- RLS obrigatório para tabelas com dados do tenant.
- Service Role somente no servidor e somente em operações administrativas controladas.

### Segurança
- RLS + validação server-side + RBAC.
- Rate limiting nas rotas públicas/autenticação/IA quando habilitada.
- Upload validado por MIME, extensão e tamanho.
- Logs sem secrets/tokens/senhas.
- Auditoria para ações sensíveis.

### Providers desacoplados
- `AIProvider` para IA.
- `BillingProvider` para cobrança.
- `MessagingProvider` para WhatsApp/e-mail futuro.
- Recursos externos só aparecem como ativos quando o provider estiver configurado.

## 2. Estrutura de diretórios alvo

```text
src/
  app/
    (marketing)/
    (auth)/
    (dashboard)/
    admin/
    api/
  components/
    ui/
    layout/
  features/
    auth/
    organizations/
    onboarding/
    leads/
    crm/
    customers/
    quotes/
    tasks/
    catalog/
    site-builder/
    plans/
    billing/
    admin/
  lib/
    auth/
    billing/
    ai/
    permissions/
    validation/
    security/
    supabase/
    utils/
  services/
  repositories/
  types/
supabase/
  migrations/
  seed.sql
docs/
tests/
```

## 3. Fases de implementação

### Fase 0 — Fundação técnica
**Objetivo:** projeto compilável e base segura.

- [x] Auditoria inicial do material disponível.
- [x] Criar `IMPLEMENTATION_PLAN.md`.
- [x] Scaffold Next.js/TypeScript/Tailwind.
- [x] ESLint + TypeScript strict.
- [x] `.env.example` sem segredos reais.
- [x] clientes Supabase browser/server.
- [x] proxy/proteção de rotas.
- [x] helpers de sessão e organização atual.
- [x] migrations iniciais.
- [x] documentação de arquitetura e banco.

### Fase 1 — MVP comercial obrigatório
**Objetivo:** primeiro fluxo comercial completo.

#### 1A. Auth + Organizações + Onboarding
- [x] Cadastro.
- [x] Login/logout.
- [x] Recuperação/redefinição de senha.
- [x] Confirmação de e-mail/callback.
- [x] Criação segura de organização.
- [x] Membership do proprietário.
- [x] Onboarding inicial.
- [x] Resolução da organização atual.

#### 1B. Site público + Catálogo
- [x] `site_configs` e `site_sections`.
- [x] editor de blocos simples.
- [x] produtos/serviços/categorias.
- [x] preview desktop/tablet/mobile.
- [x] publicação explícita.
- [x] rota pública por slug.
- [x] SEO básico e Schema.org.

#### 1C. Leads + CRM + Clientes
- [x] Formulário público gera lead real.
- [x] deduplicação básica segura por telefone/e-mail.
- [x] Kanban/funil e lista.
- [x] stages customizáveis (renomear/reordenar sem quebrar chaves internas).
- [x] timeline de eventos.
- [x] conversão de lead em cliente.

#### 1D. Orçamentos
- [x] criação com itens.
- [x] cálculo monetário seguro.
- [x] link público com token seguro.
- [x] aceitar/recusar/solicitar alteração.
- [x] registro de data/hora e histórico.
- [x] impressão profissional e saída PDF via impressão nativa do navegador.

#### 1E. Tarefas + Dashboard “Hoje”
- [x] tarefas e prioridades.
- [x] follow-ups com timezone da organização e registro na timeline.
- [x] métricas apenas de dados reais.
- [x] comparação de períodos.
- [x] quick actions iniciais.

#### 1F. Planos + Billing + Admin
- [x] planos vindos do banco.
- [x] feature entitlements no backend + RLS/RPCs.
- [x] trial configurável.
- [x] adapter/camada `BillingProvider` (`disabled`/Mercado Pago).
- [x] receptor de Webhook assinado e persistência idempotente.
- [x] `/admin` protegido.
- [x] empresas/assinaturas/MRR e consumo agregado de IA no painel master.
- [x] cupons com validação no checkout e resgate após autorização real.

### Fase 2 — Operação avançada
- [x] Agendamentos internos e públicos com disponibilidade/conflito/timezone.
- [x] calendário diário, semanal e mensal.
- [x] motor de automações V1 orientado a eventos: gatilho → condição → ação.
- [x] logs, idempotência, dry-run e testes de automações.
- [x] Assistente IA via `AIProvider` desacoplado e provider OpenAI server-side.
- [x] controle de consumo, tokens, limites e custo estimado de IA.
- [x] analytics avançado, visitas pseudonimizadas, funil e UTM.
- [x] templates iniciais para Oficina, Agrícola, Loja, Restaurante e Serviços.

### Fase 3 — Integrações e expansão
- [x] WhatsApp Business Platform Cloud API com Webhook assinado e segredo criptografado.
- [x] Mercado Pago recorrente; Stripe permanece opcional para decisão comercial futura.
- [x] Google Calendar via OAuth/outbox e Google Maps Geocoding server-side.
- [x] e-mail transacional Resend, Webhook assinado e outbox/retry.
- [x] outbox genérico para efeitos externos sem HTTP dentro do trigger transacional.
- [ ] API pública com autenticação/quotas.
- [ ] webhooks para clientes com assinatura, retry e idempotência.
- [ ] white-label e recursos empresariais.

## 4. Banco de dados inicial

### Núcleo
- `profiles`
- `organizations`
- `organization_members`
- `plans`
- `subscriptions`
- `categories`
- `products`
- `services`
- `leads`
- `customers`
- `pipelines`
- `pipeline_stages`
- `opportunities`
- `quotes`
- `quote_items`
- `tasks`
- `events`
- `site_configs`
- `site_sections`
- `audit_logs`

### Expansões já implementadas
- `appointments`
- `booking_settings`
- `automations`
- `automation_runs`
- `notifications`
- `ai_usage`
- `site_visits`
- `coupons`
- `coupon_redemptions`

### Futuras
- `domains` (gestão avançada)
- `integrations` (providers de Fase 3)

## 5. RLS e RBAC

### Papéis
- `owner`
- `admin`
- `sales`
- `support`
- `viewer`

### Regra base
Usuário só pode consultar ou alterar registros quando existe membership ativo para o `organization_id` correspondente e seu papel permite a ação.

### Teste obrigatório
Usuário da Organização A acessando um ID da Organização B deve receber `403/404` e nenhum dado.

## 6. Contratos de provider

### AIProvider
```ts
export interface AIProvider {
  suggestReply(input: SuggestReplyInput): Promise<SuggestReplyOutput>;
  generateBusinessCopy(input: BusinessCopyInput): Promise<BusinessCopyOutput>;
  analyzeLead(input: AnalyzeLeadInput): Promise<AnalyzeLeadOutput>;
}
```

### BillingProvider
```ts
export interface BillingProvider {
  createCheckout(input: CheckoutInput): Promise<CheckoutOutput>;
  cancelSubscription(input: CancelSubscriptionInput): Promise<void>;
  parseWebhook(input: WebhookInput): Promise<BillingEvent>;
}
```

## 7. Fluxos de aceitação do MVP

### Fluxo A — aquisição → venda
1. Usuário cria conta.
2. Conclui onboarding.
3. Empresa é criada.
4. Site é configurado e publicado.
5. Visitante acessa o site público.
6. Visitante solicita orçamento.
7. Lead aparece no CRM.
8. Empresa cria orçamento.
9. Cliente abre link público.
10. Cliente aceita.
11. Histórico é atualizado.
12. Lead pode ser convertido em cliente.

### Fluxo B — isolamento
1. Criar Organização A e B.
2. Criar usuário apenas em A.
3. Obter ID válido de entidade em B.
4. Tentar acesso pela aplicação/API.
5. Validar que nenhum dado é retornado.

### Fluxo C — plano
1. Usuário sem feature tenta usar recurso premium.
2. Backend recusa a operação.
3. UI exibe upsell coerente.
4. Após assinatura válida, entitlement é liberado.

## 8. Testes e gates

Antes de qualquer entrega marcada como pronta:

```bash
npm run lint
npm run typecheck
npm run test
npm run build
```

Além disso:
- E2E dos fluxos comerciais.
- Testes de RLS/multi-tenant.
- teste mobile.
- teste de erro/empty/loading states.
- revisão de secrets e headers.

## 9. Critério de “pronto para lançamento”

Somente quando:
- auth real funciona;
- RLS/multi-tenant foi validado;
- migrations são reproduzíveis;
- site público e formulário geram dados reais;
- CRM/orçamentos/dashboard funcionam;
- planos e proteção de features funcionam;
- billing está integrado ou explicitamente pendente de credenciais externas;
- admin está protegido;
- testes críticos e build passam;
- SEO/mobile/legal/documentação estão completos;
- deploy é reproduzível.

## 10. Pendências externas que não devem ser falsificadas
- Credenciais Supabase reais.
- domínio final da aplicação.
- provider de cobrança e chaves.
- credenciais OpenAI.
- WhatsApp Cloud API/provedor homologado: adapter inicial implementado; credenciais/validação real continuam externas.
- serviço de e-mail transacional: adapter Resend implementado; domínio/chave/validação real continuam externos.
- conteúdo jurídico revisado.

## 11. Próxima ação executável

A base funcional já ultrapassou Fases 0–3 em código. A próxima ação prioritária é **homologação real**, não expansão aleatória:
1. aplicar todas as migrations em Supabase de teste;
2. executar E2E de tenant e multiunidade;
3. validar providers externos/schedulers/webhooks;
4. instalar dependências e passar lint/typecheck/test/build oficiais;
5. corrigir falhas encontradas;
6. só então ampliar integrações/recursos secundários.

---

## Registro de execução — continuação 15/08/2026

Concluído nesta etapa:

- CRUD de produtos e serviços.
- CRM em funil com movimentação entre etapas.
- Conversão transacional de lead em cliente.
- Lista de clientes.
- Criação transacional de orçamento com múltiplos itens.
- Link público de orçamento liberado explicitamente.
- Aceite, recusa e solicitação de alteração por token.
- Tarefas com prioridade, prazo e vínculo comercial.
- Painel master `/admin` protegido por `platform_admins` no banco.
- Controle de status das organizações.
- Edição administrativa dos planos.
- Tela de assinatura sem simulação de pagamento.
- Migrations `002` e `003`.
- Testes de invariantes ampliados para 7 cenários.

Gates ainda bloqueados:

- instalação completa de dependências neste ambiente;
- lint/typecheck/build reais com Next/React/Supabase instalados;
- teste E2E contra Supabase real;
- billing com gateway real e webhooks;
- rate limiting persistente, storage/uploads e demais itens do checklist de lançamento.


---

## Registro de execução — segurança, equipe e billing 15/08/2026

Concluído nesta etapa:

- migration `004` com rate limiting persistente, gestão segura da equipe e Storage;
- convites de equipe por Auth Admin API server-side;
- proteção do último owner;
- uploads de produto/serviço com 5 MB e MIME restrito;
- rate limiting em auth, formulários públicos, resposta de orçamento e billing;
- migration `005` com checkout sessions, Webhook events idempotentes e campos de sync;
- Mercado Pago Assinaturas usando preapproval pendente + `init_point`;
- Webhook validado com `WebhookSignatureValidator`;
- assinatura local somente após estado `authorized`;
- cancelamento sincronizado com provider;
- MRR usando valor contratado persistido;
- script E2E de isolamento real para duas contas Supabase;
- testes de invariantes ampliados para 13 cenários.

Gates ainda externos/bloqueados:

- instalar dependências no ambiente atual (download expira);
- aplicar migrations em Supabase de homologação;
- executar E2E com credenciais de dois tenants;
- testar Webhooks/assinaturas em Mercado Pago sandbox/produção;
- lint/typecheck/build completos;
- deploy Vercel reproduzido.


## Registro de execução — catálogo, histórico e notificações 15/08/2026

Concluído nesta etapa:

- migration `006` com categorias consistentes, notificações por usuário e endurecimento do ledger `events`;
- CRUD de categorias e validação de `category_id` dentro do tenant;
- timeline real nas páginas de lead e cliente;
- notificações derivadas de pedido de orçamento, resposta de orçamento, conversão em cliente e mudança de assinatura;
- deduplicação de notificação por evento/usuário;
- histórico comercial append-only para usuários autenticados;
- eventos diretos presos ao ator autenticado e a uma allowlist de tipos;
- conteúdo de notificação sem `UPDATE` direto; leitura via RPC estreita;
- correção do único `TS2454` independente das dependências encontrado na varredura global;
- testes de invariantes ampliados para **19 cenários, 19/19 passando**.

Gates ainda externos/bloqueados:

- instalação de `node_modules` no ambiente atual (download expira);
- `npm run lint`, `npm run typecheck` e `npm run build` reais;
- migrations aplicadas em Supabase de homologação;
- E2E com duas contas/tenants reais;
- entrega de Webhooks e ciclo completo de assinatura validados no Mercado Pago;
- deploy Vercel reproduzido.


## 12. Registro de execução — fechamento do MVP (15/08/2026)

Concluído nesta revisão:

- entitlements por plano validados no backend e no PostgreSQL;
- trial Profissional configurável;
- recuperação/redefinição de senha;
- editor do site por blocos, rascunho separado do snapshot publicado e preview desktop/tablet/mobile;
- exportações CSV protegidas por plano e neutralização de fórmulas;
- SEO dinâmico, canonical, OpenGraph, JSON-LD e sitemap de empresas publicadas;
- páginas de termos, privacidade e contato comercial persistido;
- dashboard “Hoje” com timezone, comparação mensal e indicadores reais;
- etapas de CRM renomeáveis/reordenáveis;
- follow-up de lead com data/hora local convertida no banco e evento de timeline.

Gates ainda obrigatórios antes de produção:

- aplicar as 9 migrations em Supabase de homologação;
- executar E2E multi-tenant real;
- validar ciclo completo de assinatura Mercado Pago em sandbox;
- instalar dependências e executar lint/typecheck/build reais;
- reproduzir deploy Vercel;
- revisão jurídica das páginas legais.


## Checkpoint — 15/08/2026 — Fase 3 integrações

Implementado após a Fase 2:
- gatilhos temporais `lead_no_response`, `customer_inactive` e `date_specific`, com worker privado e idempotente;
- Resend server-side para mensagens manuais e `external_outbox` para e-mails automáticos de sistema;
- Webhook Resend assinado sobre corpo bruto, deduplicado e com estados de entrega/falha sem falso sucesso;
- WhatsApp Business Platform Cloud API com segredo criptografado, validação real, HMAC de Webhook, inbound/status e regra de janela/template;
- Google Calendar via OAuth com refresh token criptografado, Event ID determinístico, sync por outbox e backfill de appointments futuros;
- Google Maps Geocoding v4 somente no servidor, persistindo apenas localização validada;
- worker do outbox com `FOR UPDATE SKIP LOCKED`, stale-lock recovery, retry exponencial e `dead_letter`;
- caixa `/atendimento` e biblioteca de mensagens editáveis;
- documentação separando Cron das automações temporais do scheduler do outbox.

Decisão arquitetural: triggers transacionais nunca fazem HTTP externo. Efeitos externos usam fila/outbox + worker com retry e idempotência.

Gates ainda obrigatórios: aplicar as 22 migrations em homologação, configurar Supabase Cron/outbox worker, Resend/Meta/Google reais, executar E2E, instalar dependências e passar lint/typecheck/build oficiais.

## Checkpoint — 15/08/2026 — Fase 3: API, Webhooks, White-label e Multiunidade

Implementado neste checkpoint:
- API pública v1 com chaves opacas, HMAC+pepper, escopos e quota horária atômica;
- rotas para leitura/criação controlada de leads, clientes e orçamentos;
- contrato OpenAPI 3.1 versionado em `/api/v1/openapi.json`;
- observabilidade segura de requisições sem body, Authorization, IP ou segredo;
- Webhooks outbound assinados, SSRF guard, retry/dead-letter e retry manual auditado;
- White-label com branding e domínio customizado verificado pela Vercel;
- multiunidade com associação explícita de membros e escopo comercial compatível com registros legados;
- guards adicionais para notificações/outbox por unidade;
- suíte em 121/121 testes de invariantes.

Próxima prioridade:
1. aplicar migrations e executar homologação real;
2. corrigir qualquer divergência de RLS/providers descoberta no ambiente real;
3. só depois ampliar API/integrações adicionais;
4. manter Zapier/Make/n8n sobre API/Webhooks genéricos sempre que possível, evitando adapters duplicados sem necessidade.

## Checkpoint — 15/08/2026 — Observabilidade master e receitas de integração

Concluído neste checkpoint:
- migration `030` com resumo agregado de API, Webhooks e outbox protegido por `platform_admins`;
- painel `/admin` com volume, erros, dead letters, rotas e providers sem payloads/credenciais;
- página `/desenvolvedores/receitas` com Zapier, Make e n8n sobre API/Webhooks genéricos;
- `docs/AUTOMATION_RECIPES.md` com HMAC, idempotência, quota e roteiro de homologação;
- suíte ampliada para 124/124 testes de invariantes.

Decisão: continuar evitando adapters duplicados enquanto API/Webhooks genéricos cobrem a integração. A prioridade permanece homologação real das 30 migrations e gates de produção.
