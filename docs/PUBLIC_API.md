# API pública e Webhooks para clientes

Este documento descreve a superfície de integração servidor-servidor implementada na V1. API e Webhooks são recursos controlados por entitlement/limites do plano; não ficam automaticamente habilitados para todas as organizações.

## 1. API pública v1

Contrato OpenAPI:

```text
GET /api/v1/openapi.json
```

A versão atual do contrato é `1.0.0` e cobre somente endpoints realmente implementados.

### Autenticação

Crie a chave em `/desenvolvedores`. O valor completo é mostrado uma única vez.

```http
Authorization: Bearer nd_live_...
```

A chave é opaca. O banco persiste somente HMAC-SHA256 com `PUBLIC_API_KEY_PEPPER` e um prefixo não secreto para identificação operacional.

### Escopos

| Escopo | Uso |
|---|---|
| `leads:read` | listar leads |
| `leads:write` | criar leads |
| `customers:read` | listar clientes |
| `quotes:read` | listar orçamentos |

Use o menor conjunto de escopos possível.

### Endpoints

```text
GET  /api/v1/leads
POST /api/v1/leads
GET  /api/v1/customers
GET  /api/v1/quotes
```

Consultas são sempre vinculadas ao `organization_id` derivado da chave autenticada; o cliente da API não informa um tenant arbitrário.

### Paginação e filtros

- `GET /api/v1/leads?limit=50&after=<ISO-8601>`
- `GET /api/v1/customers?limit=50&after=<ISO-8601>`
- `GET /api/v1/quotes?limit=50&status=approved`
- `limit`: mínimo 1, máximo 100.

### Quota

A quota é consumida atomicamente no PostgreSQL por chave/janela horária e vem de `plans.limits.api_requests_per_hour`.

Respostas autenticadas incluem:

```text
X-Request-Id
X-RateLimit-Limit
X-RateLimit-Remaining
X-RateLimit-Reset
```

### Logs operacionais

Owner/admin podem ver em `/desenvolvedores` as últimas requisições com:

- data;
- prefixo da chave;
- método;
- rota;
- escopo;
- status HTTP;
- duração;
- request ID.

Esse log não expõe corpo da requisição/resposta, `Authorization`, IP, chave completa ou segredo.

## 2. Webhooks outbound

Endpoints são configurados em `/desenvolvedores`. A URL precisa ser HTTPS pública e destinos locais/faixas privadas são bloqueados antes do envio.

O segredo é criado como `whsec_...`, criptografado no servidor e mostrado uma única vez.

### Headers

```text
X-ND-Event: lead_created
X-ND-Delivery: <uuid>
X-ND-Timestamp: <unix_seconds>
X-ND-Signature: v1=<hex_hmac_sha256>
Idempotency-Key: <delivery_uuid>
```

Verificação:

```text
expected = HMAC_SHA256(signing_secret, timestamp + "." + raw_body)
```

O consumidor deve validar timestamp e assinatura antes de processar o JSON, além de tratar `X-ND-Delivery`/`Idempotency-Key` de forma idempotente.

### Eventos disponíveis

- `lead_created`
- `lead_stage_changed`
- `lead_converted_to_customer`
- `quote_created`
- `quote_viewed`
- `quote_response`
- `appointment_created`
- `appointment_status_changed`
- `site_published`
- `subscription_status_changed`

### Retry

Entregas usam o mesmo `external_outbox` das integrações externas:

- retry exponencial;
- limite de tentativas;
- `dead_letter` após falha definitiva;
- deduplicação por endpoint + evento.

Owner/admin podem reenfileirar manualmente uma entrega `failed`. O retry manual reutiliza o mesmo registro de entrega/outbox e é auditado; não cria uma segunda entrega paralela.

## 3. Homologação mínima

- [ ] criar uma API key de teste e guardar o segredo fora do código-fonte;
- [ ] confirmar que chave sem escopo recebe `403`;
- [ ] confirmar que quota excedida recebe `429`;
- [ ] provar que a chave de uma organização nunca lê dados de outra;
- [ ] importar `/api/v1/openapi.json` em um cliente OpenAPI;
- [ ] configurar endpoint HTTPS de homologação;
- [ ] validar HMAC usando o corpo bruto;
- [ ] responder `2xx` e confirmar `delivered`;
- [ ] simular falha até `dead_letter` e validar reenfileiramento manual;
- [ ] confirmar que segredos completos não reaparecem no painel/logs.
