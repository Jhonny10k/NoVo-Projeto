-- 2026-08-15 — Billing real: sessões de checkout, eventos idempotentes e sync de assinatura.

create table public.billing_checkout_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  billing_cycle text not null check (billing_cycle in ('monthly','annual')),
  provider text not null check (provider in ('mercadopago')),
  provider_reference text,
  payer_email text not null,
  amount_cents bigint not null check (amount_cents > 0),
  checkout_url text,
  status text not null default 'creating' check (status in ('creating','pending','authorized','canceled','failed','expired')),
  error_message text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index billing_checkout_provider_reference_uidx
  on public.billing_checkout_sessions(provider, provider_reference)
  where provider_reference is not null;

create unique index billing_checkout_one_pending_per_org_uidx
  on public.billing_checkout_sessions(organization_id)
  where status in ('creating','pending');

create index billing_checkout_org_created_idx
  on public.billing_checkout_sessions(organization_id, created_at desc);

alter table public.billing_checkout_sessions enable row level security;
create policy billing_checkout_select_member on public.billing_checkout_sessions
for select to authenticated using (public.is_org_member(organization_id));

create trigger billing_checkout_set_updated_at
before update on public.billing_checkout_sessions
for each row execute procedure public.set_updated_at();

create table public.billing_webhook_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  provider text not null,
  provider_event_id text not null,
  topic text,
  action text,
  resource_id text,
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  unique (provider, provider_event_id)
);

create index billing_webhook_created_idx on public.billing_webhook_events(created_at desc);
create index billing_webhook_resource_idx on public.billing_webhook_events(provider, resource_id);

alter table public.billing_webhook_events enable row level security;
-- Sem policies para usuários normais: payloads de provider podem conter metadados sensíveis.

alter table public.subscriptions
  add column billing_cycle text check (billing_cycle is null or billing_cycle in ('monthly','annual')),
  add column amount_cents bigint check (amount_cents is null or amount_cents > 0),
  add column provider_status text,
  add column last_provider_sync_at timestamptz;

create unique index subscriptions_provider_reference_uidx
  on public.subscriptions(provider, provider_subscription_id)
  where provider_subscription_id is not null;

-- Membros podem continuar apenas lendo. Escrita de subscriptions fica reservada ao backend secreto.

-- Admin global passa a enxergar receita recorrente ativa real (sem inventar dados).
create or replace function public.admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'metrics', jsonb_build_object(
      'organizations', (select count(*) from public.organizations),
      'active_organizations', (select count(*) from public.organizations where status = 'active'),
      'users', (select count(*) from auth.users),
      'subscriptions', (select count(*) from public.subscriptions),
      'active_subscriptions', (select count(*) from public.subscriptions where status = 'active'),
      'trials', (select count(*) from public.subscriptions where status = 'trial'),
      'mrr_cents', coalesce((
        select sum(case
          when s.billing_cycle = 'annual' then round(coalesce(s.amount_cents, p.price_annual_cents)::numeric / 12)::bigint
          else coalesce(s.amount_cents, p.price_monthly_cents)
        end)
        from public.subscriptions s
        join public.plans p on p.id = s.plan_id
        where s.status = 'active'
      ), 0)
    ),
    'organizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'name', o.name, 'slug', o.slug, 'segment', o.segment,
        'status', o.status, 'created_at', o.created_at,
        'members', (select count(*) from public.organization_members om where om.organization_id = o.id and om.status = 'active'),
        'subscription_status', (select s.status from public.subscriptions s where s.organization_id = o.id order by s.created_at desc limit 1),
        'plan_name', (select p.name from public.subscriptions s join public.plans p on p.id = s.plan_id where s.organization_id = o.id order by s.created_at desc limit 1)
      ) order by o.created_at desc)
      from (select * from public.organizations order by created_at desc limit 100) o
    ), '[]'::jsonb),
    'plans', coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'code',p.code,'name',p.name,'description',p.description,
      'price_monthly_cents',p.price_monthly_cents,'price_annual_cents',p.price_annual_cents,
      'active',p.active,'sort_order',p.sort_order
    ) order by p.sort_order) from public.plans p), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_dashboard() from public;
grant execute on function public.admin_dashboard() to authenticated;
