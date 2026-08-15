# Scheduler de Automações

Os gatilhos temporais (`lead_no_response`, `customer_inactive`, `date_specific`) são processados pela função PostgreSQL:

```sql
select public.run_temporal_automations(now(), 500);
```

## Produção — Supabase Cron

A opção recomendada é configurar **Supabase Cron** para chamar a função a cada 5 minutos. O scheduler fica dentro do banco e não depende do plano da Vercel.

No Supabase Dashboard, abra **Integrations → Cron / Jobs**, crie um job e use:

- Nome: `temporal-automations`
- Schedule: `*/5 * * * *`
- Tipo: SQL / Database function
- SQL:

```sql
select public.run_temporal_automations(now(), 500);
```

A função possui advisory lock para impedir execução concorrente e `dedupe_key` por alvo/ciclo para evitar repetir a mesma automação no mesmo período de inatividade.

## Estado da homologação

No projeto Supabase de homologação `kqrawaxfaahccrakqhrg`, o job `platform-temporal-automations` está ativo em `*/5 * * * *` e o smoke manual de `run_temporal_automations` executou sem erro. Em outro ambiente, trate os gatilhos temporais como pendentes até o job correspondente estar ativo e o histórico de execução ser conferido.
