# Checklist de lançamento

## Infraestrutura e segurança
- [x] Supabase **de homologação** novo criado (`kqrawaxfaahccrakqhrg`).
- [x] 36 migrations canônicas aplicadas no PostgreSQL real.
- [x] E2E transacional RLS multi-tenant/multiunidade: 16/16 PASS, cleanup sem resíduos.
- [x] 51/51 tabelas públicas com RLS habilitado.
- [x] Data API/ACL smoke testados (`anon` sem acesso direto ao tenant).
- [x] Security Advisor revisado e hardening 0033 aplicado.
- [x] Performance Advisor revisado e hardening 0034 aplicado.
- [x] Supabase Cron temporal ativo (`*/5 * * * *`).
- [ ] Supabase de **produção** configurado/promovido.
- [ ] RLS validado com duas organizações e usuários Auth reais de teste.
- [x] Histórico `events` append-only para usuários da aplicação.
- [x] Notificações individuais protegidas por usuário/tenant e sem update direto.
- [ ] `npm run test:e2e` passa em homologação.
- [ ] Secret Key Supabase existe apenas no servidor.
- [ ] `RATE_LIMIT_SALT` configurado.
- [ ] Rate limiting testado em auth, formulário, orçamento público e checkout.
- [ ] Uploads rejeitam arquivo >5 MB e MIME não permitido.
- [ ] Admin master protegido e sem autoelevação.

## Produto
- [ ] Auth, confirmação de e-mail e recuperação de senha funcionando em homologação.
- [x] Fluxo de recuperação/redefinição implementado com rate limit.
- [ ] Convite de equipe e definição de senha funcionando.
- [ ] Site público publicável pelo painel em homologação.
- [x] Rascunho, snapshot publicado, blocos e preview por dispositivo implementados.
- [ ] Formulário gera lead real.
- [ ] CRM e conversão em cliente funcionam.
- [ ] Orçamento e resposta pública funcionam.
- [ ] Tarefas funcionam.
- [ ] Dashboard validado com dados reais de homologação.
- [x] Consultas de dashboard, comparação de períodos e timezone implementados no banco.
- [x] Entitlements/trial protegidos no backend e no banco.
- [x] Exportação CSV protegida por entitlement e neutralização de fórmulas.
- [x] SEO dinâmico, JSON-LD, robots e sitemap implementados.

## Billing
- [ ] Mercado Pago configurado em ambiente de teste.
- [ ] Checkout pendente abre `init_point` real.
- [ ] Retorno pelo navegador não ativa assinatura sozinho.
- [ ] Webhook com assinatura válida é aceito.
- [ ] Webhook com assinatura inválida recebe 401.
- [ ] Evento duplicado não duplica processamento.
- [ ] Estado `authorized` ativa a assinatura local.
- [ ] Cancelamento no provider reflete localmente.
- [ ] Cenários de cobrança rejeitada/atrasada foram validados.
- [ ] MRR confere com os valores contratados.

## Conteúdo/comercial
- [ ] Termos e privacidade revisados juridicamente.
- [ ] Planos/preços/trial conferidos.
- [ ] FAQ e suporte revisados.
- [ ] SEO, robots e sitemap revisados.
- [ ] Mobile testado.

## Engenharia
- [ ] `npm run lint` passa.
- [ ] `npm run typecheck` passa.
- [x] `npm test` passa (**148/148** nesta revisão).
- [ ] `npm run build` passa.
- [ ] CI passa.
- [ ] Preview Vercel builda e executa sem erro.
- [ ] Deploy Vercel de produção reproduzível.
- [ ] Logs de erro e Webhooks inspecionados em homologação.


## Homologação remota

- [x] PostgreSQL real revelou e permitiu corrigir os 3 defeitos de migration encontrados durante rollout.
- [x] `anon` lê somente superfícies públicas deliberadas.
- [x] usuário `authenticated` sem membership vê 0 organizações.
- [x] workers `service_*` não são executáveis por `anon`.
- [x] smoke manual de `run_temporal_automations` executado sem erro.
- [ ] E2E Auth tenant A/B.
- [ ] E2E Auth multiunidade via tokens reais (o equivalente transacional no banco já passou).
- [ ] Definir qual plano/tier comercial habilita `multi_unit` (os 3 planos ativos atuais mantêm o entitlement desligado por padrão).
- [ ] Providers externos testados fim a fim.
