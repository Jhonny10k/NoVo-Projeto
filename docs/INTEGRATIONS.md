# Integrações — Fase 3 inicial

Esta documentação cobre somente integrações já implementadas em código. Uma integração só deve ser tratada como operacional depois de configurada e validada no provider real.

## 1. E-mail transacional — Resend

Variáveis server-side:

```env
RESEND_API_KEY=
RESEND_FROM_EMAIL=
RESEND_FROM_NAME=
```

Requisitos externos:
1. criar a conta/projeto no Resend;
2. verificar o domínio/remetente usado em `RESEND_FROM_EMAIL`;
3. adicionar a API key apenas no ambiente server-side;
4. abrir `/integracoes` e confirmar que o status muda de “Aguardando ambiente” para “Configurado”;
5. enviar um e-mail de teste a partir de um lead real.

O envio usa `Idempotency-Key`. O status local `sent` significa que o provider aceitou a requisição. A aplicação não chama isso de `delivered` sem confirmação posterior do provider.

## 2. WhatsApp Business Platform — Cloud API

Variáveis server-side:

```env
INTEGRATION_ENCRYPTION_KEY=
META_GRAPH_API_VERSION=
META_WHATSAPP_APP_SECRET=
META_WHATSAPP_VERIFY_TOKEN=
```

`INTEGRATION_ENCRYPTION_KEY` deve ser uma chave aleatória de 32 bytes codificada em base64. O Access Token da Meta é informado em `/integracoes`, criptografado com AES-256-GCM e persistido separadamente dos metadados que o tenant consegue consultar.

### Configuração
1. criar/configurar um app Meta com WhatsApp Business Platform;
2. obter o `Phone Number ID`, `WABA ID` e token apropriado do System User;
3. definir explicitamente a Graph API version em `META_GRAPH_API_VERSION`;
4. preencher os dados em `/integracoes`;
5. clicar **Validar com a Meta**;
6. somente depois da verificação bem-sucedida a conexão fica `active`.

### Webhook

URL:

```text
<APP_URL>/api/webhooks/whatsapp
```

O GET usa `META_WHATSAPP_VERIFY_TOKEN`. Os POSTs são rejeitados antes do parse do JSON quando `X-Hub-Signature-256` não confere com HMAC-SHA256 do payload bruto e `META_WHATSAPP_APP_SECRET`.

Mensagens recebidas são idempotentes pelo ID do provider e podem criar um lead real com origem `whatsapp` quando o telefone ainda não existe no tenant.

### Envio
- mensagem livre: só é habilitada quando houve mensagem recebida daquele contato nas últimas 24 horas;
- fora da janela: a interface exige um nome de template já aprovado na Meta;
- o sistema não cria/aprova templates em nome da empresa;
- `sent`, `delivered` e `read` são estados diferentes; entrega/leitura dependem dos Webhooks oficiais.

## 3. Scheduler das Automações temporais

As automações `lead_no_response`, `customer_inactive` e `date_specific` utilizam `public.run_temporal_automations(now(), 500)`.

Consulte `docs/SCHEDULER.md`. Em produção, configure Supabase Cron/pg_cron para executar a função em uma frequência adequada (exemplo documentado: a cada 5 minutos). Sem o job externo configurado, os gatilhos temporais ficam implementados mas não são executados periodicamente.

## 4. Checklist mínimo de homologação

- [ ] e-mail real aceito pelo Resend;
- [ ] erro do Resend fica registrado como `failed` sem falso sucesso;
- [ ] token WhatsApp nunca aparece em consultas do tenant;
- [ ] validação real do Phone Number ID passa;
- [ ] GET do Webhook Meta valida challenge;
- [ ] POST sem assinatura/assinatura inválida retorna 401;
- [ ] mensagem recebida cria/reutiliza somente lead do tenant correto;
- [ ] mensagem duplicada do provider não duplica histórico;
- [ ] janela de 24h bloqueia mensagem livre quando fechada;
- [ ] template aprovado envia fora da janela;
- [ ] Webhook atualiza `sent/delivered/read/failed` corretamente;
- [ ] Supabase Cron executa os gatilhos temporais e não duplica runs.
