# Receitas de integração — Zapier, Make e n8n

A aplicação não cria adapters exclusivos para cada plataforma. Zapier, Make, n8n e ferramentas equivalentes devem consumir a **API pública v1** e os **Webhooks outbound** documentados em `docs/PUBLIC_API.md`.

Isso evita três mecanismos paralelos de autenticação/retry e mantém uma única regra de segurança, quota, assinatura e idempotência.

## 1. Zapier — receber novo lead

1. Crie um `Catch Hook` no Zapier.
2. Em `/desenvolvedores`, cadastre a URL HTTPS do hook.
3. Selecione apenas `lead_created`.
4. Guarde o signing secret fora de campos públicos.
5. Quando houver suporte a código/validação no fluxo, valide:

```text
HMAC_SHA256(secret, timestamp + "." + raw_body)
```

6. Use `X-ND-Delivery` como identificador idempotente.
7. Só depois execute a ação seguinte, como criar uma tarefa em outro sistema.

## 2. Make — consultar leads

Use o módulo HTTP:

```http
GET https://SEU_DOMINIO/api/v1/leads?limit=50
Authorization: Bearer nd_live_...
```

A chave deve possuir `leads:read`.

Observe:

```text
X-Request-Id
X-RateLimit-Limit
X-RateLimit-Remaining
X-RateLimit-Reset
```

Em `429`, aguarde a próxima janela em vez de fazer retry agressivo.

## 3. n8n — Webhook + consulta da API

Fluxo recomendado:

```text
Webhook inbound do n8n
→ validar timestamp/HMAC
→ verificar se X-ND-Delivery já foi processado
→ consultar entidade pela API v1 quando necessário
→ executar ação externa
→ salvar X-ND-Delivery como concluído
```

Não use o body do Webhook como autorização para consultar outro tenant. A API key sempre determina a organização acessível.

## 4. Enviar lead para a plataforma

Uma integração servidor-servidor pode usar:

```http
POST /api/v1/leads
Authorization: Bearer nd_live_...
Content-Type: application/json
```

A chave precisa de `leads:write`. Consulte `/api/v1/openapi.json` para o schema vigente.

## 5. Checklist de homologação

- [ ] criar uma API key exclusiva para homologação;
- [ ] usar somente os escopos necessários;
- [ ] validar 401/403 com chave ausente/escopo ausente;
- [ ] validar 429 e backoff pela janela de quota;
- [ ] configurar um endpoint Webhook HTTPS de teste;
- [ ] validar HMAC sobre o corpo bruto;
- [ ] provar idempotência repetindo o mesmo `X-ND-Delivery`;
- [ ] simular resposta 500 até retry/dead-letter;
- [ ] validar o retry manual depois da falha definitiva;
- [ ] confirmar que nenhum segredo aparece em logs da plataforma de automação.

## 6. O que não fazer

- não colocar segredo em query string;
- não desabilitar verificação TLS;
- não aceitar Webhook sem validar assinatura em fluxos sensíveis;
- não criar uma API key com todos os escopos para todo cenário;
- não tratar retries do Webhook como eventos novos;
- não usar endpoints em localhost/rede privada como destino de Webhook da aplicação.
