# Arquitetura

## Frontend
Next.js App Router, React e TypeScript strict. Server Components por padrão; Client Components apenas quando necessário.

## Backend
Server Actions para mutações de painel e Route Handlers para integrações HTTP externas. Regras de negócio críticas ficam fora dos componentes visuais, em `features` e `lib`.

## Banco e Auth
Supabase PostgreSQL + Auth + RLS + Storage. O tenant raiz é `organizations`; associação via `organization_members`.

## Isolamento
Tabelas comerciais carregam `organization_id`. RLS valida membership ativo. Dados públicos são expostos por RPCs `security definer` de escopo estreito e payload controlado.

## Equipe
Convites usam a Auth Admin API somente no servidor. A criação/atualização de membership é feita por RPC reservada ao `service_role`; mutações de membros existentes passam por RPC autenticada que valida o papel do ator e protege o último `owner`.

## Billing
A camada atual possui `disabled` e `mercadopago` como providers configuráveis. Checkout e sincronização ficam em `src/lib/billing`; a interface nunca promove uma assinatura para ativa com base apenas no retorno do navegador.

Fluxo Mercado Pago:
1. validar usuário/tenant/plano e rate limit;
2. persistir `billing_checkout_sessions`;
3. criar preapproval pendente no provider;
4. redirecionar para `init_point` HTTPS validado;
5. receber Webhook assinado;
6. buscar o recurso real no provider;
7. validar referência, BRL e valor;
8. sincronizar checkout/assinatura;
9. registrar evento idempotente;
10. fan-out de notificação interna quando o status efetivamente muda.

## Storage
O bucket público `organization-assets` serve imagens do site. Publicidade do objeto não concede permissão de escrita: policies de `storage.objects` continuam isolando o caminho pelo UUID da organização e pelo papel do membro.

Uploads são limitados a 5 MB e JPG/PNG/WebP no bucket e novamente no servidor.

## Eventos e timeline
`events` é o ledger comercial. Para usuários autenticados ele é append-only: não existem policies de `UPDATE`/`DELETE`. Inserções diretas exigem que `actor_user_id` seja o próprio usuário e ficam limitadas a tipos operacionais explícitos. Eventos de sistema são escritos por RPCs `SECURITY DEFINER` ou pelo backend controlado.

As páginas de lead e cliente projetam a timeline a partir desse ledger, sempre filtrado pelo `organization_id` atual.

## Notificações
Notificações são materializadas por usuário a partir de eventos reais. Cada linha possui `user_id` e `source_event_id`; a restrição única impede duplicação de fan-out. RLS permite somente leitura da própria notificação dentro do tenant. O cliente não possui policy de update; apenas a RPC `mark_notifications_read` pode alterar `read_at`.

## Rate limiting
`rate_limit_windows` armazena contadores por janela. A RPC `consume_rate_limit` é executável somente por `service_role`. Identificadores são SHA-256 com `RATE_LIMIT_SALT`; IP/user-agent/e-mail/token não são persistidos em claro nessa tabela.

## Providers futuros
IA, mensageria e demais integrações devem permanecer desacopladas. Nenhum provider é tratado como ativo sem credencial/configuração real.

## Segurança
- chave secreta Supabase somente no servidor;
- RLS + validação server-side;
- Webhook Mercado Pago com assinatura oficial;
- ações administrativas sensíveis auditadas;
- rate limiting em superfícies públicas e billing;
- honeypot no formulário público;
- uploads com MIME/tamanho restritos;
- histórico comercial append-only para clientes autenticados;
- notificações sem edição direta pelo cliente;
- sem `DROP TABLE` nas migrations incrementais atuais.
