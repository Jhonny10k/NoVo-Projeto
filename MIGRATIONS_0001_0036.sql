-- ============================================================================
-- 202608150001_initial_core.sql
-- ============================================================================

-- 2026-08-15 — Fundação multi-tenant do MVP
-- Greenfield: nenhuma tabela é removida e toda segurança de tenant começa no banco.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  slug text not null unique check (char_length(slug) between 2 and 140),
  segment text,
  phone text,
  whatsapp text,
  email text,
  city text,
  state text check (state is null or char_length(state) = 2),
  status text not null default 'active' check (status in ('active', 'suspended', 'canceled')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'sales', 'support', 'viewer')),
  status text not null default 'active' check (status in ('active', 'invited', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  price_monthly_cents bigint not null check (price_monthly_cents >= 0),
  price_annual_cents bigint,
  features jsonb not null default '[]'::jsonb check (jsonb_typeof(features) = 'array'),
  limits jsonb not null default '{}'::jsonb check (jsonb_typeof(limits) = 'object'),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  provider text not null default 'manual',
  provider_customer_id text,
  provider_subscription_id text,
  status text not null default 'trial' check (status in ('trial', 'active', 'past_due', 'canceled', 'suspended')),
  trial_ends_at timestamptz,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  sort_order integer not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  name text not null check (char_length(name) between 1 and 160),
  description text,
  price_cents bigint check (price_cents is null or price_cents >= 0),
  promotional_price_cents bigint check (promotional_price_cents is null or promotional_price_cents >= 0),
  image_url text,
  available boolean not null default true,
  featured boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  name text not null check (char_length(name) between 1 and 160),
  description text,
  starting_price_cents bigint check (starting_price_cents is null or starting_price_cents >= 0),
  duration_minutes integer check (duration_minutes is null or duration_minutes > 0),
  image_url text,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pipelines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  is_default boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pipeline_stages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  pipeline_id uuid not null references public.pipelines(id) on delete cascade,
  name text not null,
  stage_key text not null,
  sort_order integer not null default 0,
  is_closed boolean not null default false,
  is_won boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (pipeline_id, stage_key)
);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  pipeline_id uuid references public.pipelines(id) on delete set null,
  stage_id uuid references public.pipeline_stages(id) on delete set null,
  name text not null check (char_length(name) between 2 and 160),
  phone text,
  whatsapp text,
  email text,
  company text,
  source text not null default 'manual',
  status text not null default 'new',
  responsible_user_id uuid references auth.users(id) on delete set null,
  tags text[] not null default '{}',
  notes text,
  potential_value_cents bigint check (potential_value_cents is null or potential_value_cents >= 0),
  interest text,
  last_contact_at timestamptz,
  next_contact_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_lead_id uuid references public.leads(id) on delete set null,
  name text not null,
  phone text,
  whatsapp text,
  email text,
  company text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.quote_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  description text not null check (char_length(description) between 5 and 5000),
  status text not null default 'pending' check (status in ('pending', 'reviewing', 'quoted', 'closed')),
  source text not null default 'site',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,
  public_token text not null unique default encode(gen_random_bytes(18), 'hex'),
  status text not null default 'draft' check (status in ('draft', 'sent', 'viewed', 'approved', 'rejected', 'change_requested', 'expired')),
  subtotal_cents bigint not null default 0 check (subtotal_cents >= 0),
  discount_cents bigint not null default 0 check (discount_cents >= 0),
  fee_cents bigint not null default 0 check (fee_cents >= 0),
  total_cents bigint not null default 0 check (total_cents >= 0),
  notes text,
  valid_until date,
  accepted_at timestamptz,
  rejected_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.quote_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null references public.quotes(id) on delete cascade,
  item_type text not null check (item_type in ('product', 'service', 'custom')),
  reference_id uuid,
  description text not null,
  quantity numeric(12,3) not null default 1 check (quantity > 0),
  unit_price_cents bigint not null check (unit_price_cents >= 0),
  total_cents bigint not null check (total_cents >= 0),
  created_at timestamptz not null default now()
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  title text not null,
  description text,
  assigned_to uuid references auth.users(id) on delete set null,
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  due_at timestamptz,
  status text not null default 'open' check (status in ('open', 'in_progress', 'done', 'canceled')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.site_configs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations(id) on delete cascade,
  status text not null default 'draft' check (status in ('draft', 'published', 'disabled')),
  headline text,
  subheadline text,
  about text,
  primary_color text,
  cover_image_url text,
  published_at timestamptz,
  version integer not null default 1,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.site_sections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  site_config_id uuid not null references public.site_configs(id) on delete cascade,
  section_type text not null check (section_type in ('hero', 'about', 'services', 'products', 'gallery', 'benefits', 'testimonials', 'faq', 'contact', 'location', 'cta')),
  enabled boolean not null default true,
  sort_order integer not null default 0,
  content jsonb not null default '{}'::jsonb check (jsonb_typeof(content) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Índices de tenant e consultas frequentes.
create index organization_members_user_idx on public.organization_members(user_id, status);
create index organization_members_org_idx on public.organization_members(organization_id, status);
create index products_org_idx on public.products(organization_id, available);
create index services_org_idx on public.services(organization_id, active);
create index leads_org_created_idx on public.leads(organization_id, created_at desc);
create index leads_org_phone_idx on public.leads(organization_id, phone);
create index leads_org_whatsapp_idx on public.leads(organization_id, whatsapp);
create index leads_org_email_idx on public.leads(organization_id, lower(email));
create index customers_org_idx on public.customers(organization_id, created_at desc);
create index quote_requests_org_idx on public.quote_requests(organization_id, created_at desc);
create index quotes_org_idx on public.quotes(organization_id, created_at desc);
create index tasks_org_status_idx on public.tasks(organization_id, status, due_at);
create index events_org_created_idx on public.events(organization_id, created_at desc);

create or replace function public.is_org_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

create or replace function public.has_org_role(p_organization_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role = any(p_roles)
  );
$$;

revoke all on function public.is_org_member(uuid) from public;
revoke all on function public.has_org_role(uuid, text[]) from public;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_role(uuid, text[]) to authenticated;

alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.plans enable row level security;
alter table public.subscriptions enable row level security;

create policy profiles_select_own on public.profiles
for select to authenticated using (id = auth.uid());

create policy profiles_update_own on public.profiles
for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy organizations_select_member on public.organizations
for select to authenticated using (public.is_org_member(id));

create policy organizations_update_admin on public.organizations
for update to authenticated
using (public.has_org_role(id, array['owner','admin']))
with check (public.has_org_role(id, array['owner','admin']));

create policy members_select_member on public.organization_members
for select to authenticated using (public.is_org_member(organization_id));

create policy members_insert_admin on public.organization_members
for insert to authenticated with check (public.has_org_role(organization_id, array['owner','admin']));

create policy members_update_admin on public.organization_members
for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin']))
with check (public.has_org_role(organization_id, array['owner','admin']));

create policy members_delete_admin on public.organization_members
for delete to authenticated using (public.has_org_role(organization_id, array['owner','admin']));

create policy plans_public_read on public.plans
for select to anon, authenticated using (active = true);

create policy subscriptions_select_member on public.subscriptions
for select to authenticated using (public.is_org_member(organization_id));

-- Policies uniformes para dados do tenant.
do $$
declare
  table_name text;
  tenant_tables text[] := array[
    'categories','products','services','pipelines','pipeline_stages','leads',
    'customers','quote_requests','quotes','quote_items','tasks','site_configs',
    'site_sections','events'
  ];
begin
  foreach table_name in array tenant_tables loop
    execute format('alter table public.%I enable row level security', table_name);

    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_org_member(organization_id))',
      table_name || '_select_member', table_name
    );

    execute format(
      'create policy %I on public.%I for insert to authenticated with check (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']))',
      table_name || '_insert_staff', table_name
    );

    execute format(
      'create policy %I on public.%I for update to authenticated using (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support''])) with check (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']))',
      table_name || '_update_staff', table_name
    );

    execute format(
      'create policy %I on public.%I for delete to authenticated using (public.has_org_role(organization_id, array[''owner'',''admin'']))',
      table_name || '_delete_admin', table_name
    );
  end loop;
end
$$;

alter table public.audit_logs enable row level security;

create policy audit_logs_select_admin on public.audit_logs
for select to authenticated
using (organization_id is not null and public.has_org_role(organization_id, array['owner','admin']));

-- Cria/atualiza profile ao cadastrar usuário.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, nullif(trim(coalesce(new.raw_user_meta_data->>'name', '')), ''))
  on conflict (id) do update set
    full_name = excluded.full_name,
    updated_at = now();

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.safe_slug(p_value text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(
    regexp_replace(lower(unaccent_fallback), '[^a-z0-9]+', '-', 'g'),
    '-+', '-', 'g'
  ))
  from (
    select translate(
      p_value,
      'áàãâäéèêëíìîïóòõôöúùûüçñ',
      'aaaaaeeeeiiiiooooouuuucn'
    ) as unaccent_fallback
  ) s;
$$;

create or replace function public.create_organization_with_owner(
  p_name text,
  p_segment text,
  p_phone text default null,
  p_whatsapp text default null,
  p_city text default null,
  p_state text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_pipeline_id uuid;
  v_base_slug text;
  v_slug text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if char_length(trim(p_name)) < 2 then
    raise exception 'invalid organization name';
  end if;

  v_base_slug := nullif(public.safe_slug(p_name), '');
  if v_base_slug is null then
    v_base_slug := 'empresa';
  end if;

  v_slug := v_base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);

  insert into public.organizations (
    name, slug, segment, phone, whatsapp, city, state, created_by
  ) values (
    trim(p_name),
    v_slug,
    nullif(trim(p_segment), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_whatsapp), ''),
    nullif(trim(p_city), ''),
    upper(nullif(trim(p_state), '')),
    v_user_id
  )
  returning id into v_org_id;

  insert into public.organization_members (organization_id, user_id, role, status)
  values (v_org_id, v_user_id, 'owner', 'active');

  insert into public.site_configs (
    organization_id, status, headline, subheadline, created_by
  ) values (
    v_org_id,
    'draft',
    trim(p_name),
    'Conheça nossos produtos e serviços.',
    v_user_id
  );

  insert into public.pipelines (organization_id, name, is_default, created_by)
  values (v_org_id, 'Comercial', true, v_user_id)
  returning id into v_pipeline_id;

  insert into public.pipeline_stages (
    organization_id, pipeline_id, name, stage_key, sort_order, is_closed, is_won
  ) values
    (v_org_id, v_pipeline_id, 'Novo lead', 'new', 10, false, false),
    (v_org_id, v_pipeline_id, 'Primeiro contato', 'first_contact', 20, false, false),
    (v_org_id, v_pipeline_id, 'Qualificado', 'qualified', 30, false, false),
    (v_org_id, v_pipeline_id, 'Orçamento', 'quote', 40, false, false),
    (v_org_id, v_pipeline_id, 'Negociação', 'negotiation', 50, false, false),
    (v_org_id, v_pipeline_id, 'Fechado', 'won', 60, true, true),
    (v_org_id, v_pipeline_id, 'Perdido', 'lost', 70, true, false);

  insert into public.events (
    organization_id, actor_user_id, entity_type, entity_id, event_type
  ) values (
    v_org_id, v_user_id, 'organization', v_org_id, 'organization_created'
  );

  return v_org_id;
end;
$$;

revoke all on function public.create_organization_with_owner(text,text,text,text,text,text) from public;
grant execute on function public.create_organization_with_owner(text,text,text,text,text,text) to authenticated;

create or replace function public.get_public_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org public.organizations%rowtype;
  v_site public.site_configs%rowtype;
begin
  select o.* into v_org
  from public.organizations o
  where o.slug = p_slug and o.status = 'active'
  limit 1;

  if v_org.id is null then
    return null;
  end if;

  select s.* into v_site
  from public.site_configs s
  where s.organization_id = v_org.id
    and s.status = 'published'
  limit 1;

  if v_site.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'organization', jsonb_build_object(
      'name', v_org.name,
      'slug', v_org.slug,
      'segment', v_org.segment,
      'whatsapp', v_org.whatsapp,
      'phone', v_org.phone,
      'city', v_org.city,
      'state', v_org.state
    ),
    'site', jsonb_build_object(
      'headline', v_site.headline,
      'subheadline', v_site.subheadline,
      'about', v_site.about
    ),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'description', p.description,
        'price_cents', p.price_cents
      ) order by p.featured desc, p.created_at desc)
      from public.products p
      where p.organization_id = v_org.id and p.available = true
    ), '[]'::jsonb),
    'services', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'description', s.description,
        'starting_price_cents', s.starting_price_cents
      ) order by s.created_at desc)
      from public.services s
      where s.organization_id = v_org.id and s.active = true
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_public_site(text) from public;
grant execute on function public.get_public_site(text) to anon, authenticated;

create or replace function public.public_create_quote_request(
  p_organization_slug text,
  p_name text,
  p_whatsapp text,
  p_email text,
  p_description text,
  p_honeypot text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_lead_id uuid;
  v_pipeline_id uuid;
  v_stage_id uuid;
  v_request_id uuid;
  v_whatsapp text := nullif(trim(p_whatsapp), '');
  v_email text := lower(nullif(trim(p_email), ''));
begin
  if nullif(trim(coalesce(p_honeypot, '')), '') is not null then
    raise exception 'invalid request';
  end if;

  if char_length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'invalid name';
  end if;

  if v_whatsapp is null and v_email is null then
    raise exception 'contact required';
  end if;

  if char_length(trim(coalesce(p_description, ''))) < 5
     or char_length(trim(coalesce(p_description, ''))) > 5000 then
    raise exception 'invalid description';
  end if;

  select o.id into v_org_id
  from public.organizations o
  join public.site_configs sc on sc.organization_id = o.id
  where o.slug = p_organization_slug
    and o.status = 'active'
    and sc.status = 'published'
  limit 1;

  if v_org_id is null then
    raise exception 'site unavailable';
  end if;

  select p.id into v_pipeline_id
  from public.pipelines p
  where p.organization_id = v_org_id and p.is_default = true
  order by p.created_at
  limit 1;

  select ps.id into v_stage_id
  from public.pipeline_stages ps
  where ps.pipeline_id = v_pipeline_id and ps.stage_key = 'new'
  limit 1;

  select l.id into v_lead_id
  from public.leads l
  where l.organization_id = v_org_id
    and (
      (v_whatsapp is not null and regexp_replace(coalesce(l.whatsapp, ''), '\D', '', 'g') = regexp_replace(v_whatsapp, '\D', '', 'g'))
      or
      (v_email is not null and lower(coalesce(l.email, '')) = v_email)
    )
  order by l.created_at desc
  limit 1;

  if v_lead_id is null then
    insert into public.leads (
      organization_id, pipeline_id, stage_id, name, whatsapp, email,
      source, status, interest, last_contact_at
    ) values (
      v_org_id, v_pipeline_id, v_stage_id, trim(p_name), v_whatsapp, v_email,
      'site', 'new', trim(p_description), now()
    )
    returning id into v_lead_id;
  else
    update public.leads
    set last_contact_at = now(),
        updated_at = now()
    where id = v_lead_id;
  end if;

  insert into public.quote_requests (
    organization_id, lead_id, description, status, source
  ) values (
    v_org_id, v_lead_id, trim(p_description), 'pending', 'site'
  )
  returning id into v_request_id;

  insert into public.events (
    organization_id, entity_type, entity_id, event_type, metadata
  ) values (
    v_org_id,
    'lead',
    v_lead_id,
    'quote_request_received',
    jsonb_build_object('quote_request_id', v_request_id, 'source', 'site')
  );

  return v_request_id;
end;
$$;

revoke all on function public.public_create_quote_request(text,text,text,text,text,text) from public;
grant execute on function public.public_create_quote_request(text,text,text,text,text,text) to anon, authenticated;

-- updated_at automático.
do $$
declare
  table_name text;
  trigger_tables text[] := array[
    'profiles','organizations','organization_members','plans','subscriptions',
    'categories','products','services','pipelines','pipeline_stages','leads',
    'customers','quote_requests','quotes','tasks','site_configs','site_sections'
  ];
begin
  foreach table_name in array trigger_tables loop
    execute format(
      'create trigger %I before update on public.%I for each row execute procedure public.set_updated_at()',
      table_name || '_set_updated_at', table_name
    );
  end loop;
end
$$;

-- Configuração inicial dos planos: dados do banco, editáveis pelo administrador no futuro.
insert into public.plans (
  code, name, description, price_monthly_cents, price_annual_cents, features, limits, sort_order
) values
(
  'essential',
  'Essencial',
  'Presença digital e captação de contatos.',
  3990,
  39900,
  '["Site","Página de contato","WhatsApp","Produtos e serviços","SEO básico","Painel","Formulários"]'::jsonb,
  '{"leads_per_month":100,"users":1}'::jsonb,
  10
),
(
  'professional',
  'Profissional',
  'Operação comercial com CRM e orçamentos.',
  6990,
  69900,
  '["Tudo do Essencial","CRM","Orçamentos","Analytics","Agendamento","Personalização avançada"]'::jsonb,
  '{"leads_per_month":1000,"users":5}'::jsonb,
  20
),
(
  'ai',
  'IA',
  'Recursos inteligentes com controle de consumo.',
  11990,
  119900,
  '["Tudo do Profissional","Assistente IA","Sugestão de respostas","Textos com IA","Insights"]'::jsonb,
  '{"leads_per_month":5000,"users":10,"ai_enabled":true}'::jsonb,
  30
);

-- ============================================================================
-- 202608150002_commercial_core.sql
-- ============================================================================

-- Núcleo comercial transacional: clientes, orçamentos e aceite público.

create or replace function public.convert_lead_to_customer(
  p_organization_id uuid,
  p_lead_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_lead public.leads%rowtype;
  v_customer_id uuid;
  v_won_stage_id uuid;
begin
  if v_user_id is null or not public.has_org_role(p_organization_id, array['owner','admin','sales','support']) then
    raise exception 'forbidden';
  end if;

  select * into v_lead
  from public.leads
  where id = p_lead_id and organization_id = p_organization_id
  for update;

  if v_lead.id is null then
    raise exception 'lead not found';
  end if;

  select c.id into v_customer_id
  from public.customers c
  where c.organization_id = p_organization_id and c.source_lead_id = p_lead_id
  limit 1;

  if v_customer_id is null then
    insert into public.customers (
      organization_id, source_lead_id, name, phone, whatsapp, email, company, notes, created_by
    ) values (
      p_organization_id, v_lead.id, v_lead.name, v_lead.phone, v_lead.whatsapp,
      v_lead.email, v_lead.company, v_lead.notes, v_user_id
    ) returning id into v_customer_id;
  end if;

  select ps.id into v_won_stage_id
  from public.pipeline_stages ps
  where ps.organization_id = p_organization_id
    and ps.pipeline_id = v_lead.pipeline_id
    and ps.is_won = true
  order by ps.sort_order
  limit 1;

  update public.leads
  set stage_id = coalesce(v_won_stage_id, stage_id),
      status = 'won',
      updated_at = now()
  where id = v_lead.id and organization_id = p_organization_id;

  insert into public.events (organization_id, actor_user_id, entity_type, entity_id, event_type, metadata)
  values (p_organization_id, v_user_id, 'customer', v_customer_id, 'lead_converted_to_customer', jsonb_build_object('lead_id', v_lead.id));

  return v_customer_id;
end;
$$;

revoke all on function public.convert_lead_to_customer(uuid,uuid) from public;
grant execute on function public.convert_lead_to_customer(uuid,uuid) to authenticated;

create or replace function public.create_quote_with_items(
  p_organization_id uuid,
  p_lead_id uuid default null,
  p_customer_id uuid default null,
  p_notes text default null,
  p_valid_until date default null,
  p_discount_cents bigint default 0,
  p_fee_cents bigint default 0,
  p_items jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_quote_id uuid;
  v_subtotal bigint := 0;
  v_total bigint := 0;
  v_item jsonb;
  v_description text;
  v_type text;
  v_reference_id uuid;
  v_quantity numeric(12,3);
  v_unit bigint;
  v_line bigint;
begin
  if v_user_id is null or not public.has_org_role(p_organization_id, array['owner','admin','sales','support']) then
    raise exception 'forbidden';
  end if;
  if p_discount_cents < 0 or p_fee_cents < 0 then raise exception 'invalid adjustment'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100 then
    raise exception 'items required';
  end if;
  if p_lead_id is not null and not exists(select 1 from public.leads where id = p_lead_id and organization_id = p_organization_id) then
    raise exception 'invalid lead';
  end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id = p_customer_id and organization_id = p_organization_id) then
    raise exception 'invalid customer';
  end if;

  insert into public.quotes (organization_id, customer_id, lead_id, status, notes, valid_until, discount_cents, fee_cents, created_by)
  values (p_organization_id, p_customer_id, p_lead_id, 'draft', nullif(trim(p_notes), ''), p_valid_until, p_discount_cents, p_fee_cents, v_user_id)
  returning id into v_quote_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_type := coalesce(nullif(v_item->>'item_type',''), 'custom');
    if v_type not in ('product','service','custom') then raise exception 'invalid item type'; end if;
    v_description := trim(coalesce(v_item->>'description',''));
    if char_length(v_description) < 1 or char_length(v_description) > 1000 then raise exception 'invalid item description'; end if;
    v_quantity := coalesce((v_item->>'quantity')::numeric, 1);
    v_unit := coalesce((v_item->>'unit_price_cents')::bigint, 0);
    if v_quantity <= 0 or v_quantity > 999999 or v_unit < 0 then raise exception 'invalid item amount'; end if;
    v_line := round(v_quantity * v_unit)::bigint;
    v_subtotal := v_subtotal + v_line;
    begin
      v_reference_id := nullif(v_item->>'reference_id','')::uuid;
    exception when invalid_text_representation then
      v_reference_id := null;
    end;

    insert into public.quote_items (organization_id, quote_id, item_type, reference_id, description, quantity, unit_price_cents, total_cents)
    values (p_organization_id, v_quote_id, v_type, v_reference_id, v_description, v_quantity, v_unit, v_line);
  end loop;

  v_total := greatest(0, v_subtotal - p_discount_cents + p_fee_cents);
  update public.quotes set subtotal_cents = v_subtotal, total_cents = v_total where id = v_quote_id;

  insert into public.events (organization_id, actor_user_id, entity_type, entity_id, event_type)
  values (p_organization_id, v_user_id, 'quote', v_quote_id, 'quote_created');

  return v_quote_id;
end;
$$;

revoke all on function public.create_quote_with_items(uuid,uuid,uuid,text,date,bigint,bigint,jsonb) from public;
grant execute on function public.create_quote_with_items(uuid,uuid,uuid,text,date,bigint,bigint,jsonb) to authenticated;

create or replace function public.publish_quote_link(p_organization_id uuid, p_quote_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_token text;
begin
  if v_user_id is null or not public.has_org_role(p_organization_id, array['owner','admin','sales','support']) then
    raise exception 'forbidden';
  end if;
  update public.quotes q
  set status = case when q.status = 'draft' then 'sent' else q.status end,
      updated_at = now()
  where q.id = p_quote_id and q.organization_id = p_organization_id
    and q.status in ('draft','sent','viewed','change_requested')
  returning q.public_token into v_token;
  if v_token is null then raise exception 'quote unavailable'; end if;
  insert into public.events (organization_id, actor_user_id, entity_type, entity_id, event_type)
  values (p_organization_id, v_user_id, 'quote', p_quote_id, 'quote_link_enabled');
  return v_token;
end;
$$;
revoke all on function public.publish_quote_link(uuid,uuid) from public;
grant execute on function public.publish_quote_link(uuid,uuid) to authenticated;

create or replace function public.get_public_quote(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote public.quotes%rowtype;
  v_org public.organizations%rowtype;
  v_name text;
  v_whatsapp text;
  v_email text;
begin
  select * into v_quote from public.quotes where public_token = p_token limit 1;
  if v_quote.id is null or v_quote.status = 'draft' then return null; end if;
  if v_quote.valid_until is not null and v_quote.valid_until < current_date and v_quote.status not in ('approved','rejected') then
    update public.quotes set status = 'expired' where id = v_quote.id;
    v_quote.status := 'expired';
  elsif v_quote.status = 'sent' then
    update public.quotes set status = 'viewed' where id = v_quote.id;
    v_quote.status := 'viewed';
    insert into public.events (organization_id, entity_type, entity_id, event_type) values (v_quote.organization_id, 'quote', v_quote.id, 'quote_viewed');
  end if;

  select * into v_org from public.organizations where id = v_quote.organization_id and status = 'active';
  if v_org.id is null then return null; end if;

  if v_quote.customer_id is not null then
    select name, whatsapp, email into v_name, v_whatsapp, v_email from public.customers where id = v_quote.customer_id;
  elsif v_quote.lead_id is not null then
    select name, whatsapp, email into v_name, v_whatsapp, v_email from public.leads where id = v_quote.lead_id;
  end if;

  return jsonb_build_object(
    'quote', jsonb_build_object('id',v_quote.id,'status',v_quote.status,'subtotal_cents',v_quote.subtotal_cents,'discount_cents',v_quote.discount_cents,'fee_cents',v_quote.fee_cents,'total_cents',v_quote.total_cents,'notes',v_quote.notes,'valid_until',v_quote.valid_until,'created_at',v_quote.created_at),
    'organization', jsonb_build_object('name',v_org.name,'phone',v_org.phone,'whatsapp',v_org.whatsapp,'email',v_org.email,'city',v_org.city,'state',v_org.state),
    'customer', jsonb_build_object('name',coalesce(v_name,'Cliente'),'whatsapp',v_whatsapp,'email',v_email),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id',qi.id,'description',qi.description,'quantity',qi.quantity,'unit_price_cents',qi.unit_price_cents,'total_cents',qi.total_cents) order by qi.created_at) from public.quote_items qi where qi.quote_id = v_quote.id), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_public_quote(text) from public;
grant execute on function public.get_public_quote(text) to anon, authenticated;

create or replace function public.respond_public_quote(p_token text, p_response text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote_id uuid;
  v_org_id uuid;
  v_status text;
begin
  if p_response not in ('approved','rejected','change_requested') then raise exception 'invalid response'; end if;
  update public.quotes
  set status = p_response,
      accepted_at = case when p_response = 'approved' then now() else accepted_at end,
      rejected_at = case when p_response = 'rejected' then now() else rejected_at end,
      updated_at = now()
  where public_token = p_token
    and status in ('sent','viewed','change_requested')
    and (valid_until is null or valid_until >= current_date)
  returning id, organization_id, status into v_quote_id, v_org_id, v_status;
  if v_quote_id is null then raise exception 'quote unavailable'; end if;
  insert into public.events (organization_id, entity_type, entity_id, event_type, metadata)
  values (v_org_id, 'quote', v_quote_id, 'quote_response', jsonb_build_object('status',v_status));
  return v_status;
end;
$$;
revoke all on function public.respond_public_quote(text,text) from public;
grant execute on function public.respond_public_quote(text,text) to anon, authenticated;

-- Unicidade segura da conversão lead -> cliente dentro da organização.
create unique index if not exists customers_org_source_lead_unique
on public.customers(organization_id, source_lead_id)
where source_lead_id is not null;

-- ============================================================================
-- 202608150003_platform_admin.sql
-- ============================================================================

-- Administração master isolada dos tenants.
create table public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;
create policy platform_admins_select_self on public.platform_admins
for select to authenticated using (user_id = auth.uid());

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.platform_admins pa where pa.user_id = auth.uid());
$$;
revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;

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
      'trials', (select count(*) from public.subscriptions where status = 'trial')
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

create or replace function public.admin_set_organization_status(p_organization_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'forbidden'; end if;
  if p_status not in ('active','suspended','canceled') then raise exception 'invalid status'; end if;
  update public.organizations set status = p_status, updated_at = now() where id = p_organization_id;
  if not found then raise exception 'organization not found'; end if;
  insert into public.audit_logs (organization_id, actor_user_id, action, entity_type, entity_id, metadata)
  values (p_organization_id, auth.uid(), 'platform.organization_status_changed', 'organization', p_organization_id, jsonb_build_object('status',p_status));
end;
$$;
revoke all on function public.admin_set_organization_status(uuid,text) from public;
grant execute on function public.admin_set_organization_status(uuid,text) to authenticated;

create or replace function public.admin_update_plan(
  p_plan_id uuid,
  p_name text,
  p_description text,
  p_price_monthly_cents bigint,
  p_price_annual_cents bigint,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'forbidden'; end if;
  if char_length(trim(p_name)) < 2 or p_price_monthly_cents < 0 or p_price_annual_cents < 0 then raise exception 'invalid plan'; end if;
  update public.plans
  set name = trim(p_name), description = nullif(trim(p_description), ''), price_monthly_cents = p_price_monthly_cents,
      price_annual_cents = p_price_annual_cents, active = p_active, updated_at = now()
  where id = p_plan_id;
  if not found then raise exception 'plan not found'; end if;
  insert into public.audit_logs (actor_user_id, action, entity_type, entity_id)
  values (auth.uid(), 'platform.plan_updated', 'plan', p_plan_id);
end;
$$;
revoke all on function public.admin_update_plan(uuid,text,text,bigint,bigint,boolean) from public;
grant execute on function public.admin_update_plan(uuid,text,text,bigint,bigint,boolean) to authenticated;

-- ============================================================================
-- 202608150004_security_team_storage.sql
-- ============================================================================

-- 2026-08-15 — Segurança operacional: rate limit persistente, equipe e Storage.
-- Migration incremental: não remove tabelas nem dados de negócio existentes.

-- ---------------------------------------------------------------------------
-- Rate limiting persistente (acesso somente via chave secreta/service_role).
-- ---------------------------------------------------------------------------
create table public.rate_limit_windows (
  scope text not null,
  identifier_hash text not null,
  window_start timestamptz not null,
  window_seconds integer not null check (window_seconds between 1 and 86400),
  hit_count integer not null default 0 check (hit_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (scope, identifier_hash, window_start)
);

alter table public.rate_limit_windows enable row level security;

create index rate_limit_windows_updated_idx
  on public.rate_limit_windows(updated_at);

create or replace function public.consume_rate_limit(
  p_scope text,
  p_identifier_hash text,
  p_limit integer,
  p_window_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window_start timestamptz;
  v_count integer;
begin
  if char_length(trim(coalesce(p_scope, ''))) < 2
     or char_length(trim(coalesce(p_identifier_hash, ''))) < 16
     or p_limit < 1
     or p_limit > 10000
     or p_window_seconds < 1
     or p_window_seconds > 86400 then
    raise exception 'invalid rate limit configuration';
  end if;

  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  insert into public.rate_limit_windows (
    scope, identifier_hash, window_start, window_seconds, hit_count, updated_at
  ) values (
    trim(p_scope), trim(p_identifier_hash), v_window_start, p_window_seconds, 1, now()
  )
  on conflict (scope, identifier_hash, window_start)
  do update set
    hit_count = public.rate_limit_windows.hit_count + 1,
    updated_at = now()
  returning hit_count into v_count;

  -- Mantém a tabela pequena sem depender de um job externo nesta fase.
  delete from public.rate_limit_windows
  where updated_at < now() - interval '2 days';

  return jsonb_build_object(
    'allowed', v_count <= p_limit,
    'count', v_count,
    'limit', p_limit,
    'reset_at', v_window_start + make_interval(secs => p_window_seconds)
  );
end;
$$;

revoke all on function public.consume_rate_limit(text,text,integer,integer) from public;
revoke all on function public.consume_rate_limit(text,text,integer,integer) from anon;
revoke all on function public.consume_rate_limit(text,text,integer,integer) from authenticated;
grant execute on function public.consume_rate_limit(text,text,integer,integer) to service_role;

-- ---------------------------------------------------------------------------
-- Gestão segura de membros.
-- A tabela continua legível pelos membros do tenant, mas mutações diretas são
-- substituídas por RPCs que protegem o último proprietário e outros owners.
-- ---------------------------------------------------------------------------
drop policy if exists members_insert_admin on public.organization_members;
drop policy if exists members_update_admin on public.organization_members;
drop policy if exists members_delete_admin on public.organization_members;

create or replace function public.organization_member_directory(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null
     or not public.has_org_role(p_organization_id, array['owner','admin']) then
    raise exception 'forbidden';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'user_id', m.user_id,
        'role', m.role,
        'status', m.status,
        'created_at', m.created_at,
        'full_name', p.full_name,
        'email', u.email,
        'email_confirmed', u.email_confirmed_at is not null
      ) order by
        case m.role when 'owner' then 0 when 'admin' then 1 else 2 end,
        m.created_at
    )
    from public.organization_members m
    join auth.users u on u.id = m.user_id
    left join public.profiles p on p.id = m.user_id
    where m.organization_id = p_organization_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.organization_member_directory(uuid) from public;
grant execute on function public.organization_member_directory(uuid) to authenticated;

create or replace function public.manage_organization_member(
  p_organization_id uuid,
  p_user_id uuid,
  p_action text,
  p_role text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_role text;
  v_target_role text;
  v_owner_count integer;
begin
  select role into v_actor_role
  from public.organization_members
  where organization_id = p_organization_id
    and user_id = auth.uid()
    and status = 'active';

  if v_actor_role not in ('owner','admin') then
    raise exception 'forbidden';
  end if;

  select role into v_target_role
  from public.organization_members
  where organization_id = p_organization_id and user_id = p_user_id;

  if v_target_role is null then
    raise exception 'member not found';
  end if;

  -- Administradores nunca alteram um proprietário.
  if v_actor_role = 'admin' and v_target_role = 'owner' then
    raise exception 'only owner can manage owner';
  end if;

  if p_action = 'role' then
    if p_role not in ('owner','admin','sales','support','viewer') then
      raise exception 'invalid role';
    end if;
    if p_role = 'owner' and v_actor_role <> 'owner' then
      raise exception 'only owner can promote owner';
    end if;

    if v_target_role = 'owner' and p_role <> 'owner' then
      select count(*) into v_owner_count
      from public.organization_members
      where organization_id = p_organization_id
        and role = 'owner'
        and status = 'active';
      if v_owner_count <= 1 then raise exception 'last owner'; end if;
    end if;

    update public.organization_members
    set role = p_role, updated_at = now()
    where organization_id = p_organization_id and user_id = p_user_id;

  elsif p_action in ('enable','disable') then
    if v_target_role = 'owner' and p_action = 'disable' then
      select count(*) into v_owner_count
      from public.organization_members
      where organization_id = p_organization_id
        and role = 'owner'
        and status = 'active';
      if v_owner_count <= 1 then raise exception 'last owner'; end if;
    end if;

    update public.organization_members
    set status = case when p_action = 'enable' then 'active' else 'disabled' end,
        updated_at = now()
    where organization_id = p_organization_id and user_id = p_user_id;

  elsif p_action = 'remove' then
    if v_target_role = 'owner' then
      select count(*) into v_owner_count
      from public.organization_members
      where organization_id = p_organization_id
        and role = 'owner'
        and status = 'active';
      if v_owner_count <= 1 then raise exception 'last owner'; end if;
    end if;

    delete from public.organization_members
    where organization_id = p_organization_id and user_id = p_user_id;
  else
    raise exception 'invalid action';
  end if;

  insert into public.audit_logs (
    organization_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    p_organization_id,
    auth.uid(),
    'organization.member_' || p_action,
    'organization_member',
    p_user_id,
    jsonb_build_object('role', p_role)
  );
end;
$$;

revoke all on function public.manage_organization_member(uuid,uuid,text,text) from public;
grant execute on function public.manage_organization_member(uuid,uuid,text,text) to authenticated;

-- Funções administrativas internas: jamais concedidas a anon/authenticated.
create or replace function public.service_find_auth_user_id_by_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = public, auth
as $$
  select u.id
  from auth.users u
  where lower(u.email) = lower(trim(p_email))
  limit 1;
$$;

revoke all on function public.service_find_auth_user_id_by_email(text) from public;
grant execute on function public.service_find_auth_user_id_by_email(text) to service_role;

create or replace function public.service_add_organization_member(
  p_organization_id uuid,
  p_user_id uuid,
  p_role text,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_role not in ('owner','admin','sales','support','viewer')
     or p_status not in ('active','invited','disabled') then
    raise exception 'invalid member';
  end if;

  if not exists(select 1 from public.organizations where id = p_organization_id) then
    raise exception 'organization not found';
  end if;

  insert into public.organization_members (organization_id, user_id, role, status)
  values (p_organization_id, p_user_id, p_role, p_status)
  on conflict (organization_id, user_id)
  do update set role = excluded.role, status = excluded.status, updated_at = now();
end;
$$;

revoke all on function public.service_add_organization_member(uuid,uuid,text,text) from public;
grant execute on function public.service_add_organization_member(uuid,uuid,text,text) to service_role;

-- Ao aceitar o convite do Supabase, o vínculo pendente passa a ativo.
create or replace function public.activate_invited_memberships()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    update public.organization_members
    set status = 'active', updated_at = now()
    where user_id = new.id and status = 'invited';
  end if;
  return new;
end;
$$;

create trigger on_auth_user_confirmed_activate_memberships
after update of email_confirmed_at on auth.users
for each row execute procedure public.activate_invited_memberships();

-- ---------------------------------------------------------------------------
-- Storage de imagens públicas da organização.
-- Bucket público para assets que aparecem no site, mas escrita é isolada por
-- tenant e por papel. Limites também são aplicados no bucket.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'organization-assets',
  'organization-assets',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy organization_assets_insert_staff
on storage.objects for insert to authenticated
with check (
  bucket_id = 'organization-assets'
  and exists (
    select 1
    from public.organization_members m
    where m.organization_id::text = split_part(name, '/', 1)
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner','admin','sales','support')
  )
);

create policy organization_assets_update_staff
on storage.objects for update to authenticated
using (
  bucket_id = 'organization-assets'
  and exists (
    select 1
    from public.organization_members m
    where m.organization_id::text = split_part(name, '/', 1)
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner','admin','sales','support')
  )
)
with check (
  bucket_id = 'organization-assets'
  and exists (
    select 1
    from public.organization_members m
    where m.organization_id::text = split_part(name, '/', 1)
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner','admin','sales','support')
  )
);

create policy organization_assets_delete_admin
on storage.objects for delete to authenticated
using (
  bucket_id = 'organization-assets'
  and exists (
    select 1
    from public.organization_members m
    where m.organization_id::text = split_part(name, '/', 1)
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner','admin')
  )
);

-- Atualiza payload público para incluir imagens reais quando cadastradas.
create or replace function public.get_public_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org public.organizations%rowtype;
  v_site public.site_configs%rowtype;
begin
  select o.* into v_org
  from public.organizations o
  where o.slug = p_slug and o.status = 'active'
  limit 1;

  if v_org.id is null then return null; end if;

  select s.* into v_site
  from public.site_configs s
  where s.organization_id = v_org.id and s.status = 'published'
  limit 1;

  if v_site.id is null then return null; end if;

  return jsonb_build_object(
    'organization', jsonb_build_object(
      'name', v_org.name, 'slug', v_org.slug, 'segment', v_org.segment,
      'whatsapp', v_org.whatsapp, 'phone', v_org.phone,
      'city', v_org.city, 'state', v_org.state
    ),
    'site', jsonb_build_object(
      'headline', v_site.headline, 'subheadline', v_site.subheadline, 'about', v_site.about
    ),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'description', p.description,
        'price_cents', p.price_cents, 'promotional_price_cents', p.promotional_price_cents,
        'image_url', p.image_url
      ) order by p.featured desc, p.created_at desc)
      from public.products p
      where p.organization_id = v_org.id and p.available = true
    ), '[]'::jsonb),
    'services', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'description', s.description,
        'starting_price_cents', s.starting_price_cents, 'image_url', s.image_url
      ) order by s.created_at desc)
      from public.services s
      where s.organization_id = v_org.id and s.active = true
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_public_site(text) from public;
grant execute on function public.get_public_site(text) to anon, authenticated;

-- ============================================================================
-- 202608150005_billing_mercadopago.sql
-- ============================================================================

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

-- ============================================================================
-- 202608150006_catalog_notifications.sql
-- ============================================================================

-- 2026-08-15 — Categorias consistentes, central de notificações e eventos de produto.

-- Categorias não podem repetir o mesmo nome (case-insensitive) dentro do tenant.
create unique index if not exists categories_org_lower_name_uidx
  on public.categories(organization_id, lower(name));

-- Histórico é append-only. Eventos criados diretamente pela aplicação precisam
-- pertencer ao usuário autenticado e ficam limitados aos tipos operacionais
-- que realmente nascem do painel. Eventos de sistema continuam sendo gravados
-- somente pelas RPCs SECURITY DEFINER ou pelo backend service-role.
drop policy if exists events_insert_staff on public.events;
drop policy if exists events_update_staff on public.events;
drop policy if exists events_delete_admin on public.events;

create policy events_insert_staff on public.events
for insert to authenticated
with check (
  public.has_org_role(organization_id, array['owner','admin','sales','support']::text[])
  and actor_user_id = auth.uid()
  and event_type in ('lead_created','lead_stage_changed','note_added','task_completed')
);

-- Não existem policies de UPDATE/DELETE para events: o histórico é append-only.

-- Notificações são materializadas por usuário, evitando que um usuário marque
-- como lida a notificação de outro membro da mesma organização.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_event_id uuid references public.events(id) on delete cascade,
  kind text not null default 'info' check (kind in ('info','success','warning','billing')),
  title text not null check (char_length(title) between 1 and 160),
  body text check (body is null or char_length(body) <= 1000),
  entity_type text,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique (source_event_id, user_id)
);

create index notifications_user_unread_idx
  on public.notifications(user_id, organization_id, read_at, created_at desc);

alter table public.notifications enable row level security;

create policy notifications_select_own on public.notifications
for select to authenticated
using (
  user_id = auth.uid()
  and public.is_org_member(organization_id)
);

-- Inserts são gerados somente pelo trigger/definer; usuários não criam
-- notificações arbitrárias para outros usuários.

create or replace function public.fanout_event_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_body text;
  v_kind text := 'info';
begin
  case new.event_type
    when 'quote_request_received' then
      v_title := 'Novo pedido de orçamento';
      v_body := 'Um novo contato chegou pelo site e precisa de atendimento.';
      v_kind := 'info';
    when 'quote_response' then
      if coalesce(new.metadata->>'status','') = 'approved' then
        v_title := 'Orçamento aprovado';
        v_body := 'O cliente aprovou um orçamento.';
        v_kind := 'success';
      elsif coalesce(new.metadata->>'status','') = 'change_requested' then
        v_title := 'Cliente pediu alteração';
        v_body := 'Um orçamento recebeu uma solicitação de alteração.';
        v_kind := 'warning';
      elsif coalesce(new.metadata->>'status','') = 'rejected' then
        v_title := 'Orçamento recusado';
        v_body := 'Um cliente recusou um orçamento.';
        v_kind := 'warning';
      else
        return new;
      end if;
    when 'lead_converted_to_customer' then
      v_title := 'Novo cliente';
      v_body := 'Um lead foi convertido em cliente.';
      v_kind := 'success';
    when 'subscription_status_changed' then
      v_title := 'Assinatura atualizada';
      v_body := 'O status da assinatura mudou para ' || coalesce(new.metadata->>'status','desconhecido') || '.';
      v_kind := 'billing';
    else
      return new;
  end case;

  insert into public.notifications (
    organization_id, user_id, source_event_id, kind, title, body, entity_type, entity_id
  )
  select
    new.organization_id, m.user_id, new.id, v_kind, v_title, v_body, new.entity_type, new.entity_id
  from public.organization_members m
  where m.organization_id = new.organization_id
    and m.status = 'active'
    and (new.actor_user_id is null or m.user_id <> new.actor_user_id)
  on conflict (source_event_id, user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.fanout_event_notification() from public;
revoke all on function public.fanout_event_notification() from anon;
revoke all on function public.fanout_event_notification() from authenticated;

create trigger events_fanout_notification
after insert on public.events
for each row execute procedure public.fanout_event_notification();

-- Marca uma ou todas as notificações da organização atual como lidas sem
-- confiar em IDs enviados pelo cliente fora do tenant/usuário.
create or replace function public.mark_notifications_read(
  p_organization_id uuid,
  p_notification_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then
    raise exception 'forbidden';
  end if;

  update public.notifications
  set read_at = coalesce(read_at, now())
  where organization_id = p_organization_id
    and user_id = auth.uid()
    and read_at is null
    and (p_notification_id is null or id = p_notification_id);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.mark_notifications_read(uuid,uuid) from public;
grant execute on function public.mark_notifications_read(uuid,uuid) to authenticated;

-- ============================================================================
-- 202608150007_entitlements_trial_site_blocks.sql
-- ============================================================================

-- 2026-08-15 — Entitlements reais, trial configurável e editor do site por blocos.

alter table public.plans
  add column if not exists entitlements jsonb not null default '{}'::jsonb check (jsonb_typeof(entitlements) = 'object'),
  add column if not exists trial_days integer not null default 7 check (trial_days between 0 and 90);

update public.plans
set entitlements = case code
  when 'essential' then '{"site":true,"catalog":true,"leads":true,"dashboard":true,"forms":true,"basic_seo":true}'::jsonb
  when 'professional' then '{"site":true,"catalog":true,"leads":true,"dashboard":true,"forms":true,"basic_seo":true,"crm":true,"quotes":true,"tasks":true,"exports":true,"appointments":true,"analytics":true,"advanced_site":true}'::jsonb
  when 'ai' then '{"site":true,"catalog":true,"leads":true,"dashboard":true,"forms":true,"basic_seo":true,"crm":true,"quotes":true,"tasks":true,"exports":true,"appointments":true,"analytics":true,"advanced_site":true,"ai_assistant":true,"ai_responses":true,"ai_copy":true,"ai_insights":true}'::jsonb
  else entitlements
end,
trial_days = case when code = 'professional' then 7 else trial_days end
where code in ('essential','professional','ai');

create or replace function public.has_feature(p_organization_id uuid, p_feature text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_allowed boolean := false;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then
    return false;
  end if;

  select coalesce((p.entitlements ->> p_feature)::boolean, false)
  into v_allowed
  from public.subscriptions s
  join public.plans p on p.id = s.plan_id and p.active = true
  join public.organizations o on o.id = s.organization_id and o.status = 'active'
  where s.organization_id = p_organization_id
    and (
      s.status = 'active'
      or (s.status = 'trial' and (s.trial_ends_at is null or s.trial_ends_at > now()))
    )
  order by (s.status = 'active') desc, s.created_at desc
  limit 1;

  return coalesce(v_allowed, false);
exception when others then
  return false;
end;
$$;

create or replace function public.feature_limit(p_organization_id uuid, p_limit text)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit integer;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then
    return null;
  end if;

  select case
    when jsonb_typeof(p.limits -> p_limit) = 'number' then (p.limits ->> p_limit)::integer
    else null
  end
  into v_limit
  from public.subscriptions s
  join public.plans p on p.id = s.plan_id and p.active = true
  join public.organizations o on o.id = s.organization_id and o.status = 'active'
  where s.organization_id = p_organization_id
    and (
      s.status = 'active'
      or (s.status = 'trial' and (s.trial_ends_at is null or s.trial_ends_at > now()))
    )
  order by (s.status = 'active') desc, s.created_at desc
  limit 1;

  return v_limit;
exception when others then
  return null;
end;
$$;

revoke all on function public.has_feature(uuid,text) from public;
revoke all on function public.feature_limit(uuid,text) from public;
grant execute on function public.has_feature(uuid,text) to authenticated;
grant execute on function public.feature_limit(uuid,text) to authenticated;

-- Trial nasce junto da organização. O plano de demonstração comercial é o Profissional.
create or replace function public.initialize_organization_trial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan public.plans%rowtype;
begin
  select * into v_plan
  from public.plans
  where active = true
  order by (code = 'professional') desc, sort_order
  limit 1;

  if v_plan.id is not null and v_plan.trial_days > 0 then
    insert into public.subscriptions (
      organization_id, plan_id, provider, status, trial_ends_at
    ) values (
      new.id, v_plan.id, 'trial', 'trial', now() + make_interval(days => v_plan.trial_days)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists organizations_initialize_trial on public.organizations;
create trigger organizations_initialize_trial
after insert on public.organizations
for each row execute procedure public.initialize_organization_trial();

-- Backfill seguro para organizações já existentes sem assinatura.
insert into public.subscriptions (organization_id, plan_id, provider, status, trial_ends_at)
select o.id, p.id, 'trial', 'trial', now() + make_interval(days => p.trial_days)
from public.organizations o
cross join lateral (
  select id, trial_days from public.plans where active = true order by (code = 'professional') desc, sort_order limit 1
) p
where p.trial_days > 0
  and not exists (select 1 from public.subscriptions s where s.organization_id = o.id);

-- Entitlements também entram nas policies: chamadas diretas ao Supabase não contornam o plano.
do $$
declare
  table_name text;
begin
  foreach table_name in array array['pipelines','pipeline_stages','customers'] loop
    execute format('drop policy if exists %I on public.%I', table_name || '_select_member', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_insert_staff', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_update_staff', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_delete_admin', table_name);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id, ''crm''))', table_name || '_select_member', table_name);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''crm''))', table_name || '_insert_staff', table_name);
    execute format('create policy %I on public.%I for update to authenticated using (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''crm'')) with check (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''crm''))', table_name || '_update_staff', table_name);
    execute format('create policy %I on public.%I for delete to authenticated using (public.has_org_role(organization_id, array[''owner'',''admin'']) and public.has_feature(organization_id, ''crm''))', table_name || '_delete_admin', table_name);
  end loop;

  foreach table_name in array array['quotes','quote_items'] loop
    execute format('drop policy if exists %I on public.%I', table_name || '_select_member', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_insert_staff', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_update_staff', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_delete_admin', table_name);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id, ''quotes''))', table_name || '_select_member', table_name);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''quotes''))', table_name || '_insert_staff', table_name);
    execute format('create policy %I on public.%I for update to authenticated using (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''quotes'')) with check (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''quotes''))', table_name || '_update_staff', table_name);
    execute format('create policy %I on public.%I for delete to authenticated using (public.has_org_role(organization_id, array[''owner'',''admin'']) and public.has_feature(organization_id, ''quotes''))', table_name || '_delete_admin', table_name);
  end loop;

  table_name := 'tasks';
  execute format('drop policy if exists %I on public.%I', table_name || '_select_member', table_name);
  execute format('drop policy if exists %I on public.%I', table_name || '_insert_staff', table_name);
  execute format('drop policy if exists %I on public.%I', table_name || '_update_staff', table_name);
  execute format('drop policy if exists %I on public.%I', table_name || '_delete_admin', table_name);
  execute format('create policy %I on public.%I for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id, ''tasks''))', table_name || '_select_member', table_name);
  execute format('create policy %I on public.%I for insert to authenticated with check (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''tasks''))', table_name || '_insert_staff', table_name);
  execute format('create policy %I on public.%I for update to authenticated using (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''tasks'')) with check (public.has_org_role(organization_id, array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id, ''tasks''))', table_name || '_update_staff', table_name);
  execute format('create policy %I on public.%I for delete to authenticated using (public.has_org_role(organization_id, array[''owner'',''admin'']) and public.has_feature(organization_id, ''tasks''))', table_name || '_delete_admin', table_name);
end
$$;

-- Blocos iniciais do site e ordenação segura.
create unique index if not exists site_sections_site_type_uidx
  on public.site_sections(site_config_id, section_type);

create or replace function public.initialize_site_sections()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.site_sections (organization_id, site_config_id, section_type, enabled, sort_order, content)
  values
    (new.organization_id, new.id, 'hero', true, 10, jsonb_build_object('title',coalesce(new.headline,''),'subtitle',coalesce(new.subheadline,''),'cta_label','Solicitar orçamento','cta_target','quote')),
    (new.organization_id, new.id, 'about', true, 20, jsonb_build_object('title','Sobre','text',coalesce(new.about,''))),
    (new.organization_id, new.id, 'services', true, 30, '{"title":"Serviços"}'::jsonb),
    (new.organization_id, new.id, 'products', true, 40, '{"title":"Produtos"}'::jsonb),
    (new.organization_id, new.id, 'contact', true, 50, '{"title":"Contato","text":"Fale com nossa equipe."}'::jsonb),
    (new.organization_id, new.id, 'cta', true, 60, '{"title":"Pronto para conversar?","text":"Conte o que você precisa e solicite um orçamento.","label":"Solicitar orçamento","target":"quote"}'::jsonb)
  on conflict (site_config_id, section_type) do nothing;
  return new;
end;
$$;

drop trigger if exists site_configs_initialize_sections on public.site_configs;
create trigger site_configs_initialize_sections
after insert on public.site_configs
for each row execute procedure public.initialize_site_sections();

insert into public.site_sections (organization_id, site_config_id, section_type, enabled, sort_order, content)
select sc.organization_id, sc.id, seed.section_type, true, seed.sort_order,
  case seed.section_type
    when 'hero' then jsonb_build_object('title',coalesce(sc.headline,''),'subtitle',coalesce(sc.subheadline,''),'cta_label','Solicitar orçamento','cta_target','quote')
    when 'about' then jsonb_build_object('title','Sobre','text',coalesce(sc.about,''))
    else seed.content
  end
from public.site_configs sc
cross join (values
  ('hero',10,'{}'::jsonb),('about',20,'{}'::jsonb),('services',30,'{"title":"Serviços"}'::jsonb),
  ('products',40,'{"title":"Produtos"}'::jsonb),('contact',50,'{"title":"Contato","text":"Fale com nossa equipe."}'::jsonb),
  ('cta',60,'{"title":"Pronto para conversar?","text":"Conte o que você precisa e solicite um orçamento.","label":"Solicitar orçamento","target":"quote"}'::jsonb)
) as seed(section_type,sort_order,content)
on conflict (site_config_id, section_type) do nothing;

create or replace function public.move_site_section(p_section_id uuid, p_direction text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current public.site_sections%rowtype;
  v_neighbor public.site_sections%rowtype;
  v_order integer;
begin
  if p_direction not in ('up','down') then raise exception 'invalid direction'; end if;
  select * into v_current from public.site_sections where id = p_section_id;
  if v_current.id is null or not public.has_org_role(v_current.organization_id, array['owner','admin','sales','support']) then raise exception 'forbidden'; end if;

  if p_direction = 'up' then
    select * into v_neighbor from public.site_sections
    where site_config_id = v_current.site_config_id and sort_order < v_current.sort_order
    order by sort_order desc limit 1;
  else
    select * into v_neighbor from public.site_sections
    where site_config_id = v_current.site_config_id and sort_order > v_current.sort_order
    order by sort_order asc limit 1;
  end if;

  if v_neighbor.id is null then return; end if;
  v_order := v_current.sort_order;
  update public.site_sections set sort_order = -1000000 where id = v_current.id;
  update public.site_sections set sort_order = v_order where id = v_neighbor.id;
  update public.site_sections set sort_order = v_neighbor.sort_order where id = v_current.id;
end;
$$;
revoke all on function public.move_site_section(uuid,text) from public;
grant execute on function public.move_site_section(uuid,text) to authenticated;

-- Site público agora respeita blocos, ordem, cores e imagens controladas pelo projeto.
create or replace function public.get_public_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org public.organizations%rowtype;
  v_site public.site_configs%rowtype;
begin
  select o.* into v_org from public.organizations o where o.slug = p_slug and o.status = 'active' limit 1;
  if v_org.id is null then return null; end if;
  select s.* into v_site from public.site_configs s where s.organization_id = v_org.id and s.status = 'published' limit 1;
  if v_site.id is null then return null; end if;

  return jsonb_build_object(
    'organization', jsonb_build_object('name',v_org.name,'slug',v_org.slug,'segment',v_org.segment,'whatsapp',v_org.whatsapp,'phone',v_org.phone,'city',v_org.city,'state',v_org.state),
    'site', jsonb_build_object('headline',v_site.headline,'subheadline',v_site.subheadline,'about',v_site.about,'primary_color',v_site.primary_color,'cover_image_url',v_site.cover_image_url),
    'sections', coalesce((select jsonb_agg(jsonb_build_object('id',ss.id,'type',ss.section_type,'enabled',ss.enabled,'sort_order',ss.sort_order,'content',ss.content) order by ss.sort_order, ss.created_at) from public.site_sections ss where ss.site_config_id = v_site.id and ss.enabled = true), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'price_cents',p.price_cents,'promotional_price_cents',p.promotional_price_cents,'image_url',p.image_url) order by p.featured desc,p.created_at desc) from public.products p where p.organization_id=v_org.id and p.available=true), '[]'::jsonb),
    'services', coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'starting_price_cents',s.starting_price_cents,'image_url',s.image_url) order by s.created_at desc) from public.services s where s.organization_id=v_org.id and s.active=true), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_public_site(text) from public;
grant execute on function public.get_public_site(text) to anon, authenticated;

create or replace function public.admin_update_plan_entitlements(p_plan_id uuid, p_entitlements jsonb, p_trial_days integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'forbidden'; end if;
  if jsonb_typeof(p_entitlements) <> 'object' or p_trial_days < 0 or p_trial_days > 90 then raise exception 'invalid plan'; end if;
  if exists(select 1 from jsonb_each(p_entitlements) e where jsonb_typeof(e.value) <> 'boolean') then raise exception 'invalid entitlements'; end if;
  update public.plans set entitlements=p_entitlements, trial_days=p_trial_days, updated_at=now() where id=p_plan_id;
  if not found then raise exception 'plan not found'; end if;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'platform.plan_entitlements_updated','plan',p_plan_id,jsonb_build_object('trial_days',p_trial_days,'entitlements',p_entitlements));
end;
$$;
revoke all on function public.admin_update_plan_entitlements(uuid,jsonb,integer) from public;
grant execute on function public.admin_update_plan_entitlements(uuid,jsonb,integer) to authenticated;

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
      'organizations',(select count(*) from public.organizations),
      'active_organizations',(select count(*) from public.organizations where status='active'),
      'users',(select count(*) from auth.users),
      'subscriptions',(select count(*) from public.subscriptions),
      'active_subscriptions',(select count(*) from public.subscriptions where status='active'),
      'trials',(select count(*) from public.subscriptions where status='trial' and (trial_ends_at is null or trial_ends_at > now())),
      'mrr_cents',coalesce((select sum(case when s.billing_cycle='annual' then round(coalesce(s.amount_cents,p.price_annual_cents)::numeric/12)::bigint else coalesce(s.amount_cents,p.price_monthly_cents) end) from public.subscriptions s join public.plans p on p.id=s.plan_id where s.status='active'),0)
    ),
    'organizations',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'slug',o.slug,'segment',o.segment,'status',o.status,'created_at',o.created_at,'members',(select count(*) from public.organization_members om where om.organization_id=o.id and om.status='active'),'subscription_status',(select s.status from public.subscriptions s where s.organization_id=o.id order by s.created_at desc limit 1),'plan_name',(select p.name from public.subscriptions s join public.plans p on p.id=s.plan_id where s.organization_id=o.id order by s.created_at desc limit 1)) order by o.created_at desc) from (select * from public.organizations order by created_at desc limit 100)o),'[]'::jsonb),
    'plans',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'description',p.description,'price_monthly_cents',p.price_monthly_cents,'price_annual_cents',p.price_annual_cents,'features',p.features,'limits',p.limits,'entitlements',p.entitlements,'trial_days',p.trial_days,'active',p.active,'sort_order',p.sort_order) order by p.sort_order) from public.plans p),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_dashboard() from public;
grant execute on function public.admin_dashboard() to authenticated;

-- Rascunho e publicação são separados: edições não vazam para o site público antes do clique em Publicar.
alter table public.site_configs
  add column if not exists published_snapshot jsonb check (published_snapshot is null or jsonb_typeof(published_snapshot) = 'object');

update public.site_configs sc
set published_snapshot = jsonb_build_object(
  'site', jsonb_build_object('headline',sc.headline,'subheadline',sc.subheadline,'about',sc.about,'primary_color',sc.primary_color,'cover_image_url',sc.cover_image_url),
  'sections', coalesce((select jsonb_agg(jsonb_build_object('id',ss.id,'type',ss.section_type,'enabled',ss.enabled,'sort_order',ss.sort_order,'content',ss.content) order by ss.sort_order,ss.created_at) from public.site_sections ss where ss.site_config_id=sc.id and ss.enabled=true),'[]'::jsonb)
)
where sc.status='published' and sc.published_snapshot is null;

create or replace function public.publish_site_snapshot(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site public.site_configs%rowtype;
  v_snapshot jsonb;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) then raise exception 'forbidden'; end if;
  if not public.has_feature(p_organization_id,'site') then raise exception 'feature unavailable'; end if;
  select * into v_site from public.site_configs where organization_id=p_organization_id limit 1;
  if v_site.id is null then raise exception 'site not found'; end if;

  v_snapshot := jsonb_build_object(
    'site',jsonb_build_object('headline',v_site.headline,'subheadline',v_site.subheadline,'about',v_site.about,'primary_color',v_site.primary_color,'cover_image_url',v_site.cover_image_url),
    'sections',coalesce((select jsonb_agg(jsonb_build_object('id',ss.id,'type',ss.section_type,'enabled',ss.enabled,'sort_order',ss.sort_order,'content',ss.content) order by ss.sort_order,ss.created_at) from public.site_sections ss where ss.site_config_id=v_site.id and ss.enabled=true),'[]'::jsonb)
  );

  update public.site_configs
  set status='published', published_at=now(), version=version+1, published_snapshot=v_snapshot, updated_at=now()
  where id=v_site.id;

  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,auth.uid(),'site',v_site.id,'site_published',jsonb_build_object('version',v_site.version+1));
end;
$$;
revoke all on function public.publish_site_snapshot(uuid) from public;
grant execute on function public.publish_site_snapshot(uuid) to authenticated;

create or replace function public.get_public_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org public.organizations%rowtype;
  v_site public.site_configs%rowtype;
  v_snapshot jsonb;
begin
  select o.* into v_org from public.organizations o where o.slug=p_slug and o.status='active' limit 1;
  if v_org.id is null then return null; end if;
  select s.* into v_site from public.site_configs s where s.organization_id=v_org.id and s.status='published' limit 1;
  if v_site.id is null then return null; end if;

  v_snapshot := coalesce(v_site.published_snapshot, jsonb_build_object(
    'site',jsonb_build_object('headline',v_site.headline,'subheadline',v_site.subheadline,'about',v_site.about,'primary_color',v_site.primary_color,'cover_image_url',v_site.cover_image_url),
    'sections',coalesce((select jsonb_agg(jsonb_build_object('id',ss.id,'type',ss.section_type,'enabled',ss.enabled,'sort_order',ss.sort_order,'content',ss.content) order by ss.sort_order,ss.created_at) from public.site_sections ss where ss.site_config_id=v_site.id and ss.enabled=true),'[]'::jsonb)
  ));

  return jsonb_build_object(
    'organization',jsonb_build_object('name',v_org.name,'slug',v_org.slug,'segment',v_org.segment,'whatsapp',v_org.whatsapp,'phone',v_org.phone,'city',v_org.city,'state',v_org.state),
    'site',v_snapshot->'site',
    'sections',coalesce(v_snapshot->'sections','[]'::jsonb),
    'products',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'price_cents',p.price_cents,'promotional_price_cents',p.promotional_price_cents,'image_url',p.image_url) order by p.featured desc,p.created_at desc) from public.products p where p.organization_id=v_org.id and p.available=true),'[]'::jsonb),
    'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'starting_price_cents',s.starting_price_cents,'image_url',s.image_url) order by s.created_at desc) from public.services s where s.organization_id=v_org.id and s.active=true),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_public_site(text) from public;
grant execute on function public.get_public_site(text) to anon, authenticated;

-- Verificação interna para superfícies públicas. Não é concedida a anon/authenticated diretamente.
create or replace function public.organization_has_entitlement(p_organization_id uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.subscriptions s
    join public.plans p on p.id=s.plan_id and p.active=true
    join public.organizations o on o.id=s.organization_id and o.status='active'
    where s.organization_id=p_organization_id
      and coalesce((p.entitlements->>p_feature)::boolean,false)=true
      and (s.status='active' or (s.status='trial' and (s.trial_ends_at is null or s.trial_ends_at>now())))
  );
$$;
revoke all on function public.organization_has_entitlement(uuid,text) from public;

create or replace function public.has_feature(p_organization_id uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and public.is_org_member(p_organization_id)
    and public.organization_has_entitlement(p_organization_id,p_feature);
$$;
revoke all on function public.has_feature(uuid,text) from public;
grant execute on function public.has_feature(uuid,text) to authenticated;

create or replace function public.enforce_quote_request_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.organization_has_entitlement(new.organization_id,'forms') then raise exception 'feature unavailable'; end if;
  return new;
end;
$$;
drop trigger if exists quote_requests_entitlement_guard on public.quote_requests;
create trigger quote_requests_entitlement_guard before insert on public.quote_requests for each row execute procedure public.enforce_quote_request_entitlement();

-- Reaplica get_public_site com bloqueio do entitlement público de site.
create or replace function public.get_public_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org public.organizations%rowtype;
  v_site public.site_configs%rowtype;
  v_snapshot jsonb;
begin
  select o.* into v_org from public.organizations o where o.slug=p_slug and o.status='active' limit 1;
  if v_org.id is null or not public.organization_has_entitlement(v_org.id,'site') then return null; end if;
  select s.* into v_site from public.site_configs s where s.organization_id=v_org.id and s.status='published' limit 1;
  if v_site.id is null then return null; end if;
  v_snapshot := coalesce(v_site.published_snapshot,jsonb_build_object('site',jsonb_build_object('headline',v_site.headline,'subheadline',v_site.subheadline,'about',v_site.about,'primary_color',v_site.primary_color,'cover_image_url',v_site.cover_image_url),'sections','[]'::jsonb));
  return jsonb_build_object(
    'organization',jsonb_build_object('name',v_org.name,'slug',v_org.slug,'segment',v_org.segment,'whatsapp',v_org.whatsapp,'phone',v_org.phone,'city',v_org.city,'state',v_org.state),
    'site',v_snapshot->'site','sections',coalesce(v_snapshot->'sections','[]'::jsonb),
    'products',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'price_cents',p.price_cents,'promotional_price_cents',p.promotional_price_cents,'image_url',p.image_url) order by p.featured desc,p.created_at desc) from public.products p where p.organization_id=v_org.id and p.available=true),'[]'::jsonb),
    'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'starting_price_cents',s.starting_price_cents,'image_url',s.image_url) order by s.created_at desc) from public.services s where s.organization_id=v_org.id and s.active=true),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_public_site(text) from public;
grant execute on function public.get_public_site(text) to anon,authenticated;

-- ============================================================================
-- 202608150008_seo_contact.sql
-- ============================================================================

-- 2026-08-15 — Contato comercial real + índice público para sitemap.

create table public.platform_contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 160),
  email text not null check (char_length(email) between 3 and 254),
  phone text,
  message text not null check (char_length(message) between 5 and 5000),
  status text not null default 'new' check (status in ('new','in_progress','resolved','spam')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index platform_contact_messages_status_created_idx on public.platform_contact_messages(status,created_at desc);
alter table public.platform_contact_messages enable row level security;
create policy platform_contact_select_admin on public.platform_contact_messages for select to authenticated using (public.is_platform_admin());
create policy platform_contact_update_admin on public.platform_contact_messages for update to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());
-- Sem INSERT para anon/authenticated: gravação ocorre somente pelo backend secreto após rate limit.

create or replace function public.list_public_sites()
returns table(slug text, published_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select o.slug, sc.published_at
  from public.organizations o
  join public.site_configs sc on sc.organization_id=o.id and sc.status='published'
  where o.status='active' and public.organization_has_entitlement(o.id,'site')
  order by sc.published_at desc nulls last;
$$;
revoke all on function public.list_public_sites() from public;
grant execute on function public.list_public_sites() to anon,authenticated;

-- ============================================================================
-- 202608150009_dashboard_timezone.sql
-- ============================================================================

-- 2026-08-15 — Dashboard Hoje com timezone da organização e comparação real de períodos.
alter table public.organizations add column if not exists timezone text not null default 'America/Sao_Paulo';

create or replace function public.organization_dashboard_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz text;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_month_start timestamptz;
  v_previous_month_start timestamptz;
  v_crm boolean;
  v_quotes boolean;
  v_tasks boolean;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then raise exception 'forbidden'; end if;
  select timezone into v_tz from public.organizations where id=p_organization_id;
  if v_tz is null then v_tz := 'America/Sao_Paulo'; end if;

  v_day_start := (date_trunc('day', now() at time zone v_tz) at time zone v_tz);
  v_day_end := v_day_start + interval '1 day';
  v_month_start := (date_trunc('month', now() at time zone v_tz) at time zone v_tz);
  v_previous_month_start := v_month_start - interval '1 month';
  v_crm := public.has_feature(p_organization_id,'crm');
  v_quotes := public.has_feature(p_organization_id,'quotes');
  v_tasks := public.has_feature(p_organization_id,'tasks');

  return jsonb_build_object(
    'timezone',v_tz,
    'leads_today',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_day_start and created_at<v_day_end),
    'leads_month',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_month_start),
    'leads_previous_month',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_previous_month_start and created_at<v_month_start),
    'leads_total',(select count(*) from public.leads where organization_id=p_organization_id),
    'potential_value_cents',coalesce((select sum(potential_value_cents) from public.leads where organization_id=p_organization_id and status not in ('won','lost')),0),
    'customers_total',case when v_crm then (select count(*) from public.customers where organization_id=p_organization_id) else null end,
    'followups_due',case when v_crm then (select count(*) from public.leads where organization_id=p_organization_id and next_contact_at is not null and next_contact_at<v_day_end and status not in ('won','lost')) else null end,
    'quotes_pending',case when v_quotes then (select count(*) from public.quotes where organization_id=p_organization_id and status in ('draft','sent','viewed','change_requested')) else null end,
    'quotes_month',case when v_quotes then (select count(*) from public.quotes where organization_id=p_organization_id and created_at>=v_month_start) else null end,
    'tasks_open',case when v_tasks then (select count(*) from public.tasks where organization_id=p_organization_id and status in ('open','in_progress')) else null end,
    'tasks_overdue',case when v_tasks then (select count(*) from public.tasks where organization_id=p_organization_id and status in ('open','in_progress') and due_at is not null and due_at<now()) else null end
  );
end;
$$;
revoke all on function public.organization_dashboard_summary(uuid) from public;
grant execute on function public.organization_dashboard_summary(uuid) to authenticated;

create or replace function public.schedule_lead_followup(p_organization_id uuid, p_lead_id uuid, p_local_datetime text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tz text;
  v_when timestamptz;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'crm') then raise exception 'forbidden'; end if;
  select timezone into v_tz from public.organizations where id=p_organization_id;
  if v_tz is null then v_tz := 'America/Sao_Paulo'; end if;
  begin
    v_when := (p_local_datetime::timestamp at time zone v_tz);
  exception when others then raise exception 'invalid datetime'; end;
  if v_when < now() - interval '5 minutes' or v_when > now() + interval '2 years' then raise exception 'invalid datetime'; end if;
  update public.leads set next_contact_at=v_when, updated_at=now() where organization_id=p_organization_id and id=p_lead_id;
  if not found then raise exception 'lead not found'; end if;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,auth.uid(),'lead',p_lead_id,'note_added',jsonb_build_object('type','follow_up_scheduled','next_contact_at',v_when,'timezone',v_tz));
  return v_when;
end;
$$;
revoke all on function public.schedule_lead_followup(uuid,uuid,text) from public;
grant execute on function public.schedule_lead_followup(uuid,uuid,text) to authenticated;

-- ============================================================================
-- 202608150010_profile_company_coupons.sql
-- ============================================================================

-- 2026-08-15 — Perfil, configurações da empresa e cupons aplicáveis ao billing.

alter table public.profiles
  add column if not exists phone text,
  add column if not exists job_title text,
  add column if not exists notification_preferences jsonb not null default '{"leads":true,"quotes":true,"appointments":true,"billing":true}'::jsonb
    check (jsonb_typeof(notification_preferences) = 'object');

alter table public.organizations
  add column if not exists logo_url text,
  add column if not exists address text,
  add column if not exists business_hours text;

-- Perfil é pessoal: inclusive membros viewer podem enviar o próprio avatar para a pasta de perfil do tenant.
create policy organization_assets_insert_profile_member
on storage.objects for insert to authenticated
with check (
  bucket_id = 'organization-assets'
  and split_part(name, '/', 2) = 'profile'
  and exists (
    select 1 from public.organization_members m
    where m.organization_id::text = split_part(name, '/', 1)
      and m.user_id = auth.uid() and m.status = 'active'
  )
);

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  description text,
  discount_type text not null check (discount_type in ('percent','fixed')),
  percent_off integer check (percent_off is null or percent_off between 1 and 100),
  amount_off_cents bigint check (amount_off_cents is null or amount_off_cents > 0),
  starts_at timestamptz,
  expires_at timestamptz,
  max_redemptions integer check (max_redemptions is null or max_redemptions > 0),
  redemptions_count integer not null default 0 check (redemptions_count >= 0),
  per_organization_limit integer not null default 1 check (per_organization_limit > 0),
  plan_id uuid references public.plans(id) on delete set null,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (discount_type = 'percent' and percent_off is not null and amount_off_cents is null)
    or (discount_type = 'fixed' and amount_off_cents is not null and percent_off is null)
  ),
  check (expires_at is null or starts_at is null or expires_at > starts_at)
);

create unique index coupons_code_uidx on public.coupons (upper(code));
create index coupons_active_expiry_idx on public.coupons(active, expires_at);
create trigger coupons_set_updated_at before update on public.coupons
for each row execute procedure public.set_updated_at();

alter table public.coupons enable row level security;
-- Cupons são operados apenas por RPCs de platform admin. Não há policy pública da tabela.

alter table public.billing_checkout_sessions
  add column if not exists coupon_id uuid references public.coupons(id) on delete set null,
  add column if not exists list_amount_cents bigint,
  add column if not exists discount_cents bigint not null default 0 check (discount_cents >= 0);

update public.billing_checkout_sessions
set list_amount_cents = amount_cents
where list_amount_cents is null;

alter table public.billing_checkout_sessions
  alter column list_amount_cents set not null;

create table public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  checkout_session_id uuid not null unique references public.billing_checkout_sessions(id) on delete cascade,
  discount_cents bigint not null check (discount_cents > 0),
  redeemed_at timestamptz not null default now(),
  unique(coupon_id, checkout_session_id)
);
create index coupon_redemptions_coupon_org_idx on public.coupon_redemptions(coupon_id, organization_id, redeemed_at desc);
alter table public.coupon_redemptions enable row level security;
-- Resgates são internos do billing; sem policy para clientes.

create or replace function public.admin_list_coupons()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'forbidden'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',c.id,'code',c.code,'description',c.description,'discount_type',c.discount_type,
      'percent_off',c.percent_off,'amount_off_cents',c.amount_off_cents,
      'starts_at',c.starts_at,'expires_at',c.expires_at,'max_redemptions',c.max_redemptions,
      'redemptions_count',c.redemptions_count,'per_organization_limit',c.per_organization_limit,
      'plan_id',c.plan_id,'plan_name',p.name,'active',c.active,'created_at',c.created_at
    ) order by c.created_at desc)
    from public.coupons c left join public.plans p on p.id=c.plan_id
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_list_coupons() from public;
grant execute on function public.admin_list_coupons() to authenticated;

create or replace function public.admin_save_coupon(
  p_coupon_id uuid,
  p_code text,
  p_description text,
  p_discount_type text,
  p_percent_off integer,
  p_amount_off_cents bigint,
  p_starts_at timestamptz,
  p_expires_at timestamptz,
  p_max_redemptions integer,
  p_per_organization_limit integer,
  p_plan_id uuid,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_code text := upper(trim(coalesce(p_code,'')));
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'forbidden'; end if;
  if v_code !~ '^[A-Z0-9_-]{3,40}$' then raise exception 'invalid code'; end if;
  if p_discount_type not in ('percent','fixed') then raise exception 'invalid discount type'; end if;
  if p_discount_type='percent' and (p_percent_off is null or p_percent_off not between 1 and 100 or p_amount_off_cents is not null) then raise exception 'invalid percent'; end if;
  if p_discount_type='fixed' and (p_amount_off_cents is null or p_amount_off_cents <= 0 or p_percent_off is not null) then raise exception 'invalid amount'; end if;
  if p_per_organization_limit is null or p_per_organization_limit < 1 then raise exception 'invalid per organization limit'; end if;
  if p_max_redemptions is not null and p_max_redemptions < 1 then raise exception 'invalid max redemptions'; end if;
  if p_expires_at is not null and p_starts_at is not null and p_expires_at <= p_starts_at then raise exception 'invalid dates'; end if;
  if p_plan_id is not null and not exists(select 1 from public.plans where id=p_plan_id) then raise exception 'plan not found'; end if;

  if p_coupon_id is null then
    insert into public.coupons(code,description,discount_type,percent_off,amount_off_cents,starts_at,expires_at,max_redemptions,per_organization_limit,plan_id,active,created_by)
    values(v_code,nullif(trim(coalesce(p_description,'')),''),p_discount_type,p_percent_off,p_amount_off_cents,p_starts_at,p_expires_at,p_max_redemptions,p_per_organization_limit,p_plan_id,p_active,auth.uid())
    returning id into v_id;
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'platform.coupon_created','coupon',v_id,jsonb_build_object('code',v_code));
  else
    update public.coupons set
      code=v_code,description=nullif(trim(coalesce(p_description,'')),''),discount_type=p_discount_type,
      percent_off=p_percent_off,amount_off_cents=p_amount_off_cents,starts_at=p_starts_at,expires_at=p_expires_at,
      max_redemptions=p_max_redemptions,per_organization_limit=p_per_organization_limit,plan_id=p_plan_id,active=p_active
    where id=p_coupon_id returning id into v_id;
    if v_id is null then raise exception 'coupon not found'; end if;
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'platform.coupon_updated','coupon',v_id,jsonb_build_object('code',v_code));
  end if;
  return v_id;
end;
$$;
revoke all on function public.admin_save_coupon(uuid,text,text,text,integer,bigint,timestamptz,timestamptz,integer,integer,uuid,boolean) from public;
grant execute on function public.admin_save_coupon(uuid,text,text,text,integer,bigint,timestamptz,timestamptz,integer,integer,uuid,boolean) to authenticated;

create or replace function public.validate_coupon_for_checkout(
  p_organization_id uuid,
  p_plan_id uuid,
  p_code text,
  p_list_amount_cents bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_coupon public.coupons%rowtype;
  v_used integer;
  v_discount bigint;
  v_final bigint;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) then raise exception 'forbidden'; end if;
  if p_list_amount_cents is null or p_list_amount_cents <= 0 then raise exception 'invalid amount'; end if;
  select * into v_coupon from public.coupons
  where upper(code)=upper(trim(coalesce(p_code,''))) and active=true limit 1;
  if v_coupon.id is null then raise exception 'coupon unavailable'; end if;
  if v_coupon.starts_at is not null and v_coupon.starts_at > now() then raise exception 'coupon not started'; end if;
  if v_coupon.expires_at is not null and v_coupon.expires_at <= now() then raise exception 'coupon expired'; end if;
  if v_coupon.plan_id is not null and v_coupon.plan_id <> p_plan_id then raise exception 'coupon plan mismatch'; end if;
  if v_coupon.max_redemptions is not null and v_coupon.redemptions_count >= v_coupon.max_redemptions then raise exception 'coupon exhausted'; end if;
  select count(*)::integer into v_used from public.coupon_redemptions where coupon_id=v_coupon.id and organization_id=p_organization_id;
  if v_used >= v_coupon.per_organization_limit then raise exception 'coupon organization limit'; end if;

  v_discount := case when v_coupon.discount_type='percent'
    then floor(p_list_amount_cents::numeric * v_coupon.percent_off::numeric / 100)::bigint
    else least(v_coupon.amount_off_cents,p_list_amount_cents-100)
  end;
  v_discount := greatest(0,least(v_discount,p_list_amount_cents-100));
  v_final := p_list_amount_cents-v_discount;
  if v_discount <= 0 or v_final < 100 then raise exception 'coupon discount invalid'; end if;

  return jsonb_build_object('id',v_coupon.id,'code',v_coupon.code,'discount_cents',v_discount,'final_amount_cents',v_final);
end;
$$;
revoke all on function public.validate_coupon_for_checkout(uuid,uuid,text,bigint) from public;
grant execute on function public.validate_coupon_for_checkout(uuid,uuid,text,bigint) to authenticated;

-- Chamada exclusivamente pelo backend com service role depois que o provider confirma autorização.
create or replace function public.apply_coupon_redemption(p_checkout_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.billing_checkout_sessions%rowtype;
  v_inserted uuid;
begin
  select * into v_session from public.billing_checkout_sessions where id=p_checkout_session_id for update;
  if v_session.id is null or v_session.status <> 'authorized' or v_session.coupon_id is null or v_session.discount_cents <= 0 then return; end if;

  insert into public.coupon_redemptions(coupon_id,organization_id,checkout_session_id,discount_cents)
  values(v_session.coupon_id,v_session.organization_id,v_session.id,v_session.discount_cents)
  on conflict (checkout_session_id) do nothing
  returning id into v_inserted;

  if v_inserted is not null then
    update public.coupons set redemptions_count=redemptions_count+1,updated_at=now() where id=v_session.coupon_id;
  end if;
end;
$$;
revoke all on function public.apply_coupon_redemption(uuid) from public;
grant execute on function public.apply_coupon_redemption(uuid) to service_role;

-- ============================================================================
-- 202608150011_appointments.sql
-- ============================================================================

-- 2026-08-15 — Fase 2: agenda, disponibilidade e agendamento público seguro.
create extension if not exists btree_gist;

create table public.booking_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  enabled boolean not null default false,
  slot_duration_minutes integer not null default 60 check (slot_duration_minutes between 15 and 480),
  buffer_minutes integer not null default 0 check (buffer_minutes between 0 and 180),
  availability jsonb not null default '{"1":[["08:00","18:00"]],"2":[["08:00","18:00"]],"3":[["08:00","18:00"]],"4":[["08:00","18:00"]],"5":[["08:00","18:00"]]}'::jsonb
    check (jsonb_typeof(availability)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger booking_settings_set_updated_at before update on public.booking_settings for each row execute procedure public.set_updated_at();

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  service_id uuid references public.services(id) on delete set null,
  professional_user_id uuid references auth.users(id) on delete set null,
  contact_name text check (contact_name is null or char_length(contact_name) between 2 and 160),
  contact_phone text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled','confirmed','completed','canceled','no_show')),
  source text not null default 'internal' check (source in ('internal','public')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (ends_at <= starts_at + interval '12 hours')
);
create index appointments_org_start_idx on public.appointments(organization_id, starts_at, status);
create index appointments_professional_start_idx on public.appointments(professional_user_id, starts_at) where professional_user_id is not null;
create trigger appointments_set_updated_at before update on public.appointments for each row execute procedure public.set_updated_at();

alter table public.booking_settings enable row level security;
alter table public.appointments enable row level security;
create policy booking_settings_select_member on public.booking_settings for select to authenticated using (public.is_org_member(organization_id));
create policy booking_settings_insert_admin on public.booking_settings for insert to authenticated with check (public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'appointments'));
create policy booking_settings_update_admin on public.booking_settings for update to authenticated using (public.has_org_role(organization_id,array['owner','admin'])) with check (public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'appointments'));
create policy appointments_select_member on public.appointments for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id,'appointments'));
-- Escrita de appointments é feita pelas RPCs abaixo para centralizar conflito, timezone e auditoria.

insert into public.booking_settings(organization_id)
select o.id from public.organizations o
where not exists(select 1 from public.booking_settings b where b.organization_id=o.id)
on conflict do nothing;

create or replace function public.save_booking_settings(
  p_organization_id uuid,
  p_enabled boolean,
  p_slot_duration_minutes integer,
  p_buffer_minutes integer,
  p_availability jsonb
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden'; end if;
  if p_slot_duration_minutes not between 15 and 480 or p_buffer_minutes not between 0 and 180 or jsonb_typeof(p_availability)<>'object' then raise exception 'invalid settings'; end if;
  insert into public.booking_settings(organization_id,enabled,slot_duration_minutes,buffer_minutes,availability)
  values(p_organization_id,p_enabled,p_slot_duration_minutes,p_buffer_minutes,p_availability)
  on conflict(organization_id) do update set enabled=excluded.enabled,slot_duration_minutes=excluded.slot_duration_minutes,buffer_minutes=excluded.buffer_minutes,availability=excluded.availability,updated_at=now();
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id)
  values(p_organization_id,auth.uid(),'booking.settings_updated','organization',p_organization_id);
end;
$$;
revoke all on function public.save_booking_settings(uuid,boolean,integer,integer,jsonb) from public;
grant execute on function public.save_booking_settings(uuid,boolean,integer,integer,jsonb) to authenticated;

create or replace function public.create_appointment(
  p_organization_id uuid,
  p_lead_id uuid,
  p_customer_id uuid,
  p_service_id uuid,
  p_professional_user_id uuid,
  p_local_start text,
  p_duration_minutes integer,
  p_notes text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_tz text; v_start timestamptz; v_end timestamptz; v_duration integer; v_id uuid; v_buffer integer := 0;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden'; end if;
  select timezone into v_tz from public.organizations where id=p_organization_id;
  if v_tz is null then v_tz:='America/Sao_Paulo'; end if;
  select coalesce(buffer_minutes,0) into v_buffer from public.booking_settings where organization_id=p_organization_id;
  v_buffer := coalesce(v_buffer,0);
  begin v_start := (p_local_start::timestamp at time zone v_tz); exception when others then raise exception 'invalid datetime'; end;
  if v_start < now()-interval '5 minutes' or v_start > now()+interval '2 years' then raise exception 'invalid datetime'; end if;
  if p_service_id is not null and not exists(select 1 from public.services where id=p_service_id and organization_id=p_organization_id and active=true) then raise exception 'service not found'; end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and organization_id=p_organization_id) then raise exception 'customer not found'; end if;
  if p_lead_id is not null and not exists(select 1 from public.leads where id=p_lead_id and organization_id=p_organization_id) then raise exception 'lead not found'; end if;
  if p_professional_user_id is not null and not exists(select 1 from public.organization_members where organization_id=p_organization_id and user_id=p_professional_user_id and status='active') then raise exception 'professional not found'; end if;
  v_duration := coalesce(nullif(p_duration_minutes,0),(select duration_minutes from public.services where id=p_service_id),60);
  if v_duration not between 15 and 480 then raise exception 'invalid duration'; end if;
  v_end := v_start + make_interval(mins=>v_duration);
  if p_professional_user_id is not null and exists(select 1 from public.appointments a where a.organization_id=p_organization_id and a.professional_user_id=p_professional_user_id and a.status in('scheduled','confirmed') and tstzrange(a.starts_at-make_interval(mins=>v_buffer),a.ends_at+make_interval(mins=>v_buffer),'[)') && tstzrange(v_start,v_end,'[)')) then raise exception 'schedule conflict'; end if;
  insert into public.appointments(organization_id,lead_id,customer_id,service_id,professional_user_id,starts_at,ends_at,notes,source,created_by)
  values(p_organization_id,p_lead_id,p_customer_id,p_service_id,p_professional_user_id,v_start,v_end,nullif(trim(coalesce(p_notes,'')),''),'internal',auth.uid()) returning id into v_id;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,auth.uid(),'appointment',v_id,'appointment_created',jsonb_build_object('starts_at',v_start,'ends_at',v_end,'source','internal'));
  return v_id;
end;
$$;
revoke all on function public.create_appointment(uuid,uuid,uuid,uuid,uuid,text,integer,text) from public;
grant execute on function public.create_appointment(uuid,uuid,uuid,uuid,uuid,text,integer,text) to authenticated;

create or replace function public.update_appointment_status(p_organization_id uuid,p_appointment_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden'; end if;
  if p_status not in('scheduled','confirmed','completed','canceled','no_show') then raise exception 'invalid status'; end if;
  update public.appointments set status=p_status,updated_at=now() where id=p_appointment_id and organization_id=p_organization_id;
  if not found then raise exception 'appointment not found'; end if;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,auth.uid(),'appointment',p_appointment_id,'appointment_status_changed',jsonb_build_object('status',p_status));
end; $$;
revoke all on function public.update_appointment_status(uuid,uuid,text) from public;
grant execute on function public.update_appointment_status(uuid,uuid,text) to authenticated;

create or replace function public.get_public_booking(p_slug text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_org public.organizations%rowtype; v_settings public.booking_settings%rowtype;
begin
  select * into v_org from public.organizations where slug=p_slug and status='active' limit 1;
  if v_org.id is null or not public.organization_has_entitlement(v_org.id,'appointments') then return null; end if;
  select * into v_settings from public.booking_settings where organization_id=v_org.id and enabled=true;
  if v_settings.organization_id is null then return null; end if;
  return jsonb_build_object(
    'organization',jsonb_build_object('name',v_org.name,'slug',v_org.slug,'timezone',v_org.timezone,'city',v_org.city,'state',v_org.state),
    'settings',jsonb_build_object('slot_duration_minutes',v_settings.slot_duration_minutes,'buffer_minutes',v_settings.buffer_minutes,'availability',v_settings.availability),
    'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'duration_minutes',coalesce(s.duration_minutes,v_settings.slot_duration_minutes),'starting_price_cents',s.starting_price_cents) order by s.name) from public.services s where s.organization_id=v_org.id and s.active=true),'[]'::jsonb)
  );
end; $$;
revoke all on function public.get_public_booking(text) from public;
grant execute on function public.get_public_booking(text) to anon,authenticated;

create or replace function public.public_create_appointment(p_slug text,p_service_id uuid,p_local_start text,p_name text,p_phone text)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_org public.organizations%rowtype; v_settings public.booking_settings%rowtype; v_service public.services%rowtype;
  v_start_local timestamp; v_end_local timestamp; v_start timestamptz; v_end timestamptz; v_day text; v_ranges jsonb; v_allowed boolean; v_phone text; v_lead uuid; v_pipeline uuid; v_stage uuid; v_id uuid;
begin
  select * into v_org from public.organizations where slug=p_slug and status='active' limit 1;
  if v_org.id is null or not public.organization_has_entitlement(v_org.id,'appointments') then raise exception 'booking unavailable'; end if;
  select * into v_settings from public.booking_settings where organization_id=v_org.id and enabled=true;
  if v_settings.organization_id is null then raise exception 'booking unavailable'; end if;
  select * into v_service from public.services where id=p_service_id and organization_id=v_org.id and active=true;
  if v_service.id is null then raise exception 'service unavailable'; end if;
  if char_length(trim(coalesce(p_name,'')))<2 then raise exception 'invalid name'; end if;
  v_phone:=regexp_replace(coalesce(p_phone,''),'\D','','g'); if char_length(v_phone)<8 then raise exception 'invalid phone'; end if;
  begin v_start_local:=p_local_start::timestamp; exception when others then raise exception 'invalid datetime'; end;
  v_end_local:=v_start_local+make_interval(mins=>coalesce(v_service.duration_minutes,v_settings.slot_duration_minutes));
  if v_end_local::date<>v_start_local::date then raise exception 'outside availability'; end if;
  v_start:=v_start_local at time zone v_org.timezone; v_end:=v_end_local at time zone v_org.timezone;
  if v_start<now()+interval '15 minutes' or v_start>now()+interval '180 days' then raise exception 'invalid datetime'; end if;
  v_day:=extract(isodow from v_start_local)::integer::text; v_ranges:=v_settings.availability->v_day;
  if v_ranges is null or jsonb_typeof(v_ranges)<>'array' then raise exception 'outside availability'; end if;
  select exists(select 1 from jsonb_array_elements(v_ranges) r where jsonb_typeof(r)='array' and jsonb_array_length(r)>=2 and (r->>0)::time<=v_start_local::time and (r->>1)::time>=v_end_local::time) into v_allowed;
  if not coalesce(v_allowed,false) then raise exception 'outside availability'; end if;
  if exists(select 1 from public.appointments a where a.organization_id=v_org.id and a.status in('scheduled','confirmed') and tstzrange(a.starts_at-make_interval(mins=>v_settings.buffer_minutes),a.ends_at+make_interval(mins=>v_settings.buffer_minutes),'[)') && tstzrange(v_start,v_end,'[)')) then raise exception 'schedule conflict'; end if;

  select id into v_lead from public.leads where organization_id=v_org.id and (regexp_replace(coalesce(phone,''),'\D','','g')=v_phone or regexp_replace(coalesce(whatsapp,''),'\D','','g')=v_phone) order by created_at desc limit 1;
  if v_lead is null then
    select id into v_pipeline from public.pipelines where organization_id=v_org.id and is_default=true limit 1;
    select id into v_stage from public.pipeline_stages where pipeline_id=v_pipeline and stage_key='new' limit 1;
    insert into public.leads(organization_id,pipeline_id,stage_id,name,phone,whatsapp,source,status,interest)
    values(v_org.id,v_pipeline,v_stage,trim(p_name),v_phone,v_phone,'booking','new',v_service.name) returning id into v_lead;
    insert into public.events(organization_id,entity_type,entity_id,event_type,metadata) values(v_org.id,'lead',v_lead,'lead_created',jsonb_build_object('source','booking'));
  end if;

  insert into public.appointments(organization_id,lead_id,service_id,contact_name,contact_phone,starts_at,ends_at,source)
  values(v_org.id,v_lead,v_service.id,trim(p_name),v_phone,v_start,v_end,'public') returning id into v_id;
  insert into public.events(organization_id,entity_type,entity_id,event_type,metadata)
  values(v_org.id,'appointment',v_id,'appointment_created',jsonb_build_object('starts_at',v_start,'ends_at',v_end,'source','public','service',v_service.name));
  return v_id;
end; $$;
revoke all on function public.public_create_appointment(text,uuid,text,text,text) from public;
grant execute on function public.public_create_appointment(text,uuid,text,text,text) to anon,authenticated;

-- Notificações também passam a cobrir a agenda.
create or replace function public.fanout_event_notification()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_title text; v_body text; v_kind text:='info'; v_pref_key text:='leads';
begin
  case new.event_type
    when 'quote_request_received' then v_title:='Novo pedido de orçamento'; v_body:='Um novo contato chegou pelo site e precisa de atendimento.'; v_pref_key:='leads';
    when 'quote_response' then
      v_pref_key:='quotes';
      if coalesce(new.metadata->>'status','')='approved' then v_title:='Orçamento aprovado';v_body:='O cliente aprovou um orçamento.';v_kind:='success';
      elsif coalesce(new.metadata->>'status','')='change_requested' then v_title:='Cliente pediu alteração';v_body:='Um orçamento recebeu uma solicitação de alteração.';v_kind:='warning';
      elsif coalesce(new.metadata->>'status','')='rejected' then v_title:='Orçamento recusado';v_body:='Um cliente recusou um orçamento.';v_kind:='warning'; else return new; end if;
    when 'lead_converted_to_customer' then v_title:='Novo cliente';v_body:='Um lead foi convertido em cliente.';v_kind:='success';v_pref_key:='leads';
    when 'subscription_status_changed' then v_title:='Assinatura atualizada';v_body:='O status da assinatura mudou para '||coalesce(new.metadata->>'status','desconhecido')||'.';v_kind:='billing';v_pref_key:='billing';
    when 'appointment_created' then v_title:='Novo agendamento';v_pref_key:='appointments';v_body:=case when coalesce(new.metadata->>'source','')='public' then 'Um cliente realizou um agendamento pelo site.' else 'Um novo compromisso foi adicionado à agenda.' end;
    when 'appointment_status_changed' then v_title:='Agendamento atualizado';v_pref_key:='appointments';v_body:='O status de um agendamento foi alterado para '||coalesce(new.metadata->>'status','desconhecido')||'.';
    else return new;
  end case;
  insert into public.notifications(organization_id,user_id,source_event_id,kind,title,body,entity_type,entity_id)
  select new.organization_id,m.user_id,new.id,v_kind,v_title,v_body,new.entity_type,new.entity_id from public.organization_members m
  left join public.profiles p on p.id=m.user_id
  where m.organization_id=new.organization_id and m.status='active'
    and coalesce(p.notification_preferences->>v_pref_key,'true')='true' and (new.actor_user_id is null or m.user_id<>new.actor_user_id)
  on conflict(source_event_id,user_id) do nothing;
  return new;
end; $$;
revoke all on function public.fanout_event_notification() from public;
revoke all on function public.fanout_event_notification() from anon;
revoke all on function public.fanout_event_notification() from authenticated;

-- Dashboard passa a incluir agenda somente quando o entitlement estiver ativo.
create or replace function public.organization_dashboard_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_tz text; v_day_start timestamptz; v_day_end timestamptz; v_month_start timestamptz; v_previous_month_start timestamptz;
  v_crm boolean; v_quotes boolean; v_tasks boolean; v_appointments boolean;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then raise exception 'forbidden'; end if;
  select timezone into v_tz from public.organizations where id=p_organization_id; if v_tz is null then v_tz:='America/Sao_Paulo'; end if;
  v_day_start:=(date_trunc('day',now() at time zone v_tz) at time zone v_tz); v_day_end:=v_day_start+interval '1 day';
  v_month_start:=(date_trunc('month',now() at time zone v_tz) at time zone v_tz); v_previous_month_start:=v_month_start-interval '1 month';
  v_crm:=public.has_feature(p_organization_id,'crm'); v_quotes:=public.has_feature(p_organization_id,'quotes'); v_tasks:=public.has_feature(p_organization_id,'tasks'); v_appointments:=public.has_feature(p_organization_id,'appointments');
  return jsonb_build_object(
    'timezone',v_tz,
    'leads_today',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_day_start and created_at<v_day_end),
    'leads_month',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_month_start),
    'leads_previous_month',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_previous_month_start and created_at<v_month_start),
    'leads_total',(select count(*) from public.leads where organization_id=p_organization_id),
    'potential_value_cents',coalesce((select sum(potential_value_cents) from public.leads where organization_id=p_organization_id and status not in('won','lost')),0),
    'customers_total',case when v_crm then(select count(*) from public.customers where organization_id=p_organization_id) else null end,
    'followups_due',case when v_crm then(select count(*) from public.leads where organization_id=p_organization_id and next_contact_at is not null and next_contact_at<v_day_end and status not in('won','lost')) else null end,
    'quotes_pending',case when v_quotes then(select count(*) from public.quotes where organization_id=p_organization_id and status in('draft','sent','viewed','change_requested')) else null end,
    'quotes_month',case when v_quotes then(select count(*) from public.quotes where organization_id=p_organization_id and created_at>=v_month_start) else null end,
    'tasks_open',case when v_tasks then(select count(*) from public.tasks where organization_id=p_organization_id and status in('open','in_progress')) else null end,
    'tasks_overdue',case when v_tasks then(select count(*) from public.tasks where organization_id=p_organization_id and status in('open','in_progress') and due_at is not null and due_at<now()) else null end,
    'appointments_today',case when v_appointments then(select count(*) from public.appointments where organization_id=p_organization_id and status in('scheduled','confirmed') and starts_at>=v_day_start and starts_at<v_day_end) else null end
  );
end; $$;
revoke all on function public.organization_dashboard_summary(uuid) from public;
grant execute on function public.organization_dashboard_summary(uuid) to authenticated;

-- ============================================================================
-- 202608150012_automations_v1.sql
-- ============================================================================

-- 2026-08-15 — Fase 2: motor de automações event-driven com ações internas seguras.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"automations":true}'::jsonb
where code in ('professional','ai');

create table public.automations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 160),
  trigger_event text not null check (trigger_event in ('lead_created','quote_created','quote_link_enabled','quote_viewed','quote_response','appointment_created','appointment_status_changed')),
  conditions jsonb not null default '{}'::jsonb check (jsonb_typeof(conditions)='object'),
  actions jsonb not null check (jsonb_typeof(actions)='array' and jsonb_array_length(actions) between 1 and 10),
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index automations_org_trigger_idx on public.automations(organization_id,trigger_event,active);
create trigger automations_set_updated_at before update on public.automations for each row execute procedure public.set_updated_at();

create table public.automation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automations(id) on delete cascade,
  source_event_id uuid references public.events(id) on delete set null,
  status text not null check (status in ('executed','failed','ignored','dry_run')),
  reason text,
  actions_log jsonb not null default '[]'::jsonb check (jsonb_typeof(actions_log)='array'),
  created_at timestamptz not null default now(),
  unique(automation_id,source_event_id)
);
create index automation_runs_org_created_idx on public.automation_runs(organization_id,created_at desc);

alter table public.automations enable row level security;
alter table public.automation_runs enable row level security;
create policy automations_select_member on public.automations for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id,'automations'));
create policy automation_runs_select_member on public.automation_runs for select to authenticated using (public.is_org_member(organization_id) and public.has_feature(organization_id,'automations'));
-- Escrita é centralizada nas RPCs/trigger para validar JSON e preservar logs.

create or replace function public.save_automation(
  p_organization_id uuid,
  p_automation_id uuid,
  p_name text,
  p_trigger_event text,
  p_conditions jsonb,
  p_actions jsonb,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid; v_action jsonb; v_type text; v_condition_key text;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'automations') then raise exception 'forbidden'; end if;
  if char_length(trim(coalesce(p_name,'')))<2 then raise exception 'invalid name'; end if;
  if p_trigger_event not in('lead_created','quote_created','quote_link_enabled','quote_viewed','quote_response','appointment_created','appointment_status_changed') then raise exception 'invalid trigger'; end if;
  if jsonb_typeof(coalesce(p_conditions,'{}'::jsonb))<>'object' or jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions) not between 1 and 10 then raise exception 'invalid automation'; end if;
  for v_condition_key in select jsonb_object_keys(coalesce(p_conditions,'{}'::jsonb)) loop
    if v_condition_key not in('source','status','tag','min_value_cents') then raise exception 'unsupported condition'; end if;
  end loop;
  if p_conditions ? 'source' and (jsonb_typeof(p_conditions->'source')<>'string' or char_length(trim(p_conditions->>'source')) not between 1 and 80) then raise exception 'invalid source condition'; end if;
  if p_conditions ? 'status' and (jsonb_typeof(p_conditions->'status')<>'string' or char_length(trim(p_conditions->>'status')) not between 1 and 80) then raise exception 'invalid status condition'; end if;
  if p_conditions ? 'tag' and (jsonb_typeof(p_conditions->'tag')<>'string' or char_length(trim(p_conditions->>'tag')) not between 1 and 50) then raise exception 'invalid tag condition'; end if;
  if p_conditions ? 'min_value_cents' and (jsonb_typeof(p_conditions->'min_value_cents')<>'number' or (p_conditions->>'min_value_cents')::numeric < 0 or mod((p_conditions->>'min_value_cents')::numeric,1)<>0) then raise exception 'invalid minimum value condition'; end if;
  for v_action in select value from jsonb_array_elements(p_actions) loop
    v_type:=v_action->>'type';
    if v_type not in('create_task','add_tag','move_stage','notify_team') then raise exception 'unsupported action'; end if;
    if v_type='add_tag' and char_length(trim(coalesce(v_action->>'tag','')))<1 then raise exception 'invalid tag'; end if;
    if v_type='move_stage' and char_length(trim(coalesce(v_action->>'stage_key','')))<1 then raise exception 'invalid stage'; end if;
    if v_type='create_task' and char_length(trim(coalesce(v_action->>'title','')))<2 then raise exception 'invalid task'; end if;
    if v_type='notify_team' and char_length(trim(coalesce(v_action->>'title','')))<2 then raise exception 'invalid notification'; end if;
  end loop;
  if p_automation_id is null then
    insert into public.automations(organization_id,name,trigger_event,conditions,actions,active,created_by)
    values(p_organization_id,trim(p_name),p_trigger_event,coalesce(p_conditions,'{}'::jsonb),p_actions,p_active,auth.uid()) returning id into v_id;
  else
    update public.automations set name=trim(p_name),trigger_event=p_trigger_event,conditions=coalesce(p_conditions,'{}'::jsonb),actions=p_actions,active=p_active,updated_at=now()
    where id=p_automation_id and organization_id=p_organization_id returning id into v_id;
    if v_id is null then raise exception 'automation not found'; end if;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id)
  values(p_organization_id,auth.uid(),case when p_automation_id is null then 'automation.created' else 'automation.updated' end,'automation',v_id);
  return v_id;
end; $$;
revoke all on function public.save_automation(uuid,uuid,text,text,jsonb,jsonb,boolean) from public;
grant execute on function public.save_automation(uuid,uuid,text,text,jsonb,jsonb,boolean) to authenticated;

create or replace function public.set_automation_active(p_organization_id uuid,p_automation_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'automations') then raise exception 'forbidden'; end if;
  update public.automations set active=p_active,updated_at=now() where id=p_automation_id and organization_id=p_organization_id;
  if not found then raise exception 'automation not found'; end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_organization_id,auth.uid(),'automation.active_changed','automation',p_automation_id,jsonb_build_object('active',p_active));
end; $$;
revoke all on function public.set_automation_active(uuid,uuid,boolean) from public;
grant execute on function public.set_automation_active(uuid,uuid,boolean) to authenticated;

create or replace function public.dry_run_automation(p_organization_id uuid,p_automation_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_auto public.automations%rowtype; v_run uuid;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'automations') then raise exception 'forbidden'; end if;
  select * into v_auto from public.automations where id=p_automation_id and organization_id=p_organization_id;
  if v_auto.id is null then raise exception 'automation not found'; end if;
  insert into public.automation_runs(organization_id,automation_id,status,reason,actions_log)
  values(p_organization_id,v_auto.id,'dry_run','Configuração validada; nenhuma ação foi executada.',v_auto.actions) returning id into v_run;
  return jsonb_build_object('run_id',v_run,'trigger_event',v_auto.trigger_event,'conditions',v_auto.conditions,'actions',v_auto.actions,'executed',false);
end; $$;
revoke all on function public.dry_run_automation(uuid,uuid) from public;
grant execute on function public.dry_run_automation(uuid,uuid) to authenticated;

create or replace function public.process_automation_event()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_auto public.automations%rowtype; v_conditions jsonb; v_action jsonb; v_type text; v_match boolean; v_reason text;
  v_lead public.leads%rowtype; v_quote public.quotes%rowtype; v_appointment public.appointments%rowtype;
  v_lead_id uuid; v_customer_id uuid; v_log jsonb; v_status text; v_failed boolean; v_assigned uuid; v_stage uuid; v_priority text; v_due integer; v_min_value bigint;
begin
  if not public.organization_has_entitlement(new.organization_id,'automations') then return new; end if;
  for v_auto in select * from public.automations a where a.organization_id=new.organization_id and a.active=true and a.trigger_event=new.event_type order by a.created_at loop
    if exists(select 1 from public.automation_runs r where r.automation_id=v_auto.id and r.source_event_id=new.id) then continue; end if;
    v_conditions:=coalesce(v_auto.conditions,'{}'::jsonb); v_match:=true; v_reason:=null; v_lead_id:=null; v_customer_id:=null;
    if new.entity_type='lead' and new.entity_id is not null then select * into v_lead from public.leads where id=new.entity_id and organization_id=new.organization_id; v_lead_id:=v_lead.id; end if;
    if new.entity_type='quote' and new.entity_id is not null then select * into v_quote from public.quotes where id=new.entity_id and organization_id=new.organization_id; v_lead_id:=v_quote.lead_id; v_customer_id:=v_quote.customer_id; if v_lead_id is not null then select * into v_lead from public.leads where id=v_lead_id; end if; end if;
    if new.entity_type='appointment' and new.entity_id is not null then select * into v_appointment from public.appointments where id=new.entity_id and organization_id=new.organization_id; v_lead_id:=v_appointment.lead_id; v_customer_id:=v_appointment.customer_id; if v_lead_id is not null then select * into v_lead from public.leads where id=v_lead_id; end if; end if;

    if v_conditions ? 'source' then
      if new.entity_type='appointment' then v_match:=coalesce(new.metadata->>'source','')=v_conditions->>'source';
      elsif v_lead.id is not null then v_match:=coalesce(v_lead.source,'')=v_conditions->>'source'; else v_match:=false; end if;
      if not v_match then v_reason:='source condition not met'; end if;
    end if;
    if v_match and v_conditions ? 'status' then
      if new.entity_type='quote' then v_match:=coalesce(new.metadata->>'status',v_quote.status,'')=v_conditions->>'status';
      elsif new.entity_type='appointment' then v_match:=coalesce(new.metadata->>'status',v_appointment.status,'')=v_conditions->>'status';
      elsif v_lead.id is not null then v_match:=coalesce(v_lead.status,'')=v_conditions->>'status'; else v_match:=false; end if;
      if not v_match then v_reason:='status condition not met'; end if;
    end if;
    if v_match and v_conditions ? 'tag' then
      v_match:=v_lead.id is not null and (v_conditions->>'tag')=any(coalesce(v_lead.tags,'{}'::text[])); if not v_match then v_reason:='tag condition not met'; end if;
    end if;
    if v_match and v_conditions ? 'min_value_cents' then
      begin
        v_min_value:=greatest(0,(v_conditions->>'min_value_cents')::bigint);
        if new.entity_type='quote' then v_match:=coalesce(v_quote.total_cents,0)>=v_min_value;
        elsif v_lead.id is not null then v_match:=coalesce(v_lead.potential_value_cents,0)>=v_min_value; else v_match:=false; end if;
        if not v_match then v_reason:='minimum value condition not met'; end if;
      exception when others then
        v_match:=false; v_reason:='invalid minimum value condition';
      end;
    end if;

    if not v_match then
      insert into public.automation_runs(organization_id,automation_id,source_event_id,status,reason)
      values(new.organization_id,v_auto.id,new.id,'ignored',coalesce(v_reason,'conditions not met')) on conflict(automation_id,source_event_id) do nothing;
      continue;
    end if;

    v_log:='[]'::jsonb; v_failed:=false;
    for v_action in select value from jsonb_array_elements(v_auto.actions) loop
      v_type:=v_action->>'type';
      begin
        if v_type='create_task' then
          v_priority:=coalesce(nullif(v_action->>'priority',''),'medium'); if v_priority not in('low','medium','high','urgent') then v_priority:='medium'; end if;
          begin v_due:=greatest(0,least(coalesce((v_action->>'due_minutes')::integer,0),43200)); exception when others then v_due:=0; end;
          v_assigned:=null; if coalesce(v_action->>'assigned_to','')<>'' then begin v_assigned:=(v_action->>'assigned_to')::uuid; exception when others then v_assigned:=null; end; end if;
          if v_assigned is not null and not exists(select 1 from public.organization_members where organization_id=new.organization_id and user_id=v_assigned and status='active') then v_assigned:=null; end if;
          insert into public.tasks(organization_id,lead_id,customer_id,title,description,assigned_to,priority,due_at,status,created_by)
          values(new.organization_id,v_lead_id,v_customer_id,left(trim(v_action->>'title'),200),nullif(left(coalesce(v_action->>'description',''),2000),''),v_assigned,v_priority,case when v_due>0 then now()+make_interval(mins=>v_due) else null end,'open',v_auto.created_by);
        elsif v_type='add_tag' then
          if v_lead_id is null then raise exception 'lead unavailable'; end if;
          update public.leads set tags=array(select distinct x from unnest(tags||array[left(trim(v_action->>'tag'),50)]) x),updated_at=now() where id=v_lead_id and organization_id=new.organization_id;
        elsif v_type='move_stage' then
          if v_lead_id is null then raise exception 'lead unavailable'; end if;
          select ps.id into v_stage from public.pipeline_stages ps join public.leads l on l.pipeline_id=ps.pipeline_id where l.id=v_lead_id and l.organization_id=new.organization_id and ps.stage_key=v_action->>'stage_key' limit 1;
          if v_stage is null then raise exception 'stage unavailable'; end if;
          update public.leads set stage_id=v_stage,status=case when (v_action->>'stage_key')='won' then 'won' when (v_action->>'stage_key')='lost' then 'lost' else status end,updated_at=now() where id=v_lead_id;
        elsif v_type='notify_team' then
          insert into public.notifications(organization_id,user_id,kind,title,body,entity_type,entity_id)
          select new.organization_id,m.user_id,'info',left(trim(v_action->>'title'),160),nullif(left(coalesce(v_action->>'body',''),1000),''),new.entity_type,new.entity_id
          from public.organization_members m where m.organization_id=new.organization_id and m.status='active';
        else
          raise exception 'unsupported action';
        end if;
        v_log:=v_log||jsonb_build_array(jsonb_build_object('type',v_type,'status','executed'));
      exception when others then
        v_failed:=true; v_log:=v_log||jsonb_build_array(jsonb_build_object('type',coalesce(v_type,'unknown'),'status','failed','reason',left(sqlerrm,300)));
      end;
    end loop;
    v_status:=case when v_failed then 'failed' else 'executed' end;
    insert into public.automation_runs(organization_id,automation_id,source_event_id,status,reason,actions_log)
    values(new.organization_id,v_auto.id,new.id,v_status,case when v_failed then 'Uma ou mais ações falharam.' else null end,v_log)
    on conflict(automation_id,source_event_id) do nothing;
  end loop;
  return new;
end; $$;
revoke all on function public.process_automation_event() from public;
revoke all on function public.process_automation_event() from anon;
revoke all on function public.process_automation_event() from authenticated;

create trigger events_process_automations
after insert on public.events
for each row execute procedure public.process_automation_event();

-- ============================================================================
-- 202608150013_analytics_utm.sql
-- ============================================================================

-- 2026-08-15 — Analytics próprio, UTM e relatórios baseados apenas em dados reais.

alter table public.leads
  add column if not exists utm_source text,
  add column if not exists utm_medium text,
  add column if not exists utm_campaign text,
  add column if not exists utm_content text,
  add column if not exists utm_term text;

create table public.site_visits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  visitor_hash text not null check (char_length(visitor_hash) between 32 and 128),
  pathname text not null default '/',
  referrer_host text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  created_at timestamptz not null default now()
);

create index site_visits_org_created_idx on public.site_visits(organization_id, created_at desc);
create index site_visits_org_visitor_idx on public.site_visits(organization_id, visitor_hash, created_at desc);

alter table public.site_visits enable row level security;
create policy site_visits_select_analytics on public.site_visits
for select to authenticated
using (public.is_org_member(organization_id) and public.has_feature(organization_id,'analytics'));
-- Sem policy de INSERT: visitas entram apenas pela RPC server-side/service role.

create or replace function public.record_site_visit(
  p_slug text,
  p_visitor_hash text,
  p_pathname text,
  p_referrer_host text,
  p_utm_source text,
  p_utm_medium text,
  p_utm_campaign text,
  p_utm_content text,
  p_utm_term text
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_org uuid;
begin
  if char_length(trim(coalesce(p_visitor_hash,''))) not between 32 and 128 then return false; end if;
  select o.id into v_org
  from public.organizations o
  join public.site_configs sc on sc.organization_id=o.id and sc.status='published'
  where o.slug=trim(p_slug) and o.status='active'
    and public.organization_has_entitlement(o.id,'analytics')
  limit 1;
  if v_org is null then return false; end if;

  -- Deduplica a mesma página/visitante por 30 minutos. Não armazena IP nem user-agent brutos.
  if exists(
    select 1 from public.site_visits sv
    where sv.organization_id=v_org
      and sv.visitor_hash=p_visitor_hash
      and sv.pathname=left(coalesce(nullif(trim(p_pathname),''),'/'),300)
      and sv.created_at>now()-interval '30 minutes'
  ) then return true; end if;

  insert into public.site_visits(
    organization_id,visitor_hash,pathname,referrer_host,
    utm_source,utm_medium,utm_campaign,utm_content,utm_term
  ) values (
    v_org,p_visitor_hash,left(coalesce(nullif(trim(p_pathname),''),'/'),300),nullif(left(trim(coalesce(p_referrer_host,'')),200),''),
    nullif(left(trim(coalesce(p_utm_source,'')),120),''),nullif(left(trim(coalesce(p_utm_medium,'')),120),''),
    nullif(left(trim(coalesce(p_utm_campaign,'')),160),''),nullif(left(trim(coalesce(p_utm_content,'')),160),''),
    nullif(left(trim(coalesce(p_utm_term,'')),160),'')
  );
  return true;
end; $$;
revoke all on function public.record_site_visit(text,text,text,text,text,text,text,text,text) from public;
revoke all on function public.record_site_visit(text,text,text,text,text,text,text,text,text) from anon;
revoke all on function public.record_site_visit(text,text,text,text,text,text,text,text,text) from authenticated;
grant execute on function public.record_site_visit(text,text,text,text,text,text,text,text,text) to service_role;

-- Overload do formulário público para associar UTM ao lead sem quebrar clientes antigos da RPC de 6 argumentos.
create or replace function public.public_create_quote_request(
  p_organization_slug text,
  p_name text,
  p_whatsapp text,
  p_email text,
  p_description text,
  p_honeypot text,
  p_utm_source text,
  p_utm_medium text,
  p_utm_campaign text,
  p_utm_content text,
  p_utm_term text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_request uuid; v_lead uuid;
begin
  v_request:=public.public_create_quote_request(
    p_organization_slug,p_name,p_whatsapp,p_email,p_description,p_honeypot
  );
  select qr.lead_id into v_lead from public.quote_requests qr where qr.id=v_request;
  if v_lead is not null then
    update public.leads set
      utm_source=coalesce(nullif(left(trim(coalesce(p_utm_source,'')),120),''),utm_source),
      utm_medium=coalesce(nullif(left(trim(coalesce(p_utm_medium,'')),120),''),utm_medium),
      utm_campaign=coalesce(nullif(left(trim(coalesce(p_utm_campaign,'')),160),''),utm_campaign),
      utm_content=coalesce(nullif(left(trim(coalesce(p_utm_content,'')),160),''),utm_content),
      utm_term=coalesce(nullif(left(trim(coalesce(p_utm_term,'')),160),''),utm_term),
      updated_at=now()
    where id=v_lead;
  end if;
  return v_request;
end; $$;
revoke all on function public.public_create_quote_request(text,text,text,text,text,text,text,text,text,text,text) from public;
grant execute on function public.public_create_quote_request(text,text,text,text,text,text,text,text,text,text,text) to anon,authenticated;

create or replace function public.organization_analytics_summary(p_organization_id uuid,p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_days integer:=least(greatest(coalesce(p_days,30),7),365);
  v_since timestamptz;
  v_previous_since timestamptz;
  v_tz text;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) or not public.has_feature(p_organization_id,'analytics') then raise exception 'forbidden'; end if;
  select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;
  v_since:=now()-make_interval(days=>v_days);
  v_previous_since:=v_since-make_interval(days=>v_days);

  select jsonb_build_object(
    'days',v_days,
    'timezone',v_tz,
    'visitors',(select count(distinct visitor_hash) from public.site_visits where organization_id=p_organization_id and created_at>=v_since),
    'page_views',(select count(*) from public.site_visits where organization_id=p_organization_id and created_at>=v_since),
    'leads',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_since),
    'site_leads',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_since and source='site'),
    'previous_leads',(select count(*) from public.leads where organization_id=p_organization_id and created_at>=v_previous_since and created_at<v_since),
    'customers',(select count(*) from public.customers where organization_id=p_organization_id and created_at>=v_since),
    'quotes',(select count(*) from public.quotes where organization_id=p_organization_id and created_at>=v_since),
    'approved_quotes',(select count(*) from public.quotes where organization_id=p_organization_id and status='approved' and coalesce(accepted_at,updated_at)>=v_since),
    'sales_cents',coalesce((select sum(total_cents) from public.quotes where organization_id=p_organization_id and status='approved' and coalesce(accepted_at,updated_at)>=v_since),0),
    'previous_sales_cents',coalesce((select sum(total_cents) from public.quotes where organization_id=p_organization_id and status='approved' and coalesce(accepted_at,updated_at)>=v_previous_since and coalesce(accepted_at,updated_at)<v_since),0),
    'average_ticket_cents',coalesce((select round(avg(total_cents))::bigint from public.quotes where organization_id=p_organization_id and status='approved' and coalesce(accepted_at,updated_at)>=v_since),0),
    'appointments',case when public.has_feature(p_organization_id,'appointments') then (select count(*) from public.appointments where organization_id=p_organization_id and created_at>=v_since) else null end,
    'lead_sources',coalesce((select jsonb_agg(jsonb_build_object('label',source,'count',qty) order by qty desc,label) from (select coalesce(nullif(source,''),'Sem origem') label,count(*) qty from public.leads where organization_id=p_organization_id and created_at>=v_since group by 1 order by 2 desc limit 12) s),'[]'::jsonb),
    'utm_sources',coalesce((select jsonb_agg(jsonb_build_object('label',label,'count',qty) order by qty desc,label) from (select coalesce(nullif(utm_source,''),'Sem UTM') label,count(*) qty from public.leads where organization_id=p_organization_id and created_at>=v_since group by 1 order by 2 desc limit 12) s),'[]'::jsonb),
    'utm_mediums',coalesce((select jsonb_agg(jsonb_build_object('label',label,'count',qty) order by qty desc,label) from (select coalesce(nullif(utm_medium,''),'Sem canal') label,count(*) qty from public.leads where organization_id=p_organization_id and created_at>=v_since group by 1 order by 2 desc limit 12) s),'[]'::jsonb),
    'top_items',coalesce((select jsonb_agg(jsonb_build_object('type',item_type,'description',description,'quantity',quantity,'revenue_cents',revenue_cents) order by revenue_cents desc) from (select qi.item_type,left(qi.description,120) description,sum(qi.quantity) quantity,sum(qi.total_cents) revenue_cents from public.quote_items qi join public.quotes q on q.id=qi.quote_id and q.organization_id=qi.organization_id where qi.organization_id=p_organization_id and q.status='approved' and coalesce(q.accepted_at,q.updated_at)>=v_since group by qi.item_type,left(qi.description,120) order by 4 desc limit 10) i),'[]'::jsonb),
    'daily',coalesce((select jsonb_agg(jsonb_build_object('date',d.day_value,'visits',d.visits,'leads',d.leads,'quotes',d.quotes,'sales_cents',d.sales_cents) order by d.day_value) from (
      select g::date as day_value,
        (select count(*) from public.site_visits sv where sv.organization_id=p_organization_id and (sv.created_at at time zone v_tz)::date=g::date) visits,
        (select count(*) from public.leads l where l.organization_id=p_organization_id and (l.created_at at time zone v_tz)::date=g::date) leads,
        (select count(*) from public.quotes q where q.organization_id=p_organization_id and (q.created_at at time zone v_tz)::date=g::date) quotes,
        coalesce((select sum(q.total_cents) from public.quotes q where q.organization_id=p_organization_id and q.status='approved' and (coalesce(q.accepted_at,q.updated_at) at time zone v_tz)::date=g::date),0) sales_cents
      from generate_series((now() at time zone v_tz)::date-(v_days-1),(now() at time zone v_tz)::date,interval '1 day') g
    ) d),'[]'::jsonb)
  ) into v_result;
  return v_result;
end; $$;
revoke all on function public.organization_analytics_summary(uuid,integer) from public;
grant execute on function public.organization_analytics_summary(uuid,integer) to authenticated;

-- ============================================================================
-- 202608150014_ai_usage_provider.sql
-- ============================================================================

-- 2026-08-15 — IA desacoplada, consumo auditável e limites mensais.

update public.plans
set entitlements=coalesce(entitlements,'{}'::jsonb)||'{"ai_quotes":true}'::jsonb,
    limits=coalesce(limits,'{}'::jsonb)||'{"ai_requests_per_month":500,"ai_tokens_per_month":2000000}'::jsonb
where code='ai';

create table public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  resource text not null check(resource in ('assistant','lead_response','copy','quote','insights')),
  status text not null default 'pending' check(status in ('pending','succeeded','failed')),
  provider text,
  model text,
  provider_request_id text,
  input_tokens integer not null default 0 check(input_tokens>=0),
  output_tokens integer not null default 0 check(output_tokens>=0),
  total_tokens integer not null default 0 check(total_tokens>=0),
  estimated_cost_usd_micros bigint check(estimated_cost_usd_micros is null or estimated_cost_usd_micros>=0),
  error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index ai_usage_org_month_idx on public.ai_usage(organization_id,created_at desc);
create index ai_usage_user_month_idx on public.ai_usage(user_id,created_at desc);
alter table public.ai_usage enable row level security;
create policy ai_usage_select_member on public.ai_usage for select to authenticated
using(public.is_org_member(organization_id) and public.organization_has_entitlement(organization_id,'ai_assistant'));
-- Escrita somente pela RPC de reserva e pelo backend service-role após a chamada do provider.

create or replace function public.begin_ai_usage(p_organization_id uuid,p_resource text)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_feature text;
  v_tz text;
  v_month_start timestamptz;
  v_request_limit integer;
  v_token_limit integer;
  v_requests integer;
  v_tokens bigint;
  v_id uuid;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) then raise exception 'forbidden'; end if;
  v_feature:=case p_resource
    when 'assistant' then 'ai_assistant'
    when 'lead_response' then 'ai_responses'
    when 'copy' then 'ai_copy'
    when 'quote' then 'ai_quotes'
    when 'insights' then 'ai_insights'
    else null end;
  if v_feature is null or not public.has_feature(p_organization_id,v_feature) then raise exception 'feature unavailable'; end if;
  -- Serializa reservas do mesmo tenant para evitar ultrapassar limites por concorrência.
  perform pg_advisory_xact_lock(hashtext(p_organization_id::text)::bigint);
  select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;
  v_month_start:=(date_trunc('month',now() at time zone v_tz) at time zone v_tz);
  v_request_limit:=coalesce(public.feature_limit(p_organization_id,'ai_requests_per_month'),500);
  v_token_limit:=coalesce(public.feature_limit(p_organization_id,'ai_tokens_per_month'),2000000);
  select count(*),coalesce(sum(total_tokens),0) into v_requests,v_tokens
  from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start;
  if v_request_limit<=0 or v_requests>=v_request_limit then raise exception 'ai request limit reached'; end if;
  if v_token_limit<=0 or v_tokens>=v_token_limit then raise exception 'ai token limit reached'; end if;
  insert into public.ai_usage(organization_id,user_id,resource) values(p_organization_id,auth.uid(),p_resource) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.begin_ai_usage(uuid,text) from public;
grant execute on function public.begin_ai_usage(uuid,text) to authenticated;

create or replace function public.ai_usage_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_tz text;v_month_start timestamptz;v_req integer;v_tok integer;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) or not public.organization_has_entitlement(p_organization_id,'ai_assistant') then raise exception 'forbidden';end if;
  select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;
  v_month_start:=(date_trunc('month',now() at time zone v_tz) at time zone v_tz);
  v_req:=coalesce(public.feature_limit(p_organization_id,'ai_requests_per_month'),500);v_tok:=coalesce(public.feature_limit(p_organization_id,'ai_tokens_per_month'),2000000);
  return jsonb_build_object(
    'request_limit',v_req,'token_limit',v_tok,
    'requests_used',(select count(*) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start),
    'tokens_used',coalesce((select sum(total_tokens) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start),0),
    'estimated_cost_usd_micros',coalesce((select sum(estimated_cost_usd_micros) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start),0),
    'successful_requests',(select count(*) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start and status='succeeded'),
    'failed_requests',(select count(*) from public.ai_usage where organization_id=p_organization_id and created_at>=v_month_start and status='failed')
  );
end; $$;
revoke all on function public.ai_usage_summary(uuid) from public;
grant execute on function public.ai_usage_summary(uuid) to authenticated;

-- ============================================================================
-- 202608150015_calendar_templates.sql
-- ============================================================================

-- 2026-08-15 — Visualizações de calendário e aplicação transacional de templates de site.

create or replace function public.appointments_calendar(
  p_organization_id uuid,
  p_date date,
  p_view text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_tz text;
  v_view text:=lower(coalesce(p_view,'week'));
  v_anchor date:=coalesce(p_date,(now() at time zone 'America/Sao_Paulo')::date);
  v_start_date date;
  v_end_date date;
  v_start timestamptz;
  v_end timestamptz;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden'; end if;
  if v_view not in('day','week','month') then v_view:='week'; end if;
  select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;
  if p_date is null then v_anchor:=(now() at time zone v_tz)::date; end if;
  if v_view='day' then v_start_date:=v_anchor;v_end_date:=v_anchor+1;
  elsif v_view='week' then v_start_date:=date_trunc('week',v_anchor::timestamp)::date;v_end_date:=v_start_date+7;
  else v_start_date:=date_trunc('month',v_anchor::timestamp)::date;v_end_date:=(v_start_date+interval '1 month')::date;end if;
  v_start:=(v_start_date::timestamp at time zone v_tz);v_end:=(v_end_date::timestamp at time zone v_tz);
  return jsonb_build_object(
    'view',v_view,'timezone',v_tz,'anchor',v_anchor,'start_date',v_start_date,'end_date',(v_end_date-1),
    'appointments',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'starts_at',a.starts_at,'ends_at',a.ends_at,'status',a.status,'source',a.source,
      'name',coalesce(c.name,l.name,a.contact_name,'Contato'),'service',s.name,'professional',p.full_name
    ) order by a.starts_at)
    from public.appointments a
    left join public.customers c on c.id=a.customer_id and c.organization_id=a.organization_id
    left join public.leads l on l.id=a.lead_id and l.organization_id=a.organization_id
    left join public.services s on s.id=a.service_id and s.organization_id=a.organization_id
    left join public.profiles p on p.id=a.professional_user_id
    where a.organization_id=p_organization_id and a.starts_at<v_end and a.ends_at>v_start),'[]'::jsonb)
  );
end; $$;
revoke all on function public.appointments_calendar(uuid,date,text) from public;
grant execute on function public.appointments_calendar(uuid,date,text) to authenticated;

create or replace function public.apply_site_template(
  p_organization_id uuid,
  p_template_key text,
  p_template jsonb
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_section jsonb;v_type text;v_site uuid;v_color text;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'site') then raise exception 'forbidden';end if;
  if jsonb_typeof(p_template)<>'object' or octet_length(p_template::text)>30000 then raise exception 'invalid template';end if;
  if jsonb_typeof(p_template->'sections')<>'array' or jsonb_array_length(p_template->'sections') not between 1 and 10 then raise exception 'invalid sections';end if;
  select id into v_site from public.site_configs where organization_id=p_organization_id;if v_site is null then raise exception 'site not found';end if;
  v_color:=coalesce(p_template->>'primary_color','#2457d6');if v_color!~'^#[0-9A-Fa-f]{6}$' then v_color:='#2457d6';end if;
  update public.site_configs set headline=nullif(left(trim(coalesce(p_template->>'headline','')),180),''),subheadline=nullif(left(trim(coalesce(p_template->>'subheadline','')),320),''),about=nullif(left(trim(coalesce(p_template->>'about','')),3000),''),primary_color=v_color,updated_at=now() where organization_id=p_organization_id;
  for v_section in select value from jsonb_array_elements(p_template->'sections') loop
    v_type:=v_section->>'type';
    if v_type not in('hero','about','services','products','contact','cta') then raise exception 'unsupported section';end if;
    if jsonb_typeof(coalesce(v_section->'content','{}'::jsonb))<>'object' or octet_length(coalesce(v_section->'content','{}'::jsonb)::text)>8000 then raise exception 'invalid section content';end if;
    update public.site_sections set enabled=coalesce((v_section->>'enabled')::boolean,true),sort_order=greatest(1,least(coalesce((v_section->>'sort_order')::integer,100),1000)),content=coalesce(v_section->'content','{}'::jsonb),updated_at=now() where organization_id=p_organization_id and site_config_id=v_site and section_type=v_type;
  end loop;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_organization_id,auth.uid(),'site.template_applied','site_config',v_site,jsonb_build_object('template',left(coalesce(p_template_key,'custom'),80)));
end; $$;
revoke all on function public.apply_site_template(uuid,text,jsonb) from public;
grant execute on function public.apply_site_template(uuid,text,jsonb) to authenticated;

-- ============================================================================
-- 202608150016_admin_ai_usage.sql
-- ============================================================================

-- Visão agregada de consumo de IA para administradores da plataforma.
-- Não expõe prompts, respostas ou dados de leads; apenas métricas operacionais.
create or replace function public.admin_ai_usage_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_month_start timestamptz := date_trunc('month', now());
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'forbidden';
  end if;

  return jsonb_build_object(
    'period_start', v_month_start,
    'requests', (select count(*) from public.ai_usage where created_at >= v_month_start),
    'successful_requests', (select count(*) from public.ai_usage where created_at >= v_month_start and status = 'succeeded'),
    'failed_requests', (select count(*) from public.ai_usage where created_at >= v_month_start and status = 'failed'),
    'tokens', coalesce((select sum(total_tokens) from public.ai_usage where created_at >= v_month_start), 0),
    'estimated_cost_usd_micros', coalesce((select sum(estimated_cost_usd_micros) from public.ai_usage where created_at >= v_month_start), 0),
    'organizations_using_ai', (select count(distinct organization_id) from public.ai_usage where created_at >= v_month_start),
    'resources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'resource', resource,
        'requests', requests,
        'tokens', tokens,
        'estimated_cost_usd_micros', estimated_cost_usd_micros
      ) order by requests desc, resource)
      from (
        select
          resource,
          count(*)::bigint as requests,
          coalesce(sum(total_tokens), 0)::bigint as tokens,
          coalesce(sum(estimated_cost_usd_micros), 0)::bigint as estimated_cost_usd_micros
        from public.ai_usage
        where created_at >= v_month_start
        group by resource
      ) r
    ), '[]'::jsonb),
    'organizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organization_id', organization_id,
        'organization_name', organization_name,
        'requests', requests,
        'successful_requests', successful_requests,
        'failed_requests', failed_requests,
        'tokens', tokens,
        'estimated_cost_usd_micros', estimated_cost_usd_micros
      ) order by requests desc, organization_name)
      from (
        select
          u.organization_id,
          o.name as organization_name,
          count(*)::bigint as requests,
          count(*) filter (where u.status = 'succeeded')::bigint as successful_requests,
          count(*) filter (where u.status = 'failed')::bigint as failed_requests,
          coalesce(sum(u.total_tokens), 0)::bigint as tokens,
          coalesce(sum(u.estimated_cost_usd_micros), 0)::bigint as estimated_cost_usd_micros
        from public.ai_usage u
        join public.organizations o on o.id = u.organization_id
        where u.created_at >= v_month_start
        group by u.organization_id, o.name
        order by count(*) desc, o.name
        limit 50
      ) org_usage
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_ai_usage_summary() from public;
grant execute on function public.admin_ai_usage_summary() to authenticated;

-- ============================================================================
-- 202608150017_temporal_automations.sql
-- ============================================================================

-- 2026-08-15 — Automações temporais: lead sem contato, cliente inativo e data específica.
-- O scheduler é executado por Supabase Cron/pg_cron chamando run_temporal_automations.

alter table public.automations drop constraint if exists automations_trigger_event_check;
alter table public.automations add constraint automations_trigger_event_check check (
  trigger_event in (
    'lead_created','quote_created','quote_link_enabled','quote_viewed','quote_response',
    'appointment_created','appointment_status_changed',
    'lead_no_response','customer_inactive','date_specific'
  )
);

alter table public.automation_runs add column if not exists dedupe_key text;
create unique index if not exists automation_runs_automation_dedupe_uidx
  on public.automation_runs(automation_id,dedupe_key)
  where dedupe_key is not null;

-- Mantém a mesma assinatura usada pelo aplicativo, ampliando a validação para gatilhos temporais.
create or replace function public.save_automation(
  p_organization_id uuid,
  p_automation_id uuid,
  p_name text,
  p_trigger_event text,
  p_conditions jsonb,
  p_actions jsonb,
  p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid; v_action jsonb; v_type text; v_condition_key text;
  v_after integer; v_days integer; v_run_local timestamp; v_timezone text;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin']) or not public.has_feature(p_organization_id,'automations') then raise exception 'forbidden'; end if;
  if char_length(trim(coalesce(p_name,'')))<2 then raise exception 'invalid name'; end if;
  if p_trigger_event not in(
    'lead_created','quote_created','quote_link_enabled','quote_viewed','quote_response',
    'appointment_created','appointment_status_changed','lead_no_response','customer_inactive','date_specific'
  ) then raise exception 'invalid trigger'; end if;
  if jsonb_typeof(coalesce(p_conditions,'{}'::jsonb))<>'object' or jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions) not between 1 and 10 then raise exception 'invalid automation'; end if;

  for v_condition_key in select jsonb_object_keys(coalesce(p_conditions,'{}'::jsonb)) loop
    if v_condition_key not in('source','status','tag','min_value_cents','after_minutes','inactive_days','run_at_local') then raise exception 'unsupported condition'; end if;
  end loop;
  if p_conditions ? 'source' and (jsonb_typeof(p_conditions->'source')<>'string' or char_length(trim(p_conditions->>'source')) not between 1 and 80) then raise exception 'invalid source condition'; end if;
  if p_conditions ? 'status' and (jsonb_typeof(p_conditions->'status')<>'string' or char_length(trim(p_conditions->>'status')) not between 1 and 80) then raise exception 'invalid status condition'; end if;
  if p_conditions ? 'tag' and (jsonb_typeof(p_conditions->'tag')<>'string' or char_length(trim(p_conditions->>'tag')) not between 1 and 50) then raise exception 'invalid tag condition'; end if;
  if p_conditions ? 'min_value_cents' and (jsonb_typeof(p_conditions->'min_value_cents')<>'number' or (p_conditions->>'min_value_cents')::numeric < 0 or mod((p_conditions->>'min_value_cents')::numeric,1)<>0) then raise exception 'invalid minimum value condition'; end if;

  if p_trigger_event='lead_no_response' then
    begin v_after:=(p_conditions->>'after_minutes')::integer; exception when others then v_after:=null; end;
    if v_after is null or v_after not between 15 and 525600 then raise exception 'invalid response interval'; end if;
    if p_conditions ? 'inactive_days' or p_conditions ? 'run_at_local' then raise exception 'invalid temporal condition'; end if;
  elsif p_trigger_event='customer_inactive' then
    begin v_days:=(p_conditions->>'inactive_days')::integer; exception when others then v_days:=null; end;
    if v_days is null or v_days not between 1 and 3650 then raise exception 'invalid inactivity interval'; end if;
    if p_conditions ? 'source' or p_conditions ? 'status' or p_conditions ? 'tag' or p_conditions ? 'min_value_cents' or p_conditions ? 'after_minutes' or p_conditions ? 'run_at_local' then raise exception 'invalid customer inactivity condition'; end if;
  elsif p_trigger_event='date_specific' then
    if jsonb_typeof(p_conditions->'run_at_local')<>'string' then raise exception 'invalid scheduled date'; end if;
    begin v_run_local:=(p_conditions->>'run_at_local')::timestamp; exception when others then v_run_local:=null; end;
    select timezone into v_timezone from public.organizations where id=p_organization_id;
    if v_run_local is null or (v_run_local at time zone coalesce(v_timezone,'America/Sao_Paulo')) <= now() then raise exception 'scheduled date must be in the future'; end if;
    if p_conditions ? 'source' or p_conditions ? 'status' or p_conditions ? 'tag' or p_conditions ? 'min_value_cents' or p_conditions ? 'after_minutes' or p_conditions ? 'inactive_days' then raise exception 'invalid scheduled condition'; end if;
  elsif p_conditions ? 'after_minutes' or p_conditions ? 'inactive_days' or p_conditions ? 'run_at_local' then
    raise exception 'temporal condition requires temporal trigger';
  end if;

  for v_action in select value from jsonb_array_elements(p_actions) loop
    v_type:=v_action->>'type';
    if v_type not in('create_task','add_tag','move_stage','notify_team') then raise exception 'unsupported action'; end if;
    if v_type='add_tag' and char_length(trim(coalesce(v_action->>'tag','')))<1 then raise exception 'invalid tag'; end if;
    if v_type='move_stage' and char_length(trim(coalesce(v_action->>'stage_key','')))<1 then raise exception 'invalid stage'; end if;
    if v_type='create_task' and char_length(trim(coalesce(v_action->>'title','')))<2 then raise exception 'invalid task'; end if;
    if v_type='notify_team' and char_length(trim(coalesce(v_action->>'title','')))<2 then raise exception 'invalid notification'; end if;
    if p_trigger_event in('customer_inactive','date_specific') and v_type in('add_tag','move_stage') then raise exception 'action requires lead context'; end if;
  end loop;

  if p_automation_id is null then
    insert into public.automations(organization_id,name,trigger_event,conditions,actions,active,created_by)
    values(p_organization_id,trim(p_name),p_trigger_event,coalesce(p_conditions,'{}'::jsonb),p_actions,p_active,auth.uid()) returning id into v_id;
  else
    update public.automations set name=trim(p_name),trigger_event=p_trigger_event,conditions=coalesce(p_conditions,'{}'::jsonb),actions=p_actions,active=p_active,updated_at=now()
    where id=p_automation_id and organization_id=p_organization_id returning id into v_id;
    if v_id is null then raise exception 'automation not found'; end if;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id)
  values(p_organization_id,auth.uid(),case when p_automation_id is null then 'automation.created' else 'automation.updated' end,'automation',v_id);
  return v_id;
end; $$;

-- Executa somente ações internas já suportadas pelo motor V1. Função privada ao banco.
create or replace function public.execute_temporal_automation_actions(
  p_automation_id uuid,
  p_lead_id uuid,
  p_customer_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_dedupe_key text
)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_auto public.automations%rowtype; v_action jsonb; v_type text; v_log jsonb:='[]'::jsonb;
  v_failed boolean:=false; v_assigned uuid; v_stage uuid; v_priority text; v_due integer; v_status text;
begin
  select * into v_auto from public.automations where id=p_automation_id and active=true;
  if v_auto.id is null or not public.organization_has_entitlement(v_auto.organization_id,'automations') then return 'ignored'; end if;
  if p_dedupe_key is null or exists(select 1 from public.automation_runs where automation_id=v_auto.id and dedupe_key=p_dedupe_key) then return 'ignored'; end if;

  for v_action in select value from jsonb_array_elements(v_auto.actions) loop
    v_type:=v_action->>'type';
    begin
      if v_type='create_task' then
        v_priority:=coalesce(nullif(v_action->>'priority',''),'medium'); if v_priority not in('low','medium','high','urgent') then v_priority:='medium'; end if;
        begin v_due:=greatest(0,least(coalesce((v_action->>'due_minutes')::integer,0),43200)); exception when others then v_due:=0; end;
        v_assigned:=null;
        if coalesce(v_action->>'assigned_to','')<>'' then begin v_assigned:=(v_action->>'assigned_to')::uuid; exception when others then v_assigned:=null; end; end if;
        if v_assigned is not null and not exists(select 1 from public.organization_members where organization_id=v_auto.organization_id and user_id=v_assigned and status='active') then v_assigned:=null; end if;
        insert into public.tasks(organization_id,lead_id,customer_id,title,description,assigned_to,priority,due_at,status,created_by)
        values(v_auto.organization_id,p_lead_id,p_customer_id,left(trim(v_action->>'title'),200),nullif(left(coalesce(v_action->>'description',''),2000),''),v_assigned,v_priority,case when v_due>0 then now()+make_interval(mins=>v_due) else null end,'open',v_auto.created_by);
      elsif v_type='add_tag' then
        if p_lead_id is null then raise exception 'lead unavailable'; end if;
        update public.leads set tags=array(select distinct x from unnest(tags||array[left(trim(v_action->>'tag'),50)]) x),updated_at=now()
        where id=p_lead_id and organization_id=v_auto.organization_id;
      elsif v_type='move_stage' then
        if p_lead_id is null then raise exception 'lead unavailable'; end if;
        select ps.id into v_stage from public.pipeline_stages ps join public.leads l on l.pipeline_id=ps.pipeline_id
        where l.id=p_lead_id and l.organization_id=v_auto.organization_id and ps.stage_key=v_action->>'stage_key' limit 1;
        if v_stage is null then raise exception 'stage unavailable'; end if;
        update public.leads set stage_id=v_stage,status=case when (v_action->>'stage_key')='won' then 'won' when (v_action->>'stage_key')='lost' then 'lost' else status end,updated_at=now() where id=p_lead_id;
      elsif v_type='notify_team' then
        insert into public.notifications(organization_id,user_id,kind,title,body,entity_type,entity_id)
        select v_auto.organization_id,m.user_id,'info',left(trim(v_action->>'title'),160),nullif(left(coalesce(v_action->>'body',''),1000),''),p_entity_type,p_entity_id
        from public.organization_members m where m.organization_id=v_auto.organization_id and m.status='active';
      else
        raise exception 'unsupported action';
      end if;
      v_log:=v_log||jsonb_build_array(jsonb_build_object('type',v_type,'status','executed'));
    exception when others then
      v_failed:=true;
      v_log:=v_log||jsonb_build_array(jsonb_build_object('type',coalesce(v_type,'unknown'),'status','failed','reason',left(sqlerrm,300)));
    end;
  end loop;

  v_status:=case when v_failed then 'failed' else 'executed' end;
  insert into public.automation_runs(organization_id,automation_id,status,reason,actions_log,dedupe_key)
  values(v_auto.organization_id,v_auto.id,v_status,case when v_failed then 'Uma ou mais ações falharam.' else null end,v_log,p_dedupe_key)
  on conflict (automation_id,dedupe_key) where dedupe_key is not null do nothing;
  return v_status;
end; $$;
revoke all on function public.execute_temporal_automation_actions(uuid,uuid,uuid,text,uuid,text) from public, anon, authenticated;

-- Chamado pelo Supabase Cron. O lock evita dois schedulers executando o mesmo lote em paralelo.
create or replace function public.run_temporal_automations(p_now timestamptz default now(), p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_auto public.automations%rowtype; v_lead public.leads%rowtype; v_customer public.customers%rowtype;
  v_after integer; v_days integer; v_count integer:=0; v_run_at timestamptz; v_timezone text; v_last_activity timestamptz;
  v_key text; v_status text;
begin
  p_limit:=greatest(1,least(coalesce(p_limit,500),2000));
  if not pg_try_advisory_xact_lock(hashtextextended('platform_temporal_automations',0)) then
    return jsonb_build_object('processed',0,'busy',true);
  end if;

  for v_auto in
    select a.* from public.automations a
    where a.active=true and a.trigger_event in('lead_no_response','customer_inactive','date_specific')
      and public.organization_has_entitlement(a.organization_id,'automations')
    order by a.created_at
  loop
    exit when v_count>=p_limit;

    if v_auto.trigger_event='lead_no_response' then
      begin v_after:=(v_auto.conditions->>'after_minutes')::integer; exception when others then continue; end;
      if v_after not between 15 and 525600 then continue; end if;
      for v_lead in
        select l.* from public.leads l
        where l.organization_id=v_auto.organization_id
          and l.status not in('won','lost')
          and greatest(coalesce(l.last_contact_at,l.created_at),l.updated_at) <= p_now-make_interval(mins=>v_after)
          and (not(v_auto.conditions?'source') or l.source=v_auto.conditions->>'source')
          and (not(v_auto.conditions?'status') or l.status=v_auto.conditions->>'status')
          and (not(v_auto.conditions?'tag') or (v_auto.conditions->>'tag')=any(coalesce(l.tags,'{}'::text[])))
          and (not(v_auto.conditions?'min_value_cents') or coalesce(l.potential_value_cents,0)>=(v_auto.conditions->>'min_value_cents')::bigint)
        order by greatest(coalesce(l.last_contact_at,l.created_at),l.updated_at)
        limit greatest(1,p_limit-v_count)
      loop
        v_last_activity:=greatest(coalesce(v_lead.last_contact_at,v_lead.created_at),v_lead.updated_at);
        v_key:='lead_no_response:'||v_lead.id::text||':'||floor(extract(epoch from v_last_activity))::bigint::text;
        v_status:=public.execute_temporal_automation_actions(v_auto.id,v_lead.id,null,'lead',v_lead.id,v_key);
        if v_status<>'ignored' then v_count:=v_count+1; end if;
        exit when v_count>=p_limit;
      end loop;

    elsif v_auto.trigger_event='customer_inactive' then
      begin v_days:=(v_auto.conditions->>'inactive_days')::integer; exception when others then continue; end;
      if v_days not between 1 and 3650 then continue; end if;
      for v_customer in
        select c.* from public.customers c
        where c.organization_id=v_auto.organization_id
          and greatest(
            c.updated_at,
            coalesce((select max(q.updated_at) from public.quotes q where q.organization_id=c.organization_id and q.customer_id=c.id),c.updated_at),
            coalesce((select max(a.updated_at) from public.appointments a where a.organization_id=c.organization_id and a.customer_id=c.id),c.updated_at),
            coalesce((select max(t.updated_at) from public.tasks t where t.organization_id=c.organization_id and t.customer_id=c.id),c.updated_at)
          ) <= p_now-make_interval(days=>v_days)
        order by c.updated_at
        limit greatest(1,p_limit-v_count)
      loop
        select greatest(
          v_customer.updated_at,
          coalesce((select max(q.updated_at) from public.quotes q where q.organization_id=v_customer.organization_id and q.customer_id=v_customer.id),v_customer.updated_at),
          coalesce((select max(a.updated_at) from public.appointments a where a.organization_id=v_customer.organization_id and a.customer_id=v_customer.id),v_customer.updated_at),
          coalesce((select max(t.updated_at) from public.tasks t where t.organization_id=v_customer.organization_id and t.customer_id=v_customer.id),v_customer.updated_at)
        ) into v_last_activity;
        v_key:='customer_inactive:'||v_customer.id::text||':'||floor(extract(epoch from v_last_activity))::bigint::text;
        v_status:=public.execute_temporal_automation_actions(v_auto.id,null,v_customer.id,'customer',v_customer.id,v_key);
        if v_status<>'ignored' then v_count:=v_count+1; end if;
        exit when v_count>=p_limit;
      end loop;

    elsif v_auto.trigger_event='date_specific' then
      select timezone into v_timezone from public.organizations where id=v_auto.organization_id;
      begin v_run_at:=(v_auto.conditions->>'run_at_local')::timestamp at time zone coalesce(v_timezone,'America/Sao_Paulo'); exception when others then continue; end;
      if v_run_at<=p_now then
        v_key:='date_specific:'||v_auto.id::text||':'||floor(extract(epoch from v_run_at))::bigint::text;
        v_status:=public.execute_temporal_automation_actions(v_auto.id,null,null,'automation',v_auto.id,v_key);
        if v_status<>'ignored' then
          v_count:=v_count+1;
          update public.automations set active=false,updated_at=now() where id=v_auto.id;
        end if;
      end if;
    end if;
  end loop;

  return jsonb_build_object('processed',v_count,'busy',false,'ran_at',p_now);
end; $$;
revoke all on function public.run_temporal_automations(timestamptz,integer) from public, anon, authenticated;
grant execute on function public.run_temporal_automations(timestamptz,integer) to service_role;

comment on function public.run_temporal_automations(timestamptz,integer) is
'Executa gatilhos temporais. Em Supabase hospedado, agendar via Supabase Cron/pg_cron; não expor a usuários da aplicação.';

-- ============================================================================
-- 202608150018_communications_phase3.sql
-- ============================================================================

-- 2026-08-15 — Fase 3 inicial: e-mail transacional e WhatsApp Cloud API oficial.
-- Segredos de WhatsApp ficam em tabela sem policy e são gravados somente pelo backend service-role.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"email_transactional":true,"whatsapp_official":true}'::jsonb
where code in ('professional','ai');

create table public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null check (provider in ('whatsapp_cloud')),
  status text not null default 'configured' check (status in ('disconnected','configured','active','error')),
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config)='object'),
  last_verified_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,provider)
);
create trigger integration_connections_set_updated_at before update on public.integration_connections for each row execute procedure public.set_updated_at();
create index integration_connections_whatsapp_phone_idx on public.integration_connections ((config->>'phone_number_id')) where provider='whatsapp_cloud';
alter table public.integration_connections enable row level security;
create policy integration_connections_select_member on public.integration_connections for select to authenticated
using (public.is_org_member(organization_id));
-- Escrita somente pelo backend após validar papel/entitlement na Server Action.

create table public.integration_secrets (
  connection_id uuid primary key references public.integration_connections(id) on delete cascade,
  ciphertext text not null,
  iv text not null,
  auth_tag text not null,
  updated_at timestamptz not null default now()
);
alter table public.integration_secrets enable row level security;
-- Sem policies: segredos nunca são retornados para anon/authenticated.

create table public.communication_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  channel text not null check (channel in ('email','whatsapp')),
  direction text not null check (direction in ('inbound','outbound')),
  provider text not null check (provider in ('resend','whatsapp_cloud')),
  provider_message_id text,
  lead_id uuid references public.leads(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  sender text,
  recipient text,
  subject text,
  body text check (body is null or char_length(body)<=10000),
  message_type text,
  template_name text,
  status text not null check (status in ('queued','sent','delivered','read','failed','received')),
  error_code text,
  error_message text,
  created_by uuid references auth.users(id) on delete set null,
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index communication_messages_provider_id_uidx on public.communication_messages(provider,provider_message_id) where provider_message_id is not null;
create index communication_messages_org_created_idx on public.communication_messages(organization_id,created_at desc);
create index communication_messages_lead_idx on public.communication_messages(organization_id,lead_id,created_at desc) where lead_id is not null;
create index communication_messages_customer_idx on public.communication_messages(organization_id,customer_id,created_at desc) where customer_id is not null;
create trigger communication_messages_set_updated_at before update on public.communication_messages for each row execute procedure public.set_updated_at();
alter table public.communication_messages enable row level security;
create policy communication_messages_select_member on public.communication_messages for select to authenticated
using (public.is_org_member(organization_id));
-- INSERT/UPDATE externos ficam restritos ao backend service-role.

-- Resolve conexão sem expor segredo; usado pelo Webhook assinado da Meta.
create or replace function public.service_find_whatsapp_connection(p_phone_number_id text)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object('id',c.id,'organization_id',c.organization_id,'status',c.status,'config',c.config)
  from public.integration_connections c
  where c.provider='whatsapp_cloud' and c.status='active' and c.config->>'phone_number_id'=trim(p_phone_number_id)
  limit 1;
$$;
revoke all on function public.service_find_whatsapp_connection(text) from public, anon, authenticated;
grant execute on function public.service_find_whatsapp_connection(text) to service_role;

-- Registra mensagem recebida de forma transacional, reaproveitando lead/cliente pelo telefone.
create or replace function public.service_record_whatsapp_inbound(
  p_phone_number_id text,
  p_provider_message_id text,
  p_from_phone text,
  p_contact_name text,
  p_body text,
  p_message_type text,
  p_received_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_conn public.integration_connections%rowtype; v_org uuid; v_phone text; v_lead uuid; v_customer uuid; v_message uuid; v_pipeline uuid; v_stage uuid; v_inserted boolean:=false;
begin
  select * into v_conn from public.integration_connections
  where provider='whatsapp_cloud' and status='active' and config->>'phone_number_id'=trim(p_phone_number_id) limit 1;
  if v_conn.id is null then raise exception 'whatsapp connection not found'; end if;
  v_org:=v_conn.organization_id;
  v_phone:=regexp_replace(coalesce(p_from_phone,''),'[^0-9]','','g');
  if char_length(v_phone) not between 8 and 15 then raise exception 'invalid sender phone'; end if;
  if char_length(trim(coalesce(p_provider_message_id,'')))<3 then raise exception 'invalid provider message id'; end if;

  select l.id into v_lead from public.leads l
  where l.organization_id=v_org and (
    regexp_replace(coalesce(l.whatsapp,''),'[^0-9]','','g')=v_phone or regexp_replace(coalesce(l.phone,''),'[^0-9]','','g')=v_phone
  ) order by l.updated_at desc limit 1;
  select c.id into v_customer from public.customers c
  where c.organization_id=v_org and (
    regexp_replace(coalesce(c.whatsapp,''),'[^0-9]','','g')=v_phone or regexp_replace(coalesce(c.phone,''),'[^0-9]','','g')=v_phone
  ) order by c.updated_at desc limit 1;

  if v_lead is null and v_customer is null then
    select p.id into v_pipeline from public.pipelines p where p.organization_id=v_org and p.is_default=true order by p.created_at limit 1;
    if v_pipeline is not null then select ps.id into v_stage from public.pipeline_stages ps where ps.pipeline_id=v_pipeline order by ps.sort_order limit 1; end if;
    insert into public.leads(organization_id,pipeline_id,stage_id,name,whatsapp,source,status,last_contact_at)
    values(v_org,v_pipeline,v_stage,left(coalesce(nullif(trim(p_contact_name),''),v_phone),160),v_phone,'whatsapp','new',coalesce(p_received_at,now())) returning id into v_lead;
  end if;

  insert into public.communication_messages(
    organization_id,channel,direction,provider,provider_message_id,lead_id,customer_id,sender,body,message_type,status,received_at
  ) values(
    v_org,'whatsapp','inbound','whatsapp_cloud',trim(p_provider_message_id),v_lead,v_customer,v_phone,left(p_body,10000),left(coalesce(p_message_type,'unknown'),50),'received',coalesce(p_received_at,now())
  ) on conflict (provider,provider_message_id) where provider_message_id is not null do nothing
  returning id into v_message;

  if v_message is not null then
    v_inserted:=true;
    if v_lead is not null then
      update public.leads set last_contact_at=coalesce(p_received_at,now()),updated_at=now() where id=v_lead and organization_id=v_org;
      insert into public.events(organization_id,entity_type,entity_id,event_type,metadata)
      values(v_org,'lead',v_lead,'whatsapp_message_received',jsonb_build_object('message_id',v_message,'message_type',coalesce(p_message_type,'unknown')));
    elsif v_customer is not null then
      insert into public.events(organization_id,entity_type,entity_id,event_type,metadata)
      values(v_org,'customer',v_customer,'whatsapp_message_received',jsonb_build_object('message_id',v_message,'message_type',coalesce(p_message_type,'unknown')));
    end if;
  else
    select id into v_message from public.communication_messages where provider='whatsapp_cloud' and provider_message_id=trim(p_provider_message_id);
  end if;

  return jsonb_build_object('organization_id',v_org,'lead_id',v_lead,'customer_id',v_customer,'message_id',v_message,'inserted',v_inserted);
end; $$;
revoke all on function public.service_record_whatsapp_inbound(text,text,text,text,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.service_record_whatsapp_inbound(text,text,text,text,text,text,timestamptz) to service_role;

create or replace function public.service_update_communication_status(
  p_provider text,
  p_provider_message_id text,
  p_status text,
  p_error_code text,
  p_error_message text,
  p_at timestamptz
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if p_provider not in('resend','whatsapp_cloud') or p_status not in('sent','delivered','read','failed') then raise exception 'invalid provider status'; end if;
  update public.communication_messages set
    status=p_status,
    error_code=nullif(left(coalesce(p_error_code,''),100),''),
    error_message=nullif(left(coalesce(p_error_message,''),1000),''),
    sent_at=case when p_status='sent' then coalesce(p_at,now()) else sent_at end,
    delivered_at=case when p_status='delivered' then coalesce(p_at,now()) else delivered_at end,
    read_at=case when p_status='read' then coalesce(p_at,now()) else read_at end,
    updated_at=now()
  where provider=p_provider and provider_message_id=p_provider_message_id;
end; $$;
revoke all on function public.service_update_communication_status(text,text,text,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.service_update_communication_status(text,text,text,text,text,timestamptz) to service_role;

-- ============================================================================
-- 202608150019_transactional_outbox.sql
-- ============================================================================

-- 2026-08-15 — Outbox transacional para integrações externas.
-- Triggers apenas enfileiram trabalho no PostgreSQL. Nenhuma chamada HTTP ocorre dentro da transação comercial.

create table public.external_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null check (provider in ('resend','whatsapp_cloud','google_calendar')),
  kind text not null check (char_length(kind) between 3 and 80),
  recipient_user_id uuid references auth.users(id) on delete set null,
  recipient text,
  entity_type text,
  entity_id uuid,
  source_event_id uuid references public.events(id) on delete set null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  dedupe_key text not null check (char_length(dedupe_key) between 8 and 300),
  status text not null default 'pending' check (status in ('pending','processing','retry','sent','dead_letter')),
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(dedupe_key)
);
create index external_outbox_claim_idx on public.external_outbox(status,available_at,created_at)
  where status in ('pending','retry','processing');
create index external_outbox_org_created_idx on public.external_outbox(organization_id,created_at desc);
create trigger external_outbox_set_updated_at before update on public.external_outbox
for each row execute procedure public.set_updated_at();
alter table public.external_outbox enable row level security;
-- Sem policies: fila é infraestrutura server-side e não pode ser manipulada diretamente pelo tenant.

create or replace function public.enqueue_system_email_from_event()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_lead public.leads%rowtype;
  v_status text;
  v_plan_name text;
begin
  if new.event_type='organization_created' and new.actor_user_id is not null then
    insert into public.external_outbox(
      organization_id,provider,kind,recipient_user_id,entity_type,entity_id,source_event_id,payload,dedupe_key
    ) values(
      new.organization_id,'resend','welcome',new.actor_user_id,'organization',new.organization_id,new.id,
      jsonb_build_object('organization_name',(select name from public.organizations where id=new.organization_id)),
      'resend:welcome:event:'||new.id::text
    ) on conflict(dedupe_key) do nothing;
    return new;
  end if;

  if new.event_type='lead_created' and new.entity_id is not null then
    select * into v_lead from public.leads where id=new.entity_id and organization_id=new.organization_id;
    if v_lead.id is null then return new; end if;

    insert into public.external_outbox(
      organization_id,provider,kind,recipient_user_id,entity_type,entity_id,source_event_id,payload,dedupe_key
    )
    select
      new.organization_id,'resend','new_lead',m.user_id,'lead',v_lead.id,new.id,
      jsonb_build_object(
        'lead_name',v_lead.name,
        'source',v_lead.source,
        'interest',v_lead.interest,
        'organization_name',(select name from public.organizations where id=new.organization_id)
      ),
      'resend:new_lead:event:'||new.id::text||':user:'||m.user_id::text
    from public.organization_members m
    left join public.profiles p on p.id=m.user_id
    where m.organization_id=new.organization_id
      and m.status='active'
      and m.role in ('owner','admin','sales','support')
      and (new.actor_user_id is null or m.user_id<>new.actor_user_id)
      and coalesce(p.notification_preferences->'leads','true'::jsonb) <> 'false'::jsonb
    on conflict(dedupe_key) do nothing;
    return new;
  end if;

  if new.event_type='subscription_status_changed' then
    v_status:=lower(coalesce(new.metadata->>'status',''));
    if v_status not in ('active','past_due','suspended','canceled') then return new; end if;

    select p.name into v_plan_name
    from public.subscriptions s join public.plans p on p.id=s.plan_id
    where s.organization_id=new.organization_id
    order by s.created_at desc limit 1;

    insert into public.external_outbox(
      organization_id,provider,kind,recipient_user_id,entity_type,entity_id,source_event_id,payload,dedupe_key
    )
    select
      new.organization_id,'resend','subscription_'||v_status,m.user_id,'subscription',new.entity_id,new.id,
      jsonb_build_object(
        'status',v_status,
        'plan_name',v_plan_name,
        'organization_name',(select name from public.organizations where id=new.organization_id)
      ),
      'resend:subscription:'||v_status||':event:'||new.id::text||':user:'||m.user_id::text
    from public.organization_members m
    left join public.profiles p on p.id=m.user_id
    where m.organization_id=new.organization_id
      and m.status='active'
      and m.role in ('owner','admin')
      and coalesce(p.notification_preferences->'billing','true'::jsonb) <> 'false'::jsonb
    on conflict(dedupe_key) do nothing;
  end if;

  return new;
end;
$$;
revoke all on function public.enqueue_system_email_from_event() from public, anon, authenticated;

create trigger events_enqueue_system_email
after insert on public.events
for each row execute procedure public.enqueue_system_email_from_event();

create or replace function public.service_claim_external_outbox(p_worker_id text,p_limit integer default 20)
returns setof public.external_outbox
language plpgsql
security definer
set search_path=public
as $$
begin
  if char_length(trim(coalesce(p_worker_id,'')))<8 then raise exception 'invalid worker id'; end if;
  p_limit:=least(greatest(coalesce(p_limit,20),1),50);

  -- Jobs abandonados por worker interrompido voltam à fila.
  update public.external_outbox
  set status='retry',available_at=now(),locked_at=null,locked_by=null,last_error=coalesce(last_error,'worker lock expired')
  where status='processing' and locked_at < now()-interval '15 minutes';

  return query
  with picked as (
    select id from public.external_outbox
    where status in ('pending','retry') and available_at<=now()
    order by available_at,created_at
    for update skip locked
    limit p_limit
  )
  update public.external_outbox o set
    status='processing',attempts=o.attempts+1,locked_at=now(),locked_by=trim(p_worker_id),last_error=null
  from picked
  where o.id=picked.id
  returning o.*;
end;
$$;
revoke all on function public.service_claim_external_outbox(text,integer) from public, anon, authenticated;
grant execute on function public.service_claim_external_outbox(text,integer) to service_role;

create or replace function public.service_complete_external_outbox(
  p_job_id uuid,p_worker_id text,p_provider_message_id text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  update public.external_outbox set
    status='sent',provider_message_id=nullif(left(coalesce(p_provider_message_id,''),300),''),sent_at=now(),
    locked_at=null,locked_by=null,last_error=null
  where id=p_job_id and status='processing' and locked_by=trim(p_worker_id);
  if not found then raise exception 'outbox job not owned by worker'; end if;
end;
$$;
revoke all on function public.service_complete_external_outbox(uuid,text,text) from public, anon, authenticated;
grant execute on function public.service_complete_external_outbox(uuid,text,text) to service_role;

create or replace function public.service_fail_external_outbox(
  p_job_id uuid,p_worker_id text,p_error text
)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare v_attempts integer;v_max integer;v_status text;v_delay integer;
begin
  select attempts,max_attempts into v_attempts,v_max from public.external_outbox
  where id=p_job_id and status='processing' and locked_by=trim(p_worker_id) for update;
  if not found then raise exception 'outbox job not owned by worker'; end if;

  if v_attempts>=v_max then
    v_status:='dead_letter';
    update public.external_outbox set status=v_status,available_at=now(),locked_at=null,locked_by=null,
      last_error=left(coalesce(p_error,'unknown error'),1500) where id=p_job_id;
  else
    v_status:='retry';
    v_delay:=least(3600,30*(2^greatest(v_attempts-1,0))::integer);
    update public.external_outbox set status=v_status,available_at=now()+make_interval(secs=>v_delay),locked_at=null,locked_by=null,
      last_error=left(coalesce(p_error,'unknown error'),1500) where id=p_job_id;
  end if;
  return v_status;
end;
$$;
revoke all on function public.service_fail_external_outbox(uuid,text,text) from public, anon, authenticated;
grant execute on function public.service_fail_external_outbox(uuid,text,text) to service_role;

-- ============================================================================
-- 202608150020_resend_webhooks.sql
-- ============================================================================

-- 2026-08-15 — Webhooks do Resend: auditoria idempotente e atualização de entrega real.

create table public.provider_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('resend','whatsapp_cloud')),
  provider_event_id text not null,
  event_type text not null,
  provider_message_id text,
  occurred_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  unique(provider,provider_event_id)
);
create index provider_webhook_events_message_idx on public.provider_webhook_events(provider,provider_message_id,created_at desc);
alter table public.provider_webhook_events enable row level security;
-- Sem policies: eventos assinados são infraestrutura interna, não payload para o tenant.

create or replace function public.service_record_resend_event(
  p_provider_event_id text,
  p_event_type text,
  p_email_id text,
  p_occurred_at timestamptz,
  p_error_message text default null
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_event uuid;v_type text:=lower(trim(coalesce(p_event_type,'')));
begin
  if char_length(trim(coalesce(p_provider_event_id,'')))<3 then raise exception 'invalid event id'; end if;
  if char_length(trim(coalesce(p_email_id,'')))<3 then raise exception 'invalid email id'; end if;
  if v_type not in ('email.sent','email.delivered','email.bounced','email.failed','email.suppressed','email.delivery_delayed','email.opened','email.clicked','email.complained') then
    raise exception 'unsupported resend event';
  end if;

  insert into public.provider_webhook_events(provider,provider_event_id,event_type,provider_message_id,occurred_at,error_message)
  values('resend',trim(p_provider_event_id),v_type,trim(p_email_id),coalesce(p_occurred_at,now()),nullif(left(coalesce(p_error_message,''),1000),''))
  on conflict(provider,provider_event_id) do nothing returning id into v_event;
  if v_event is null then return false; end if;

  if v_type='email.sent' then
    update public.communication_messages set
      status=case when status='queued' then 'sent' else status end,
      sent_at=case when status='queued' then coalesce(p_occurred_at,now()) else sent_at end
    where provider='resend' and provider_message_id=trim(p_email_id);
  elsif v_type='email.delivered' then
    update public.communication_messages set
      status='delivered',
      sent_at=coalesce(sent_at,coalesce(p_occurred_at,now())),
      delivered_at=coalesce(delivered_at,coalesce(p_occurred_at,now())),
      error_code=null,error_message=null
    where provider='resend' and provider_message_id=trim(p_email_id) and status<>'failed';
  elsif v_type in ('email.bounced','email.failed','email.suppressed') then
    update public.communication_messages set
      status='failed',error_code=left(v_type,100),
      error_message=coalesce(nullif(left(coalesce(p_error_message,''),1000),''),v_type)
    where provider='resend' and provider_message_id=trim(p_email_id) and status<>'delivered';
  end if;

  return true;
end;
$$;
revoke all on function public.service_record_resend_event(text,text,text,timestamptz,text) from public, anon, authenticated;
grant execute on function public.service_record_resend_event(text,text,text,timestamptz,text) to service_role;

-- ============================================================================
-- 202608150021_google_integrations.sql
-- ============================================================================

-- 2026-08-15 — Google Calendar via OAuth/outbox e Google Maps Geocoding v4 server-side.

update public.plans
set entitlements=coalesce(entitlements,'{}'::jsonb)||'{"google_calendar":true,"google_maps":true}'::jsonb
where code in ('professional','ai');

alter table public.integration_connections drop constraint if exists integration_connections_provider_check;
alter table public.integration_connections add constraint integration_connections_provider_check
  check (provider in ('whatsapp_cloud','google_calendar'));

create table public.oauth_states (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('google_calendar')),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index oauth_states_expiry_idx on public.oauth_states(expires_at) where used_at is null;
alter table public.oauth_states enable row level security;
-- Sem policies: state OAuth é lido/escrito apenas pelo backend secreto.

create table public.appointment_external_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  provider text not null check (provider='google_calendar'),
  external_event_id text not null,
  html_link text,
  status text not null default 'active' check(status in ('active','canceled','error')),
  last_synced_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(appointment_id,provider)
);
create trigger appointment_external_events_set_updated_at before update on public.appointment_external_events
for each row execute procedure public.set_updated_at();
alter table public.appointment_external_events enable row level security;
create policy appointment_external_events_select_member on public.appointment_external_events for select to authenticated
using(public.is_org_member(organization_id));
-- Escrita somente pelo worker server-side.

alter table public.organizations
  add column if not exists latitude double precision check(latitude is null or latitude between -90 and 90),
  add column if not exists longitude double precision check(longitude is null or longitude between -180 and 180),
  add column if not exists google_place_id text,
  add column if not exists geocoded_address text,
  add column if not exists geocoded_at timestamptz;

create or replace function public.enqueue_google_calendar_from_event()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_kind text;
begin
  if new.entity_type<>'appointment' or new.entity_id is null then return new; end if;
  if new.event_type not in('appointment_created','appointment_status_changed') then return new; end if;
  if not public.organization_has_entitlement(new.organization_id,'google_calendar') then return new; end if;
  if not exists(select 1 from public.integration_connections c where c.organization_id=new.organization_id and c.provider='google_calendar' and c.status='active') then return new; end if;

  if new.event_type='appointment_status_changed' and lower(coalesce(new.metadata->>'status',''))='canceled' then
    v_kind:='calendar_delete_appointment';
  else
    v_kind:='calendar_upsert_appointment';
  end if;

  insert into public.external_outbox(organization_id,provider,kind,entity_type,entity_id,source_event_id,payload,dedupe_key)
  values(new.organization_id,'google_calendar',v_kind,'appointment',new.entity_id,new.id,new.metadata,
    'google_calendar:'||v_kind||':event:'||new.id::text)
  on conflict(dedupe_key) do nothing;
  return new;
end;
$$;
revoke all on function public.enqueue_google_calendar_from_event() from public,anon,authenticated;
create trigger events_enqueue_google_calendar after insert on public.events
for each row execute procedure public.enqueue_google_calendar_from_event();

-- Reaplica o payload público para expor localização validada sem expor chave do Maps.
create or replace function public.get_public_site(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_org public.organizations%rowtype;v_site public.site_configs%rowtype;v_snapshot jsonb;
begin
  select o.* into v_org from public.organizations o where o.slug=p_slug and o.status='active' limit 1;
  if v_org.id is null or not public.organization_has_entitlement(v_org.id,'site') then return null; end if;
  select s.* into v_site from public.site_configs s where s.organization_id=v_org.id and s.status='published' limit 1;
  if v_site.id is null then return null; end if;
  v_snapshot:=coalesce(v_site.published_snapshot,jsonb_build_object('site',jsonb_build_object('headline',v_site.headline,'subheadline',v_site.subheadline,'about',v_site.about,'primary_color',v_site.primary_color,'cover_image_url',v_site.cover_image_url),'sections','[]'::jsonb));
  return jsonb_build_object(
    'organization',jsonb_build_object('name',v_org.name,'slug',v_org.slug,'segment',v_org.segment,'whatsapp',v_org.whatsapp,'phone',v_org.phone,'city',v_org.city,'state',v_org.state,'address',v_org.address,'latitude',v_org.latitude,'longitude',v_org.longitude,'geocoded_address',v_org.geocoded_address),
    'site',v_snapshot->'site','sections',coalesce(v_snapshot->'sections','[]'::jsonb),
    'products',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'price_cents',p.price_cents,'promotional_price_cents',p.promotional_price_cents,'image_url',p.image_url) order by p.featured desc,p.created_at desc) from public.products p where p.organization_id=v_org.id and p.available=true),'[]'::jsonb),
    'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'description',s.description,'starting_price_cents',s.starting_price_cents,'image_url',s.image_url) order by s.created_at desc) from public.services s where s.organization_id=v_org.id and s.active=true),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_public_site(text) from public;
grant execute on function public.get_public_site(text) to anon,authenticated;

-- ============================================================================
-- 202608150022_google_calendar_backfill.sql
-- ============================================================================

-- 2026-08-15 — Backfill seguro do Google Calendar após OAuth.
-- O callback server-side chama esta RPC com a chave única do fluxo OAuth.
create or replace function public.service_enqueue_google_calendar_backfill(
  p_organization_id uuid,
  p_sync_key text
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'forbidden'; end if;
  if p_sync_key is null or char_length(p_sync_key)<8 or char_length(p_sync_key)>120 then
    raise exception 'invalid sync key';
  end if;
  if not public.organization_has_entitlement(p_organization_id,'google_calendar') then return 0; end if;
  if not exists(
    select 1 from public.integration_connections c
    where c.organization_id=p_organization_id
      and c.provider='google_calendar'
      and c.status='active'
  ) then return 0; end if;

  insert into public.external_outbox(
    organization_id,provider,kind,entity_type,entity_id,payload,dedupe_key
  )
  select
    a.organization_id,
    'google_calendar',
    'calendar_upsert_appointment',
    'appointment',
    a.id,
    jsonb_build_object('source','google_calendar_connection','sync_key',p_sync_key),
    'google_calendar:backfill:'||p_sync_key||':appointment:'||a.id::text
  from public.appointments a
  where a.organization_id=p_organization_id
    and a.status in ('scheduled','confirmed')
    and a.ends_at>now()
  on conflict(dedupe_key) do nothing;

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.service_enqueue_google_calendar_backfill(uuid,text) from public,anon,authenticated;
grant execute on function public.service_enqueue_google_calendar_backfill(uuid,text) to service_role;

-- ============================================================================
-- 202608150023_public_api.sql
-- ============================================================================

-- 2026-08-15 — API pública com chaves opacas, escopos e quota horária atômica.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"public_api":false}'::jsonb,
    limits = '{"api_keys":3,"api_requests_per_hour":1000}'::jsonb || coalesce(limits,'{}'::jsonb)
where not coalesce(entitlements,'{}'::jsonb) ? 'public_api';

create table public.api_keys (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 100),
  key_prefix text not null check (char_length(key_prefix) between 8 and 32),
  secret_hash text not null unique check (char_length(secret_hash) = 64),
  scopes text[] not null default '{}'::text[] check (cardinality(scopes) between 1 and 20),
  status text not null default 'active' check (status in ('active','revoked')),
  expires_at timestamptz,
  last_used_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index api_keys_org_created_idx on public.api_keys(organization_id,created_at desc);
create index api_keys_org_status_idx on public.api_keys(organization_id,status);
create trigger api_keys_set_updated_at before update on public.api_keys
for each row execute procedure public.set_updated_at();
alter table public.api_keys enable row level security;
-- Sem policies: o hash da chave nunca fica disponível via PostgREST do tenant.

create table public.api_usage_windows (
  api_key_id uuid not null references public.api_keys(id) on delete cascade,
  window_start timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key(api_key_id,window_start)
);
alter table public.api_usage_windows enable row level security;
-- Infraestrutura server-only, sem policies.

create table public.api_request_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  api_key_id uuid references public.api_keys(id) on delete set null,
  scope text not null,
  method text not null,
  route text not null check (char_length(route) between 1 and 240),
  response_status integer not null check (response_status between 100 and 599),
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  request_id text,
  created_at timestamptz not null default now()
);
create index api_request_logs_org_created_idx on public.api_request_logs(organization_id,created_at desc);
create index api_request_logs_key_created_idx on public.api_request_logs(api_key_id,created_at desc);
alter table public.api_request_logs enable row level security;
-- Logs de API são server-only; o tenant recebe somente agregados por RPC segura.

create or replace function public.service_organization_has_feature(p_organization_id uuid,p_feature text)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1
    from public.subscriptions s
    join public.plans p on p.id=s.plan_id and p.active=true
    join public.organizations o on o.id=s.organization_id and o.status='active'
    where s.organization_id=p_organization_id
      and coalesce((p.entitlements->>p_feature)::boolean,false)=true
      and (s.status='active' or (s.status='trial' and (s.trial_ends_at is null or s.trial_ends_at>now())))
  );
$$;
revoke all on function public.service_organization_has_feature(uuid,text) from public,anon,authenticated;

create or replace function public.service_plan_limit(p_organization_id uuid,p_limit text,p_default integer default null)
returns integer
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_limit integer;
begin
  select case when jsonb_typeof(p.limits->p_limit)='number' then (p.limits->>p_limit)::integer else p_default end
  into v_limit
  from public.subscriptions s
  join public.plans p on p.id=s.plan_id and p.active=true
  join public.organizations o on o.id=s.organization_id and o.status='active'
  where s.organization_id=p_organization_id
    and (s.status='active' or (s.status='trial' and (s.trial_ends_at is null or s.trial_ends_at>now())))
  order by (s.status='active') desc,s.created_at desc
  limit 1;
  return coalesce(v_limit,p_default);
end;
$$;
revoke all on function public.service_plan_limit(uuid,text,integer) from public,anon,authenticated;

create or replace function public.service_consume_public_api_key(
  p_secret_hash text,
  p_required_scope text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_key public.api_keys%rowtype;
  v_limit integer;
  v_window timestamptz:=date_trunc('hour',now());
  v_count integer;
begin
  if p_secret_hash !~ '^[0-9a-f]{64}$' or char_length(trim(coalesce(p_required_scope,'')))<3 then
    raise exception 'invalid api credentials';
  end if;

  select * into v_key from public.api_keys where secret_hash=p_secret_hash for update;
  if v_key.id is null or v_key.status<>'active' or (v_key.expires_at is not null and v_key.expires_at<=now()) then
    raise exception 'invalid api key';
  end if;
  if not public.service_organization_has_feature(v_key.organization_id,'public_api') then
    raise exception 'api feature unavailable';
  end if;
  if not ('*'=any(v_key.scopes) or p_required_scope=any(v_key.scopes)) then
    raise exception 'insufficient scope';
  end if;

  v_limit:=greatest(coalesce(public.service_plan_limit(v_key.organization_id,'api_requests_per_hour',1000),1000),1);
  insert into public.api_usage_windows(api_key_id,window_start,request_count)
  values(v_key.id,v_window,1)
  on conflict(api_key_id,window_start) do update
    set request_count=public.api_usage_windows.request_count+1,updated_at=now()
    where public.api_usage_windows.request_count < v_limit
  returning request_count into v_count;

  if v_count is null then raise exception 'api rate limit exceeded'; end if;
  update public.api_keys set last_used_at=now() where id=v_key.id;

  return jsonb_build_object(
    'organization_id',v_key.organization_id,
    'api_key_id',v_key.id,
    'key_prefix',v_key.key_prefix,
    'scopes',to_jsonb(v_key.scopes),
    'limit',v_limit,
    'remaining',greatest(v_limit-v_count,0),
    'reset_at',v_window+interval '1 hour'
  );
end;
$$;
revoke all on function public.service_consume_public_api_key(text,text) from public,anon,authenticated;
grant execute on function public.service_consume_public_api_key(text,text) to service_role;

create or replace function public.service_create_api_lead(
  p_organization_id uuid,p_name text,p_phone text default null,p_whatsapp text default null,p_email text default null,
  p_company text default null,p_interest text default null,p_potential_value_cents bigint default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_pipeline uuid;v_stage uuid;v_id uuid;v_email text;
begin
  if not public.service_organization_has_feature(p_organization_id,'public_api') then raise exception 'api feature unavailable'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 2 and 160 then raise exception 'invalid name'; end if;
  v_email:=nullif(lower(trim(coalesce(p_email,''))),'');
  if v_email is not null and (char_length(v_email)>254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then raise exception 'invalid email'; end if;
  if p_potential_value_cents is not null and p_potential_value_cents<0 then raise exception 'invalid value'; end if;

  select id into v_pipeline from public.pipelines where organization_id=p_organization_id and is_default=true order by created_at limit 1;
  select id into v_stage from public.pipeline_stages where organization_id=p_organization_id and pipeline_id=v_pipeline and stage_key='new' limit 1;
  insert into public.leads(organization_id,pipeline_id,stage_id,name,phone,whatsapp,email,company,source,status,interest,potential_value_cents)
  values(p_organization_id,v_pipeline,v_stage,trim(p_name),nullif(left(trim(coalesce(p_phone,'')),40),''),nullif(left(trim(coalesce(p_whatsapp,'')),40),''),v_email,
    nullif(left(trim(coalesce(p_company,'')),160),''),'api','new',nullif(left(trim(coalesce(p_interest,'')),500),''),p_potential_value_cents)
  returning id into v_id;
  insert into public.events(organization_id,entity_type,entity_id,event_type,metadata)
  values(p_organization_id,'lead',v_id,'lead_created',jsonb_build_object('source','api'));
  return v_id;
end;
$$;
revoke all on function public.service_create_api_lead(uuid,text,text,text,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.service_create_api_lead(uuid,text,text,text,text,text,text,bigint) to service_role;

create or replace function public.list_api_keys(p_organization_id uuid)
returns table(id uuid,name text,key_prefix text,scopes text[],status text,expires_at timestamptz,last_used_at timestamptz,created_at timestamptz)
language sql
stable
security definer
set search_path=public
as $$
  select k.id,k.name,k.key_prefix,k.scopes,k.status,k.expires_at,k.last_used_at,k.created_at
  from public.api_keys k
  where k.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'public_api')
  order by k.created_at desc;
$$;
revoke all on function public.list_api_keys(uuid) from public;
grant execute on function public.list_api_keys(uuid) to authenticated;

create or replace function public.api_usage_summary(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when public.has_org_role(p_organization_id,array['owner','admin']) and public.has_feature(p_organization_id,'public_api') then
    jsonb_build_object(
      'last_24h',(select count(*) from public.api_request_logs l where l.organization_id=p_organization_id and l.created_at>=now()-interval '24 hours'),
      'errors_24h',(select count(*) from public.api_request_logs l where l.organization_id=p_organization_id and l.created_at>=now()-interval '24 hours' and l.response_status>=400),
      'active_keys',(select count(*) from public.api_keys k where k.organization_id=p_organization_id and k.status='active' and (k.expires_at is null or k.expires_at>now()))
    ) else null end;
$$;
revoke all on function public.api_usage_summary(uuid) from public;
grant execute on function public.api_usage_summary(uuid) to authenticated;

create or replace function public.admin_update_plan_limits(p_plan_id uuid,p_limits jsonb)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then raise exception 'forbidden'; end if;
  if jsonb_typeof(p_limits)<>'object' or exists(select 1 from jsonb_each(p_limits) e where jsonb_typeof(e.value)<>'number') then raise exception 'invalid limits'; end if;
  if exists(select 1 from jsonb_each_text(p_limits) e where e.value::numeric<0 or e.value::numeric>100000000) then raise exception 'invalid limits'; end if;
  update public.plans set limits=coalesce(limits,'{}'::jsonb)||p_limits,updated_at=now() where id=p_plan_id;
  if not found then raise exception 'plan not found'; end if;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'platform.plan_limits_updated','plan',p_plan_id,p_limits);
end;
$$;
revoke all on function public.admin_update_plan_limits(uuid,jsonb) from public;
grant execute on function public.admin_update_plan_limits(uuid,jsonb) to authenticated;

-- ============================================================================
-- 202608150024_client_webhooks.sql
-- ============================================================================

-- 2026-08-15 — Webhooks outbound por tenant usando o external_outbox existente.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"outbound_webhooks":false}'::jsonb,
    limits = '{"webhook_endpoints":3}'::jsonb || coalesce(limits,'{}'::jsonb)
where not coalesce(entitlements,'{}'::jsonb) ? 'outbound_webhooks';

create table public.webhook_endpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check(char_length(name) between 2 and 100),
  url text not null check(char_length(url) between 12 and 1000),
  event_types text[] not null check(cardinality(event_types) between 1 and 30),
  status text not null default 'active' check(status in ('active','paused','disabled')),
  signing_secret_prefix text not null check(char_length(signing_secret_prefix) between 8 and 32),
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index webhook_endpoints_org_idx on public.webhook_endpoints(organization_id,created_at desc);
create trigger webhook_endpoints_set_updated_at before update on public.webhook_endpoints for each row execute procedure public.set_updated_at();
alter table public.webhook_endpoints enable row level security;
-- Sem policies: edição passa por ações server-side; leitura segura usa RPC sem segredo.

create table public.webhook_endpoint_secrets (
  endpoint_id uuid primary key references public.webhook_endpoints(id) on delete cascade,
  ciphertext text not null,
  iv text not null,
  auth_tag text not null,
  updated_at timestamptz not null default now()
);
alter table public.webhook_endpoint_secrets enable row level security;
-- Sem policies: segredo criptografado ainda é infraestrutura server-only.

create table public.webhook_deliveries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  endpoint_id uuid not null references public.webhook_endpoints(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  event_type text not null,
  status text not null default 'queued' check(status in ('queued','processing','retry','delivered','failed')),
  attempts integer not null default 0 check(attempts>=0),
  response_status integer check(response_status is null or response_status between 100 and 599),
  last_error text,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(endpoint_id,event_id)
);
create index webhook_deliveries_org_created_idx on public.webhook_deliveries(organization_id,created_at desc);
create index webhook_deliveries_endpoint_created_idx on public.webhook_deliveries(endpoint_id,created_at desc);
create trigger webhook_deliveries_set_updated_at before update on public.webhook_deliveries for each row execute procedure public.set_updated_at();
alter table public.webhook_deliveries enable row level security;

alter table public.external_outbox drop constraint if exists external_outbox_provider_check;
alter table public.external_outbox add constraint external_outbox_provider_check
check(provider in ('resend','whatsapp_cloud','google_calendar','client_webhook'));

create or replace function public.enqueue_client_webhooks_from_event()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_endpoint record;v_delivery uuid;
begin
  if not public.service_organization_has_feature(new.organization_id,'outbound_webhooks') then return new; end if;
  for v_endpoint in
    select e.id,e.organization_id from public.webhook_endpoints e
    where e.organization_id=new.organization_id and e.status='active' and new.event_type=any(e.event_types)
  loop
    insert into public.webhook_deliveries(organization_id,endpoint_id,event_id,event_type)
    values(new.organization_id,v_endpoint.id,new.id,new.event_type)
    on conflict(endpoint_id,event_id) do nothing
    returning id into v_delivery;
    if v_delivery is null then select id into v_delivery from public.webhook_deliveries where endpoint_id=v_endpoint.id and event_id=new.id; end if;

    insert into public.external_outbox(organization_id,provider,kind,entity_type,entity_id,source_event_id,payload,dedupe_key)
    values(new.organization_id,'client_webhook',new.event_type,'webhook_delivery',v_delivery,new.id,
      jsonb_build_object(
        'delivery_id',v_delivery,'endpoint_id',v_endpoint.id,'event_id',new.id,'event_type',new.event_type,
        'entity_type',new.entity_type,'entity_id',new.entity_id,'occurred_at',new.created_at,'metadata',coalesce(new.metadata,'{}'::jsonb)
      ),
      'client_webhook:endpoint:'||v_endpoint.id::text||':event:'||new.id::text
    ) on conflict(dedupe_key) do nothing;
  end loop;
  return new;
end;
$$;
revoke all on function public.enqueue_client_webhooks_from_event() from public,anon,authenticated;
create trigger events_enqueue_client_webhooks after insert on public.events
for each row execute procedure public.enqueue_client_webhooks_from_event();

create or replace function public.list_webhook_endpoints(p_organization_id uuid)
returns table(id uuid,name text,url text,event_types text[],status text,signing_secret_prefix text,last_success_at timestamptz,last_failure_at timestamptz,last_error text,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select e.id,e.name,e.url,e.event_types,e.status,e.signing_secret_prefix,e.last_success_at,e.last_failure_at,e.last_error,e.created_at
  from public.webhook_endpoints e
  where e.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'outbound_webhooks')
  order by e.created_at desc;
$$;
revoke all on function public.list_webhook_endpoints(uuid) from public;
grant execute on function public.list_webhook_endpoints(uuid) to authenticated;

create or replace function public.list_webhook_deliveries(p_organization_id uuid,p_limit integer default 50)
returns table(id uuid,endpoint_id uuid,endpoint_name text,event_type text,status text,attempts integer,response_status integer,last_error text,delivered_at timestamptz,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select d.id,d.endpoint_id,e.name,d.event_type,d.status,d.attempts,d.response_status,d.last_error,d.delivered_at,d.created_at
  from public.webhook_deliveries d join public.webhook_endpoints e on e.id=d.endpoint_id
  where d.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'outbound_webhooks')
  order by d.created_at desc limit least(greatest(coalesce(p_limit,50),1),200);
$$;
revoke all on function public.list_webhook_deliveries(uuid,integer) from public;
grant execute on function public.list_webhook_deliveries(uuid,integer) to authenticated;

-- ============================================================================
-- 202608150025_white_label_domains.sql
-- ============================================================================

-- 2026-08-15 — White-label e domínios customizados verificados pelo provider de deploy.

update public.plans
set entitlements = coalesce(entitlements,'{}'::jsonb) || '{"white_label":false}'::jsonb,
    limits = '{"custom_domains":1}'::jsonb || coalesce(limits,'{}'::jsonb)
where not coalesce(entitlements,'{}'::jsonb) ? 'white_label';

create table public.organization_branding (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  brand_name text check(brand_name is null or char_length(brand_name) between 2 and 100),
  logo_url text,
  favicon_url text,
  primary_color text check(primary_color is null or primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  support_email text,
  hide_platform_branding boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.organization_branding enable row level security;
create policy organization_branding_select_member on public.organization_branding for select to authenticated
using(public.is_org_member(organization_id) and public.has_feature(organization_id,'white_label'));
create policy organization_branding_insert_admin on public.organization_branding for insert to authenticated
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'white_label'));
create policy organization_branding_update_admin on public.organization_branding for update to authenticated
using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'white_label'))
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'white_label'));

create table public.custom_domains (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  hostname text not null unique check(hostname=lower(hostname) and char_length(hostname) between 4 and 253),
  status text not null default 'pending' check(status in ('pending','verifying','active','error','disabled')),
  provider text not null default 'vercel' check(provider in ('vercel')),
  provider_verified boolean not null default false,
  provider_data jsonb not null default '{}'::jsonb check(jsonb_typeof(provider_data)='object'),
  is_primary boolean not null default false,
  last_checked_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index custom_domains_org_idx on public.custom_domains(organization_id,created_at desc);
create unique index custom_domains_one_primary_idx on public.custom_domains(organization_id) where is_primary=true and status='active';
create trigger custom_domains_set_updated_at before update on public.custom_domains for each row execute procedure public.set_updated_at();
alter table public.custom_domains enable row level security;
-- Gestão server-side; leitura segura por RPC para não expor provider_data completo.

create or replace function public.list_custom_domains(p_organization_id uuid)
returns table(id uuid,hostname text,status text,provider_verified boolean,is_primary boolean,verification jsonb,last_checked_at timestamptz,last_error text,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select d.id,d.hostname,d.status,d.provider_verified,d.is_primary,coalesce(d.provider_data->'verification','[]'::jsonb),d.last_checked_at,d.last_error,d.created_at
  from public.custom_domains d
  where d.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'white_label')
  order by d.is_primary desc,d.created_at desc;
$$;
revoke all on function public.list_custom_domains(uuid) from public;
grant execute on function public.list_custom_domains(uuid) to authenticated;

create or replace function public.resolve_public_custom_domain(p_hostname text)
returns text
language sql stable security definer set search_path=public as $$
  select o.slug
  from public.custom_domains d join public.organizations o on o.id=d.organization_id
  where d.hostname=lower(trim(p_hostname)) and d.status='active' and d.provider_verified=true and o.status='active'
    and public.service_organization_has_feature(o.id,'white_label')
  limit 1;
$$;
revoke all on function public.resolve_public_custom_domain(text) from public;
grant execute on function public.resolve_public_custom_domain(text) to anon,authenticated;

create or replace function public.get_public_branding(p_slug text)
returns jsonb
language sql stable security definer set search_path=public as $$
  select case when public.service_organization_has_feature(o.id,'white_label') then jsonb_build_object(
    'brand_name',b.brand_name,'logo_url',b.logo_url,'favicon_url',b.favicon_url,'primary_color',b.primary_color,
    'hide_platform_branding',coalesce(b.hide_platform_branding,true),
    'primary_domain',(select d.hostname from public.custom_domains d where d.organization_id=o.id and d.status='active' and d.provider_verified=true order by d.is_primary desc,d.created_at limit 1)
  ) else '{}'::jsonb end
  from public.organizations o left join public.organization_branding b on b.organization_id=o.id
  where o.slug=p_slug and o.status='active' limit 1;
$$;
revoke all on function public.get_public_branding(text) from public;
grant execute on function public.get_public_branding(text) to anon,authenticated;

-- ============================================================================
-- 202608150026_enterprise_units.sql
-- ============================================================================

-- 2026-08-15 — Fundação empresarial de múltiplas unidades e associação de membros.
-- Esta migration NÃO altera silenciosamente o escopo dos registros comerciais existentes.

update public.plans
set entitlements=coalesce(entitlements,'{}'::jsonb)||'{"multi_unit":false}'::jsonb,
    limits='{"units":5}'::jsonb||coalesce(limits,'{}'::jsonb)
where not coalesce(entitlements,'{}'::jsonb) ? 'multi_unit';

create table public.organization_units (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check(char_length(name) between 2 and 120),
  code text not null check(code ~ '^[A-Z0-9_-]{2,20}$'),
  phone text,
  email text,
  address text,
  city text,
  state text check(state is null or char_length(state)=2),
  timezone text not null default 'America/Sao_Paulo' check(char_length(timezone) between 3 and 80),
  status text not null default 'active' check(status in ('active','inactive')),
  is_headquarters boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,code),
  unique(organization_id,id)
);
create unique index organization_units_one_headquarters_idx on public.organization_units(organization_id) where is_headquarters=true and status='active';
create trigger organization_units_set_updated_at before update on public.organization_units for each row execute procedure public.set_updated_at();
alter table public.organization_units enable row level security;
create policy organization_units_select_member on public.organization_units for select to authenticated
using(public.is_org_member(organization_id) and public.has_feature(organization_id,'multi_unit'));
create policy organization_units_insert_admin on public.organization_units for insert to authenticated
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));
create policy organization_units_update_admin on public.organization_units for update to authenticated
using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'))
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));
create policy organization_units_delete_admin on public.organization_units for delete to authenticated
using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));

create table public.organization_member_units (
  organization_id uuid not null,
  user_id uuid not null,
  unit_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(organization_id,user_id,unit_id),
  foreign key(organization_id,user_id) references public.organization_members(organization_id,user_id) on delete cascade,
  foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete cascade
);
create index organization_member_units_unit_idx on public.organization_member_units(organization_id,unit_id);
alter table public.organization_member_units enable row level security;
create policy organization_member_units_select on public.organization_member_units for select to authenticated
using(public.has_feature(organization_id,'multi_unit') and (user_id=auth.uid() or public.has_org_role(organization_id,array['owner','admin'])));
create policy organization_member_units_insert_admin on public.organization_member_units for insert to authenticated
with check(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));
create policy organization_member_units_delete_admin on public.organization_member_units for delete to authenticated
using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'multi_unit'));

create or replace function public.member_can_access_unit(p_organization_id uuid,p_unit_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select case
    when p_unit_id is null then public.is_org_member(p_organization_id)
    when public.has_org_role(p_organization_id,array['owner','admin']) then true
    else exists(select 1 from public.organization_member_units mu where mu.organization_id=p_organization_id and mu.user_id=auth.uid() and mu.unit_id=p_unit_id)
  end;
$$;
revoke all on function public.member_can_access_unit(uuid,uuid) from public;
grant execute on function public.member_can_access_unit(uuid,uuid) to authenticated;

create or replace function public.list_enterprise_units(p_organization_id uuid)
returns table(id uuid,name text,code text,phone text,email text,address text,city text,state text,timezone text,status text,is_headquarters boolean,assigned_members bigint,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select u.id,u.name,u.code,u.phone,u.email,u.address,u.city,u.state,u.timezone,u.status,u.is_headquarters,
    (select count(*) from public.organization_member_units mu where mu.organization_id=u.organization_id and mu.unit_id=u.id),u.created_at
  from public.organization_units u
  where u.organization_id=p_organization_id and public.is_org_member(p_organization_id) and public.has_feature(p_organization_id,'multi_unit')
  order by u.is_headquarters desc,u.name;
$$;
revoke all on function public.list_enterprise_units(uuid) from public;
grant execute on function public.list_enterprise_units(uuid) to authenticated;

-- ============================================================================
-- 202608150027_unit_scoped_commercial.sql
-- ============================================================================

-- 2026-08-15 — Escopo comercial por unidade sem atribuir registros legados arbitrariamente.
-- unit_id NULL significa escopo geral da organização e preserva compatibilidade com dados existentes.

alter table public.leads add column if not exists unit_id uuid;
alter table public.customers add column if not exists unit_id uuid;
alter table public.quote_requests add column if not exists unit_id uuid;
alter table public.quotes add column if not exists unit_id uuid;
alter table public.quote_items add column if not exists unit_id uuid;
alter table public.tasks add column if not exists unit_id uuid;
alter table public.appointments add column if not exists unit_id uuid;
alter table public.events add column if not exists unit_id uuid;

do $$ begin
  alter table public.leads add constraint leads_unit_fk foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.customers add constraint customers_unit_fk foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.quote_requests add constraint quote_requests_unit_fk foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.quotes add constraint quotes_unit_fk foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.quote_items add constraint quote_items_unit_fk foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.tasks add constraint tasks_unit_fk foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.appointments add constraint appointments_unit_fk foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.events add constraint events_unit_fk foreign key(organization_id,unit_id) references public.organization_units(organization_id,id) on delete set null;
exception when duplicate_object then null; end $$;

create index if not exists leads_org_unit_idx on public.leads(organization_id,unit_id,created_at desc);
create index if not exists customers_org_unit_idx on public.customers(organization_id,unit_id,created_at desc);
create index if not exists quotes_org_unit_idx on public.quotes(organization_id,unit_id,created_at desc);
create index if not exists tasks_org_unit_idx on public.tasks(organization_id,unit_id,status,due_at);
create index if not exists appointments_org_unit_idx on public.appointments(organization_id,unit_id,starts_at);
create index if not exists events_org_unit_idx on public.events(organization_id,unit_id,created_at desc);

-- Copia escopo somente quando ele é inferível de uma relação real. Nada escolhe uma filial para registros gerais.
update public.customers c set unit_id=l.unit_id from public.leads l
where c.organization_id=l.organization_id and c.source_lead_id=l.id and c.unit_id is null and l.unit_id is not null;
update public.quote_requests qr set unit_id=l.unit_id from public.leads l
where qr.organization_id=l.organization_id and qr.lead_id=l.id and qr.unit_id is null and l.unit_id is not null;
update public.quotes q set unit_id=c.unit_id from public.customers c
where q.organization_id=c.organization_id and q.customer_id=c.id and q.unit_id is null and c.unit_id is not null;
update public.quotes q set unit_id=l.unit_id from public.leads l
where q.organization_id=l.organization_id and q.lead_id=l.id and q.unit_id is null and l.unit_id is not null;
update public.quote_items qi set unit_id=q.unit_id from public.quotes q
where qi.organization_id=q.organization_id and qi.quote_id=q.id and qi.unit_id is null and q.unit_id is not null;
update public.tasks t set unit_id=c.unit_id from public.customers c
where t.organization_id=c.organization_id and t.customer_id=c.id and t.unit_id is null and c.unit_id is not null;
update public.tasks t set unit_id=l.unit_id from public.leads l
where t.organization_id=l.organization_id and t.lead_id=l.id and t.unit_id is null and l.unit_id is not null;
update public.appointments a set unit_id=c.unit_id from public.customers c
where a.organization_id=c.organization_id and a.customer_id=c.id and a.unit_id is null and c.unit_id is not null;
update public.appointments a set unit_id=l.unit_id from public.leads l
where a.organization_id=l.organization_id and a.lead_id=l.id and a.unit_id is null and l.unit_id is not null;

create or replace function public.can_access_unit_scope(p_organization_id uuid,p_unit_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.is_org_member(p_organization_id)
    and (not public.has_feature(p_organization_id,'multi_unit') or public.member_can_access_unit(p_organization_id,p_unit_id));
$$;
revoke all on function public.can_access_unit_scope(uuid,uuid) from public;
grant execute on function public.can_access_unit_scope(uuid,uuid) to authenticated;

create or replace function public.user_can_access_unit(p_organization_id uuid,p_user_id uuid,p_unit_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=p_user_id and m.status='active')
    and (
      p_unit_id is null
      or exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=p_user_id and m.status='active' and m.role in('owner','admin'))
      or exists(select 1 from public.organization_member_units mu where mu.organization_id=p_organization_id and mu.user_id=p_user_id and mu.unit_id=p_unit_id)
    );
$$;
revoke all on function public.user_can_access_unit(uuid,uuid,uuid) from public;

create or replace function public.list_accessible_units(p_organization_id uuid)
returns table(id uuid,name text,code text,is_headquarters boolean)
language sql stable security definer set search_path=public as $$
  select u.id,u.name,u.code,u.is_headquarters
  from public.organization_units u
  where u.organization_id=p_organization_id and u.status='active'
    and public.can_access_unit_scope(p_organization_id,u.id)
  order by u.is_headquarters desc,u.name;
$$;
revoke all on function public.list_accessible_units(uuid) from public;
grant execute on function public.list_accessible_units(uuid) to authenticated;

-- Garante que relações comerciais ligadas a um lead/cliente/orçamento preservem o mesmo unit_id.
create or replace function public.sync_commercial_unit()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_lead uuid;v_customer uuid;v_quote uuid;v_inferred uuid;
begin
  if tg_table_name='customers' and new.source_lead_id is not null then
    select unit_id into v_inferred from public.leads where id=new.source_lead_id and organization_id=new.organization_id;
  elsif tg_table_name='quote_requests' then
    select unit_id into v_inferred from public.leads where id=new.lead_id and organization_id=new.organization_id;
  elsif tg_table_name='quotes' then
    if new.customer_id is not null then select unit_id into v_customer from public.customers where id=new.customer_id and organization_id=new.organization_id; end if;
    if new.lead_id is not null then select unit_id into v_lead from public.leads where id=new.lead_id and organization_id=new.organization_id; end if;
    if v_customer is not null and v_lead is not null and v_customer<>v_lead then raise exception 'unit mismatch'; end if;
    v_inferred:=coalesce(v_customer,v_lead);
  elsif tg_table_name='quote_items' then
    select unit_id into v_inferred from public.quotes where id=new.quote_id and organization_id=new.organization_id;
  elsif tg_table_name in('tasks','appointments') then
    if new.customer_id is not null then select unit_id into v_customer from public.customers where id=new.customer_id and organization_id=new.organization_id; end if;
    if new.lead_id is not null then select unit_id into v_lead from public.leads where id=new.lead_id and organization_id=new.organization_id; end if;
    if v_customer is not null and v_lead is not null and v_customer<>v_lead then raise exception 'unit mismatch'; end if;
    v_inferred:=coalesce(v_customer,v_lead);
  end if;
  if v_inferred is not null then
    if new.unit_id is not null and new.unit_id<>v_inferred then raise exception 'unit mismatch'; end if;
    new.unit_id:=v_inferred;
  end if;
  return new;
end; $$;
revoke all on function public.sync_commercial_unit() from public;

do $$ declare t text; begin
  foreach t in array array['customers','quote_requests','quotes','quote_items','tasks','appointments'] loop
    execute format('drop trigger if exists %I on public.%I',t||'_sync_unit',t);
    execute format('create trigger %I before insert or update on public.%I for each row execute procedure public.sync_commercial_unit()',t||'_sync_unit',t);
  end loop;
end $$;

-- Eventos herdam o escopo da entidade para a timeline não revelar outra unidade.
create or replace function public.sync_event_unit()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.entity_id is null then new.unit_id:=null; return new; end if;
  case new.entity_type
    when 'lead' then select unit_id into new.unit_id from public.leads where id=new.entity_id and organization_id=new.organization_id;
    when 'customer' then select unit_id into new.unit_id from public.customers where id=new.entity_id and organization_id=new.organization_id;
    when 'quote' then select unit_id into new.unit_id from public.quotes where id=new.entity_id and organization_id=new.organization_id;
    when 'quote_request' then select unit_id into new.unit_id from public.quote_requests where id=new.entity_id and organization_id=new.organization_id;
    when 'task' then select unit_id into new.unit_id from public.tasks where id=new.entity_id and organization_id=new.organization_id;
    when 'appointment' then select unit_id into new.unit_id from public.appointments where id=new.entity_id and organization_id=new.organization_id;
    else new.unit_id:=null;
  end case;
  return new;
end; $$;
revoke all on function public.sync_event_unit() from public;
drop trigger if exists events_sync_unit on public.events;
create trigger events_sync_unit before insert or update on public.events for each row execute procedure public.sync_event_unit();

-- Backfill de eventos inferíveis.
update public.events e set unit_id=l.unit_id from public.leads l where e.organization_id=l.organization_id and e.entity_type='lead' and e.entity_id=l.id and e.unit_id is distinct from l.unit_id;
update public.events e set unit_id=c.unit_id from public.customers c where e.organization_id=c.organization_id and e.entity_type='customer' and e.entity_id=c.id and e.unit_id is distinct from c.unit_id;
update public.events e set unit_id=q.unit_id from public.quotes q where e.organization_id=q.organization_id and e.entity_type='quote' and e.entity_id=q.id and e.unit_id is distinct from q.unit_id;
update public.events e set unit_id=a.unit_id from public.appointments a where e.organization_id=a.organization_id and e.entity_type='appointment' and e.entity_id=a.id and e.unit_id is distinct from a.unit_id;

-- RLS unit-aware. unit_id NULL permanece compartilhado dentro do tenant.
do $$ declare t text; f text; begin
  foreach t in array array['leads','customers'] loop
    f:='crm';
    execute format('drop policy if exists %I on public.%I',t||'_select_member',t);
    execute format('drop policy if exists %I on public.%I',t||'_insert_staff',t);
    execute format('drop policy if exists %I on public.%I',t||'_update_staff',t);
    execute format('drop policy if exists %I on public.%I',t||'_delete_admin',t);
    execute format('create policy %I on public.%I for select to authenticated using(public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id))',t||'_select_member',t,f);
    execute format('create policy %I on public.%I for insert to authenticated with check(public.has_org_role(organization_id,array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id))',t||'_insert_staff',t,f);
    execute format('create policy %I on public.%I for update to authenticated using(public.has_org_role(organization_id,array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id)) with check(public.has_org_role(organization_id,array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id))',t||'_update_staff',t,f,f);
    execute format('create policy %I on public.%I for delete to authenticated using(public.has_org_role(organization_id,array[''owner'',''admin'']) and public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id))',t||'_delete_admin',t,f);
  end loop;
  foreach t in array array['quote_requests','quotes','quote_items'] loop
    f:='quotes';
    execute format('drop policy if exists %I on public.%I',t||'_select_member',t);execute format('drop policy if exists %I on public.%I',t||'_insert_staff',t);execute format('drop policy if exists %I on public.%I',t||'_update_staff',t);execute format('drop policy if exists %I on public.%I',t||'_delete_admin',t);
    execute format('create policy %I on public.%I for select to authenticated using(public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id))',t||'_select_member',t,f);
    execute format('create policy %I on public.%I for insert to authenticated with check(public.has_org_role(organization_id,array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id))',t||'_insert_staff',t,f);
    execute format('create policy %I on public.%I for update to authenticated using(public.has_org_role(organization_id,array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id)) with check(public.has_org_role(organization_id,array[''owner'',''admin'',''sales'',''support'']) and public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id))',t||'_update_staff',t,f,f);
    execute format('create policy %I on public.%I for delete to authenticated using(public.has_org_role(organization_id,array[''owner'',''admin'']) and public.has_feature(organization_id,%L) and public.can_access_unit_scope(organization_id,unit_id))',t||'_delete_admin',t,f);
  end loop;
end $$;

drop policy if exists tasks_select_member on public.tasks;drop policy if exists tasks_insert_staff on public.tasks;drop policy if exists tasks_update_staff on public.tasks;drop policy if exists tasks_delete_admin on public.tasks;
create policy tasks_select_member on public.tasks for select to authenticated using(public.has_feature(organization_id,'tasks') and public.can_access_unit_scope(organization_id,unit_id));
create policy tasks_insert_staff on public.tasks for insert to authenticated with check(public.has_org_role(organization_id,array['owner','admin','sales','support']) and public.has_feature(organization_id,'tasks') and public.can_access_unit_scope(organization_id,unit_id));
create policy tasks_update_staff on public.tasks for update to authenticated using(public.has_org_role(organization_id,array['owner','admin','sales','support']) and public.has_feature(organization_id,'tasks') and public.can_access_unit_scope(organization_id,unit_id)) with check(public.has_org_role(organization_id,array['owner','admin','sales','support']) and public.has_feature(organization_id,'tasks') and public.can_access_unit_scope(organization_id,unit_id));
create policy tasks_delete_admin on public.tasks for delete to authenticated using(public.has_org_role(organization_id,array['owner','admin']) and public.has_feature(organization_id,'tasks') and public.can_access_unit_scope(organization_id,unit_id));

drop policy if exists appointments_select_member on public.appointments;
create policy appointments_select_member on public.appointments for select to authenticated using(public.has_feature(organization_id,'appointments') and public.can_access_unit_scope(organization_id,unit_id));

drop policy if exists events_select_member on public.events;
create policy events_select_member on public.events for select to authenticated using(public.can_access_unit_scope(organization_id,unit_id));
drop policy if exists events_insert_staff on public.events;
create policy events_insert_staff on public.events for insert to authenticated with check(public.has_org_role(organization_id,array['owner','admin','sales','support']) and actor_user_id=auth.uid() and event_type in('lead_created','lead_stage_changed','note_added','task_completed') and public.can_access_unit_scope(organization_id,unit_id));

-- Conversão preserva e valida o escopo da unidade.
create or replace function public.convert_lead_to_customer(p_organization_id uuid,p_lead_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_user_id uuid:=auth.uid();v_lead public.leads%rowtype;v_customer_id uuid;v_won_stage_id uuid;
begin
  if v_user_id is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'crm') then raise exception 'forbidden';end if;
  select * into v_lead from public.leads where id=p_lead_id and organization_id=p_organization_id for update;
  if v_lead.id is null or not public.can_access_unit_scope(p_organization_id,v_lead.unit_id) then raise exception 'lead not found';end if;
  select id into v_customer_id from public.customers where organization_id=p_organization_id and source_lead_id=p_lead_id limit 1;
  if v_customer_id is null then insert into public.customers(organization_id,unit_id,source_lead_id,name,phone,whatsapp,email,company,notes,created_by) values(p_organization_id,v_lead.unit_id,v_lead.id,v_lead.name,v_lead.phone,v_lead.whatsapp,v_lead.email,v_lead.company,v_lead.notes,v_user_id) returning id into v_customer_id;end if;
  select ps.id into v_won_stage_id from public.pipeline_stages ps where ps.organization_id=p_organization_id and ps.pipeline_id=v_lead.pipeline_id and ps.is_won=true order by ps.sort_order limit 1;
  update public.leads set stage_id=coalesce(v_won_stage_id,stage_id),status='won',updated_at=now() where id=v_lead.id and organization_id=p_organization_id;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata) values(p_organization_id,v_user_id,'customer',v_customer_id,'lead_converted_to_customer',jsonb_build_object('lead_id',v_lead.id));
  return v_customer_id;
end $$;
revoke all on function public.convert_lead_to_customer(uuid,uuid) from public;grant execute on function public.convert_lead_to_customer(uuid,uuid) to authenticated;

-- Recria orçamento preservando unidade do lead/cliente e bloqueando acesso cruzado.
create or replace function public.create_quote_with_items(p_organization_id uuid,p_lead_id uuid default null,p_customer_id uuid default null,p_notes text default null,p_valid_until date default null,p_discount_cents bigint default 0,p_fee_cents bigint default 0,p_items jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_user_id uuid:=auth.uid();v_quote_id uuid;v_subtotal bigint:=0;v_total bigint:=0;v_item jsonb;v_description text;v_type text;v_reference_id uuid;v_quantity numeric(12,3);v_unit_price bigint;v_line bigint;v_lead_unit uuid;v_customer_unit uuid;v_unit uuid;
begin
  if v_user_id is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'quotes') then raise exception 'forbidden';end if;
  if p_discount_cents<0 or p_fee_cents<0 or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'invalid quote';end if;
  if p_lead_id is not null then select unit_id into v_lead_unit from public.leads where id=p_lead_id and organization_id=p_organization_id;if not found then raise exception 'invalid lead';end if;end if;
  if p_customer_id is not null then select unit_id into v_customer_unit from public.customers where id=p_customer_id and organization_id=p_organization_id;if not found then raise exception 'invalid customer';end if;end if;
  if v_lead_unit is not null and v_customer_unit is not null and v_lead_unit<>v_customer_unit then raise exception 'unit mismatch';end if;v_unit:=coalesce(v_customer_unit,v_lead_unit);
  if not public.can_access_unit_scope(p_organization_id,v_unit) then raise exception 'forbidden';end if;
  insert into public.quotes(organization_id,unit_id,customer_id,lead_id,status,notes,valid_until,discount_cents,fee_cents,created_by) values(p_organization_id,v_unit,p_customer_id,p_lead_id,'draft',nullif(trim(p_notes),''),p_valid_until,p_discount_cents,p_fee_cents,v_user_id) returning id into v_quote_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_type:=coalesce(nullif(v_item->>'item_type',''),'custom');if v_type not in('product','service','custom') then raise exception 'invalid item type';end if;v_description:=trim(coalesce(v_item->>'description',''));if char_length(v_description)<1 or char_length(v_description)>1000 then raise exception 'invalid item description';end if;v_quantity:=coalesce((v_item->>'quantity')::numeric,1);v_unit_price:=coalesce((v_item->>'unit_price_cents')::bigint,0);if v_quantity<=0 or v_quantity>999999 or v_unit_price<0 then raise exception 'invalid item amount';end if;v_line:=round(v_quantity*v_unit_price)::bigint;v_subtotal:=v_subtotal+v_line;begin v_reference_id:=nullif(v_item->>'reference_id','')::uuid;exception when invalid_text_representation then v_reference_id:=null;end;
    insert into public.quote_items(organization_id,unit_id,quote_id,item_type,reference_id,description,quantity,unit_price_cents,total_cents) values(p_organization_id,v_unit,v_quote_id,v_type,v_reference_id,v_description,v_quantity,v_unit_price,v_line);
  end loop;
  v_total:=greatest(0,v_subtotal-p_discount_cents+p_fee_cents);update public.quotes set subtotal_cents=v_subtotal,total_cents=v_total where id=v_quote_id;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type) values(p_organization_id,v_user_id,'quote',v_quote_id,'quote_created');return v_quote_id;
end $$;
revoke all on function public.create_quote_with_items(uuid,uuid,uuid,text,date,bigint,bigint,jsonb) from public;grant execute on function public.create_quote_with_items(uuid,uuid,uuid,text,date,bigint,bigint,jsonb) to authenticated;

create or replace function public.publish_quote_link(p_organization_id uuid,p_quote_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare v_user_id uuid:=auth.uid();v_token text;v_unit uuid;
begin
  if v_user_id is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'quotes') then raise exception 'forbidden';end if;
  select unit_id into v_unit from public.quotes where id=p_quote_id and organization_id=p_organization_id;if not found or not public.can_access_unit_scope(p_organization_id,v_unit) then raise exception 'quote unavailable';end if;
  update public.quotes q set status=case when q.status='draft' then 'sent' else q.status end,updated_at=now() where q.id=p_quote_id and q.organization_id=p_organization_id and q.status in('draft','sent','viewed','change_requested') returning q.public_token into v_token;
  if v_token is null then raise exception 'quote unavailable';end if;insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type) values(p_organization_id,v_user_id,'quote',p_quote_id,'quote_link_enabled');return v_token;
end $$;
revoke all on function public.publish_quote_link(uuid,uuid) from public;grant execute on function public.publish_quote_link(uuid,uuid) to authenticated;

create or replace function public.schedule_lead_followup(p_organization_id uuid,p_lead_id uuid,p_local_datetime text)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare v_tz text;v_when timestamptz;v_unit uuid;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'crm') then raise exception 'forbidden';end if;
  select unit_id into v_unit from public.leads where organization_id=p_organization_id and id=p_lead_id;if not found or not public.can_access_unit_scope(p_organization_id,v_unit) then raise exception 'lead not found';end if;
  select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;begin v_when:=(p_local_datetime::timestamp at time zone v_tz);exception when others then raise exception 'invalid datetime';end;if v_when<now()-interval '5 minutes' or v_when>now()+interval '2 years' then raise exception 'invalid datetime';end if;
  update public.leads set next_contact_at=v_when,updated_at=now() where organization_id=p_organization_id and id=p_lead_id;insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata) values(p_organization_id,auth.uid(),'lead',p_lead_id,'note_added',jsonb_build_object('type','follow_up_scheduled','next_contact_at',v_when,'timezone',v_tz));return v_when;
end $$;
revoke all on function public.schedule_lead_followup(uuid,uuid,text) from public;grant execute on function public.schedule_lead_followup(uuid,uuid,text) to authenticated;

-- Appointments inferem a unidade do lead/cliente e validam profissional + operador.
create or replace function public.create_appointment(p_organization_id uuid,p_lead_id uuid,p_customer_id uuid,p_service_id uuid,p_professional_user_id uuid,p_local_start text,p_duration_minutes integer,p_notes text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_tz text;v_start timestamptz;v_end timestamptz;v_duration integer;v_id uuid;v_settings public.booking_settings%rowtype;v_lead_unit uuid;v_customer_unit uuid;v_unit uuid;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden';end if;
  select * into v_settings from public.booking_settings where organization_id=p_organization_id;select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;
  if p_lead_id is not null then select unit_id into v_lead_unit from public.leads where id=p_lead_id and organization_id=p_organization_id;if not found then raise exception 'lead not found';end if;end if;
  if p_customer_id is not null then select unit_id into v_customer_unit from public.customers where id=p_customer_id and organization_id=p_organization_id;if not found then raise exception 'customer not found';end if;end if;
  if v_lead_unit is not null and v_customer_unit is not null and v_lead_unit<>v_customer_unit then raise exception 'unit mismatch';end if;v_unit:=coalesce(v_customer_unit,v_lead_unit);if not public.can_access_unit_scope(p_organization_id,v_unit) then raise exception 'forbidden';end if;
  begin v_start:=(p_local_start::timestamp at time zone v_tz);exception when others then raise exception 'invalid datetime';end;if v_start<now()-interval '5 minutes' or v_start>now()+interval '2 years' then raise exception 'invalid datetime';end if;
  if p_service_id is not null and not exists(select 1 from public.services where id=p_service_id and organization_id=p_organization_id and active=true) then raise exception 'service not found';end if;
  if p_professional_user_id is not null and not public.user_can_access_unit(p_organization_id,p_professional_user_id,v_unit) then raise exception 'professional not available for unit';end if;
  v_duration:=coalesce(nullif(p_duration_minutes,0),(select duration_minutes from public.services where id=p_service_id),60);if v_duration not between 15 and 480 then raise exception 'invalid duration';end if;v_end:=v_start+make_interval(mins=>v_duration);
  if p_professional_user_id is not null and exists(select 1 from public.appointments a where a.organization_id=p_organization_id and a.professional_user_id=p_professional_user_id and a.status in('scheduled','confirmed') and tstzrange(a.starts_at-make_interval(mins=>coalesce(v_settings.buffer_minutes,0)),a.ends_at+make_interval(mins=>coalesce(v_settings.buffer_minutes,0)),'[)') && tstzrange(v_start,v_end,'[)')) then raise exception 'schedule conflict';end if;
  insert into public.appointments(organization_id,unit_id,lead_id,customer_id,service_id,professional_user_id,starts_at,ends_at,notes,source,created_by) values(p_organization_id,v_unit,p_lead_id,p_customer_id,p_service_id,p_professional_user_id,v_start,v_end,nullif(trim(coalesce(p_notes,'')),''),'internal',auth.uid()) returning id into v_id;
  insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata) values(p_organization_id,auth.uid(),'appointment',v_id,'appointment_created',jsonb_build_object('starts_at',v_start,'ends_at',v_end,'source','internal'));return v_id;
end $$;
revoke all on function public.create_appointment(uuid,uuid,uuid,uuid,uuid,text,integer,text) from public;grant execute on function public.create_appointment(uuid,uuid,uuid,uuid,uuid,text,integer,text) to authenticated;

create or replace function public.update_appointment_status(p_organization_id uuid,p_appointment_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
declare v_unit uuid;
begin
  if auth.uid() is null or not public.has_org_role(p_organization_id,array['owner','admin','sales','support']) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden';end if;if p_status not in('scheduled','confirmed','completed','canceled','no_show') then raise exception 'invalid status';end if;
  select unit_id into v_unit from public.appointments where id=p_appointment_id and organization_id=p_organization_id;if not found or not public.can_access_unit_scope(p_organization_id,v_unit) then raise exception 'appointment not found';end if;
  update public.appointments set status=p_status,updated_at=now() where id=p_appointment_id and organization_id=p_organization_id;insert into public.events(organization_id,actor_user_id,entity_type,entity_id,event_type,metadata) values(p_organization_id,auth.uid(),'appointment',p_appointment_id,'appointment_status_changed',jsonb_build_object('status',p_status));
end $$;
revoke all on function public.update_appointment_status(uuid,uuid,text) from public;grant execute on function public.update_appointment_status(uuid,uuid,text) to authenticated;

create or replace function public.appointments_calendar(p_organization_id uuid,p_date date,p_view text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_tz text;v_view text:=lower(coalesce(p_view,'week'));v_anchor date:=coalesce(p_date,(now() at time zone 'America/Sao_Paulo')::date);v_start_date date;v_end_date date;v_start timestamptz;v_end timestamptz;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) or not public.has_feature(p_organization_id,'appointments') then raise exception 'forbidden';end if;if v_view not in('day','week','month') then v_view:='week';end if;select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;if p_date is null then v_anchor:=(now() at time zone v_tz)::date;end if;
  if v_view='day' then v_start_date:=v_anchor;v_end_date:=v_anchor+1;elsif v_view='week' then v_start_date:=date_trunc('week',v_anchor::timestamp)::date;v_end_date:=v_start_date+7;else v_start_date:=date_trunc('month',v_anchor::timestamp)::date;v_end_date:=(v_start_date+interval '1 month')::date;end if;v_start:=(v_start_date::timestamp at time zone v_tz);v_end:=(v_end_date::timestamp at time zone v_tz);
  return jsonb_build_object('view',v_view,'timezone',v_tz,'anchor',v_anchor,'start_date',v_start_date,'end_date',(v_end_date-1),'appointments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'unit_id',a.unit_id,'starts_at',a.starts_at,'ends_at',a.ends_at,'status',a.status,'source',a.source,'name',coalesce(c.name,l.name,a.contact_name,'Contato'),'service',s.name,'professional',p.full_name) order by a.starts_at) from public.appointments a left join public.customers c on c.id=a.customer_id and c.organization_id=a.organization_id left join public.leads l on l.id=a.lead_id and l.organization_id=a.organization_id left join public.services s on s.id=a.service_id and s.organization_id=a.organization_id left join public.profiles p on p.id=a.professional_user_id where a.organization_id=p_organization_id and a.starts_at<v_end and a.ends_at>v_start and public.can_access_unit_scope(a.organization_id,a.unit_id)),'[]'::jsonb));
end $$;
revoke all on function public.appointments_calendar(uuid,date,text) from public;grant execute on function public.appointments_calendar(uuid,date,text) to authenticated;

-- Dashboard respeita unidades atribuídas para membros não administrativos.
create or replace function public.organization_dashboard_summary(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_tz text;v_day_start timestamptz;v_day_end timestamptz;v_month_start timestamptz;v_previous_month_start timestamptz;v_crm boolean;v_quotes boolean;v_tasks boolean;v_appointments boolean;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then raise exception 'forbidden';end if;select coalesce(timezone,'America/Sao_Paulo') into v_tz from public.organizations where id=p_organization_id;v_day_start:=(date_trunc('day',now() at time zone v_tz) at time zone v_tz);v_day_end:=v_day_start+interval '1 day';v_month_start:=(date_trunc('month',now() at time zone v_tz) at time zone v_tz);v_previous_month_start:=v_month_start-interval '1 month';v_crm:=public.has_feature(p_organization_id,'crm');v_quotes:=public.has_feature(p_organization_id,'quotes');v_tasks:=public.has_feature(p_organization_id,'tasks');v_appointments:=public.has_feature(p_organization_id,'appointments');
  return jsonb_build_object('timezone',v_tz,
    'leads_today',(select count(*) from public.leads where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and created_at>=v_day_start and created_at<v_day_end),
    'leads_month',(select count(*) from public.leads where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and created_at>=v_month_start),
    'leads_previous_month',(select count(*) from public.leads where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and created_at>=v_previous_month_start and created_at<v_month_start),
    'leads_total',(select count(*) from public.leads where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id)),
    'potential_value_cents',coalesce((select sum(potential_value_cents) from public.leads where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and status not in('won','lost')),0),
    'customers_total',case when v_crm then(select count(*) from public.customers where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id)) else null end,
    'followups_due',case when v_crm then(select count(*) from public.leads where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and next_contact_at is not null and next_contact_at<v_day_end and status not in('won','lost')) else null end,
    'quotes_pending',case when v_quotes then(select count(*) from public.quotes where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and status in('draft','sent','viewed','change_requested')) else null end,
    'quotes_month',case when v_quotes then(select count(*) from public.quotes where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and created_at>=v_month_start) else null end,
    'tasks_open',case when v_tasks then(select count(*) from public.tasks where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and status in('open','in_progress')) else null end,
    'tasks_overdue',case when v_tasks then(select count(*) from public.tasks where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and status in('open','in_progress') and due_at is not null and due_at<now()) else null end,
    'appointments_today',case when v_appointments then(select count(*) from public.appointments where organization_id=p_organization_id and public.can_access_unit_scope(organization_id,unit_id) and status in('scheduled','confirmed') and starts_at>=v_day_start and starts_at<v_day_end) else null end);
end $$;
revoke all on function public.organization_dashboard_summary(uuid) from public;grant execute on function public.organization_dashboard_summary(uuid) to authenticated;

-- Analytics de visita é organizacional. Em multiunidade ele permanece disponível apenas a owner/admin até existir atribuição de visitas por unidade.
alter function public.organization_analytics_summary(uuid,integer) rename to organization_analytics_summary_orgwide;
revoke all on function public.organization_analytics_summary_orgwide(uuid,integer) from public;
revoke all on function public.organization_analytics_summary_orgwide(uuid,integer) from authenticated;
create or replace function public.organization_analytics_summary(p_organization_id uuid,p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) or not public.has_feature(p_organization_id,'analytics') then raise exception 'forbidden';end if;
  if public.has_feature(p_organization_id,'multi_unit') and not public.has_org_role(p_organization_id,array['owner','admin']) then raise exception 'analytics requires organization admin in multi-unit mode';end if;
  return public.organization_analytics_summary_orgwide(p_organization_id,p_days);
end $$;
revoke all on function public.organization_analytics_summary(uuid,integer) from public;grant execute on function public.organization_analytics_summary(uuid,integer) to authenticated;

-- Fan-out respeita a unidade do evento para não notificar membros de outra filial.
create or replace function public.fanout_event_notification()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_title text;v_body text;v_kind text:='info';v_pref_key text:='leads';
begin
  case new.event_type
    when 'quote_request_received' then v_title:='Novo pedido de orçamento';v_body:='Um novo contato chegou pelo site e precisa de atendimento.';v_pref_key:='leads';
    when 'quote_response' then v_pref_key:='quotes';if coalesce(new.metadata->>'status','')='approved' then v_title:='Orçamento aprovado';v_body:='O cliente aprovou um orçamento.';v_kind:='success';elsif coalesce(new.metadata->>'status','')='change_requested' then v_title:='Cliente pediu alteração';v_body:='Um orçamento recebeu uma solicitação de alteração.';v_kind:='warning';elsif coalesce(new.metadata->>'status','')='rejected' then v_title:='Orçamento recusado';v_body:='Um cliente recusou um orçamento.';v_kind:='warning';else return new;end if;
    when 'lead_converted_to_customer' then v_title:='Novo cliente';v_body:='Um lead foi convertido em cliente.';v_kind:='success';v_pref_key:='leads';
    when 'subscription_status_changed' then v_title:='Assinatura atualizada';v_body:='O status da assinatura mudou para '||coalesce(new.metadata->>'status','desconhecido')||'.';v_kind:='billing';v_pref_key:='billing';
    when 'appointment_created' then v_title:='Novo agendamento';v_pref_key:='appointments';v_body:=case when coalesce(new.metadata->>'source','')='public' then 'Um cliente realizou um agendamento pelo site.' else 'Um novo compromisso foi adicionado à agenda.' end;
    when 'appointment_status_changed' then v_title:='Agendamento atualizado';v_pref_key:='appointments';v_body:='O status de um agendamento foi alterado para '||coalesce(new.metadata->>'status','desconhecido')||'.';
    else return new;
  end case;
  insert into public.notifications(organization_id,user_id,source_event_id,kind,title,body,entity_type,entity_id)
  select new.organization_id,m.user_id,new.id,v_kind,v_title,v_body,new.entity_type,new.entity_id from public.organization_members m left join public.profiles p on p.id=m.user_id
  where m.organization_id=new.organization_id and m.status='active' and coalesce(p.notification_preferences->>v_pref_key,'true')='true' and (new.actor_user_id is null or m.user_id<>new.actor_user_id)
    and (not public.organization_has_entitlement(new.organization_id,'multi_unit') or public.user_can_access_unit(new.organization_id,m.user_id,new.unit_id))
  on conflict(source_event_id,user_id) do nothing;return new;
end $$;
revoke all on function public.fanout_event_notification() from public;revoke all on function public.fanout_event_notification() from anon;revoke all on function public.fanout_event_notification() from authenticated;

-- ============================================================================
-- 202608150028_developer_observability.sql
-- ============================================================================

-- 2026-08-15 — Observabilidade segura da API pública e retry manual de Webhooks falhados.
-- Não armazena/exibe corpo, Authorization, IP, API key completa ou segredo de assinatura.

create or replace function public.list_api_request_logs(
  p_organization_id uuid,
  p_limit integer default 50
)
returns table(
  id bigint,
  key_prefix text,
  scope text,
  method text,
  route text,
  response_status integer,
  duration_ms integer,
  request_id text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path=public
as $$
  select
    l.id,
    coalesce(k.key_prefix,'revogada') as key_prefix,
    l.scope,
    l.method,
    l.route,
    l.response_status,
    l.duration_ms,
    l.request_id,
    l.created_at
  from public.api_request_logs l
  left join public.api_keys k on k.id=l.api_key_id
  where l.organization_id=p_organization_id
    and public.has_org_role(p_organization_id,array['owner','admin'])
    and public.has_feature(p_organization_id,'public_api')
  order by l.created_at desc
  limit least(greatest(coalesce(p_limit,50),1),200);
$$;
revoke all on function public.list_api_request_logs(uuid,integer) from public;
grant execute on function public.list_api_request_logs(uuid,integer) to authenticated;

create or replace function public.retry_webhook_delivery(
  p_organization_id uuid,
  p_delivery_id uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_delivery public.webhook_deliveries%rowtype;
  v_endpoint public.webhook_endpoints%rowtype;
  v_job public.external_outbox%rowtype;
begin
  if auth.uid() is null
     or not public.has_org_role(p_organization_id,array['owner','admin'])
     or not public.has_feature(p_organization_id,'outbound_webhooks') then
    raise exception 'forbidden';
  end if;

  select * into v_delivery
  from public.webhook_deliveries
  where id=p_delivery_id and organization_id=p_organization_id
  for update;
  if v_delivery.id is null then raise exception 'delivery not found'; end if;
  if v_delivery.status<>'failed' then raise exception 'delivery is not failed'; end if;

  select * into v_endpoint
  from public.webhook_endpoints
  where id=v_delivery.endpoint_id and organization_id=p_organization_id
  for update;
  if v_endpoint.id is null or v_endpoint.status<>'active' then
    raise exception 'webhook endpoint is not active';
  end if;

  select * into v_job
  from public.external_outbox
  where organization_id=p_organization_id
    and provider='client_webhook'
    and entity_type='webhook_delivery'
    and entity_id=p_delivery_id
  order by created_at desc
  limit 1
  for update;
  if v_job.id is null then raise exception 'outbox job not found'; end if;
  if v_job.status<>'dead_letter' then raise exception 'outbox job is not dead letter'; end if;

  update public.external_outbox
  set status='pending',attempts=0,available_at=now(),locked_at=null,locked_by=null,
      provider_message_id=null,last_error=null,sent_at=null,updated_at=now()
  where id=v_job.id;

  update public.webhook_deliveries
  set status='queued',attempts=0,response_status=null,last_error=null,delivered_at=null,updated_at=now()
  where id=p_delivery_id;

  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(
    p_organization_id,auth.uid(),'webhook_delivery.manual_retry','webhook_delivery',p_delivery_id,
    jsonb_build_object('endpoint_id',v_delivery.endpoint_id,'event_type',v_delivery.event_type,'outbox_job_id',v_job.id)
  );
end;
$$;
revoke all on function public.retry_webhook_delivery(uuid,uuid) from public;
grant execute on function public.retry_webhook_delivery(uuid,uuid) to authenticated;

-- ============================================================================
-- 202608150029_unit_notification_guards.sql
-- ============================================================================

-- 2026-08-15 — Defesa em profundidade para comunicações/notificações em organizações multiunidade.
-- Garante que destinatários internos não recebam conteúdo de uma filial à qual não possuem acesso.

create or replace function public.guard_notification_unit_scope()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_unit uuid;
begin
  if new.user_id is null or not public.organization_has_entitlement(new.organization_id,'multi_unit') or new.entity_id is null then
    return new;
  end if;

  case new.entity_type
    when 'lead' then select unit_id into v_unit from public.leads where organization_id=new.organization_id and id=new.entity_id;
    when 'customer' then select unit_id into v_unit from public.customers where organization_id=new.organization_id and id=new.entity_id;
    when 'quote' then select unit_id into v_unit from public.quotes where organization_id=new.organization_id and id=new.entity_id;
    when 'task' then select unit_id into v_unit from public.tasks where organization_id=new.organization_id and id=new.entity_id;
    when 'appointment' then select unit_id into v_unit from public.appointments where organization_id=new.organization_id and id=new.entity_id;
    else v_unit:=null;
  end case;

  if v_unit is not null and not public.user_can_access_unit(new.organization_id,new.user_id,v_unit) then
    return null;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_notification_unit_scope() from public,anon,authenticated;

drop trigger if exists notifications_guard_unit_scope on public.notifications;
create trigger notifications_guard_unit_scope
before insert on public.notifications
for each row execute procedure public.guard_notification_unit_scope();

create or replace function public.guard_external_outbox_unit_recipient()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_unit uuid;
begin
  if new.recipient_user_id is null or new.source_event_id is null or not public.organization_has_entitlement(new.organization_id,'multi_unit') then
    return new;
  end if;
  select unit_id into v_unit from public.events where id=new.source_event_id and organization_id=new.organization_id;
  if v_unit is not null and not public.user_can_access_unit(new.organization_id,new.recipient_user_id,v_unit) then
    return null;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_external_outbox_unit_recipient() from public,anon,authenticated;

drop trigger if exists external_outbox_guard_unit_recipient on public.external_outbox;
create trigger external_outbox_guard_unit_recipient
before insert on public.external_outbox
for each row execute procedure public.guard_external_outbox_unit_recipient();

-- ============================================================================
-- 202608150030_admin_developer_observability.sql
-- ============================================================================

-- 2026-08-15 — Observabilidade agregada de API/Webhooks/outbox para o admin master.
-- Somente metadados operacionais: nenhum payload, Authorization, IP, segredo, URL sensível ou corpo de resposta.

create or replace function public.admin_developer_observability(p_hours integer default 24)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_since timestamptz;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'forbidden';
  end if;

  p_hours := least(greatest(coalesce(p_hours,24),1),720);
  v_since := now() - make_interval(hours => p_hours);

  select jsonb_build_object(
    'hours', p_hours,
    'generated_at', now(),
    'api', jsonb_build_object(
      'requests', (select count(*) from public.api_request_logs l where l.created_at >= v_since),
      'errors', (select count(*) from public.api_request_logs l where l.created_at >= v_since and l.response_status >= 400),
      'organizations', (select count(distinct l.organization_id) from public.api_request_logs l where l.created_at >= v_since),
      'active_keys', (select count(*) from public.api_keys k where k.status='active' and (k.expires_at is null or k.expires_at>now())),
      'top_routes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'method',r.method,'route',r.route,'requests',r.requests,'errors',r.errors
        ) order by r.requests desc,r.route)
        from (
          select l.method,l.route,count(*)::bigint requests,
                 count(*) filter(where l.response_status>=400)::bigint errors
          from public.api_request_logs l
          where l.created_at>=v_since
          group by l.method,l.route
          order by count(*) desc,l.route
          limit 10
        ) r
      ),'[]'::jsonb),
      'top_organizations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'organization_id',r.organization_id,'organization_name',r.organization_name,
          'requests',r.requests,'errors',r.errors
        ) order by r.requests desc,r.organization_name)
        from (
          select o.id organization_id,o.name organization_name,count(*)::bigint requests,
                 count(*) filter(where l.response_status>=400)::bigint errors
          from public.api_request_logs l
          join public.organizations o on o.id=l.organization_id
          where l.created_at>=v_since
          group by o.id,o.name
          order by count(*) desc,o.name
          limit 10
        ) r
      ),'[]'::jsonb)
    ),
    'webhooks', jsonb_build_object(
      'deliveries', (select count(*) from public.webhook_deliveries d where d.created_at>=v_since),
      'delivered', (select count(*) from public.webhook_deliveries d where d.created_at>=v_since and d.status='delivered'),
      'failed', (select count(*) from public.webhook_deliveries d where d.created_at>=v_since and d.status='failed'),
      'active_endpoints', (select count(*) from public.webhook_endpoints e where e.status='active'),
      'dead_letters', (select count(*) from public.external_outbox o where o.provider='client_webhook' and o.status='dead_letter'),
      'top_organizations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'organization_id',r.organization_id,'organization_name',r.organization_name,
          'deliveries',r.deliveries,'delivered',r.delivered,'failed',r.failed
        ) order by r.deliveries desc,r.organization_name)
        from (
          select o.id organization_id,o.name organization_name,count(*)::bigint deliveries,
                 count(*) filter(where d.status='delivered')::bigint delivered,
                 count(*) filter(where d.status='failed')::bigint failed
          from public.webhook_deliveries d
          join public.organizations o on o.id=d.organization_id
          where d.created_at>=v_since
          group by o.id,o.name
          order by count(*) desc,o.name
          limit 10
        ) r
      ),'[]'::jsonb)
    ),
    'outbox', jsonb_build_object(
      'pending', (select count(*) from public.external_outbox o where o.status='pending'),
      'retry', (select count(*) from public.external_outbox o where o.status='retry'),
      'processing', (select count(*) from public.external_outbox o where o.status='processing'),
      'dead_letter', (select count(*) from public.external_outbox o where o.status='dead_letter'),
      'sent_window', (select count(*) from public.external_outbox o where o.status='sent' and o.sent_at>=v_since),
      'providers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'provider',r.provider,'pending',r.pending,'retry',r.retry,
          'processing',r.processing,'dead_letter',r.dead_letter,'sent_window',r.sent_window
        ) order by r.provider)
        from (
          select o.provider,
                 count(*) filter(where o.status='pending')::bigint pending,
                 count(*) filter(where o.status='retry')::bigint retry,
                 count(*) filter(where o.status='processing')::bigint processing,
                 count(*) filter(where o.status='dead_letter')::bigint dead_letter,
                 count(*) filter(where o.status='sent' and o.sent_at>=v_since)::bigint sent_window
          from public.external_outbox o
          group by o.provider
        ) r
      ),'[]'::jsonb)
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_developer_observability(integer) from public;
grant execute on function public.admin_developer_observability(integer) to authenticated;

-- ============================================================================
-- 202608150031_security_definer_acl_hardening.sql
-- ============================================================================

-- 2026-08-15 — Hardening de ACL para funções SECURITY DEFINER internas.
-- Funções de trigger não precisam ser executáveis por clientes REST/Auth.
-- O trigger continua podendo invocá-las normalmente após o REVOKE.

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.activate_invited_memberships() from public, anon, authenticated;
revoke all on function public.initialize_organization_trial() from public, anon, authenticated;
revoke all on function public.initialize_site_sections() from public, anon, authenticated;
revoke all on function public.enforce_quote_request_entitlement() from public, anon, authenticated;

-- Garantias adicionais para helpers internos que só são consumidos por outras funções/triggers.
revoke all on function public.organization_has_entitlement(uuid,text) from public, anon, authenticated;
revoke all on function public.user_can_access_unit(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.sync_commercial_unit() from public, anon, authenticated;
revoke all on function public.sync_event_unit() from public, anon, authenticated;

-- ============================================================================
-- 202608150032_data_api_explicit_grants.sql
-- ============================================================================

-- 2026-08-15 — Compatibilidade com novos projetos Supabase/Data API.
-- Desde 2026, novas tabelas podem não receber grants implícitos para anon/authenticated.
-- RLS continua sendo a camada de autorização por linha; estes grants apenas tornam
-- as tabelas deliberadamente alcançáveis pelo PostgREST/supabase-js.

-- Nenhuma tabela fica diretamente exposta ao visitante anônimo por padrão.
revoke all privileges on all tables in schema public from anon;

-- A página pública de planos consulta a tabela diretamente; a policy existente
-- plans_public_read limita a active = true.
grant select on table public.plans to anon;

-- Usuários autenticados usam o Data API em vários módulos. Todas as tabelas da
-- aplicação possuem RLS; tabelas internas sem policies permanecem deny-by-default.
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Workers/backend usam service_role e precisam operar as tabelas internas.
grant all privileges on all tables in schema public to service_role;

-- Mantém o mesmo comportamento para tabelas criadas por migrations futuras.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant all privileges on tables to service_role;

-- ============================================================================
-- 202608150033_security_advisor_hardening.sql
-- ============================================================================

-- 2026-08-15 — Hardening final após Supabase Security Advisor.
-- Revoga EXECUTE anônimo de SECURITY DEFINER por padrão e reabre somente RPCs públicas deliberadas.

alter function public.set_updated_at() set search_path = public;
alter function public.safe_slug(text) set search_path = public;

-- btree_gist foi instalada para Agenda, mas não há índice/exclusion constraint GiST dependente dela.
-- Os operadores tstzrange usados pela aplicação são nativos do PostgreSQL.
drop extension if exists btree_gist;

-- Supabase/Postgres pode conceder EXECUTE a PUBLIC por padrão em funções novas.
-- Fechamos todas as SECURITY DEFINER e depois reabrimos apenas a allowlist pública.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from public, anon', r.signature);
  end loop;
end
$$;

-- RPCs públicas deliberadas. Elas retornam apenas projeções públicas e/ou validam inputs internamente.
grant execute on function public.get_public_site(text) to anon, authenticated;
grant execute on function public.get_public_quote(text) to anon, authenticated;
grant execute on function public.respond_public_quote(text,text) to anon, authenticated;
grant execute on function public.public_create_quote_request(text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.public_create_quote_request(text,text,text,text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.get_public_booking(text) to anon, authenticated;
grant execute on function public.public_create_appointment(text,uuid,text,text,text) to anon, authenticated;
grant execute on function public.resolve_public_custom_domain(text) to anon, authenticated;
grant execute on function public.get_public_branding(text) to anon, authenticated;
grant execute on function public.list_public_sites() to anon, authenticated;

-- Funções service_* são exclusivamente backend/service role.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname like 'service\_%' escape '\\'
  loop
    execute format('revoke execute on function %s from authenticated', r.signature);
    execute format('grant execute on function %s to service_role', r.signature);
  end loop;
end
$$;

-- Helpers/Workers internos que não são endpoints RPC de usuário.
revoke execute on function public.apply_coupon_redemption(uuid) from authenticated;
revoke execute on function public.record_site_visit(text,text,text,text,text,text,text,text,text) from authenticated;
revoke execute on function public.run_temporal_automations(timestamptz,integer) from authenticated;
revoke execute on function public.execute_temporal_automation_actions(uuid,uuid,uuid,text,uuid,text) from authenticated;
revoke execute on function public.organization_analytics_summary_orgwide(uuid,integer) from authenticated;
revoke execute on function public.organization_has_entitlement(uuid,text) from authenticated;
revoke execute on function public.user_can_access_unit(uuid,uuid,uuid) from authenticated;

grant execute on function public.apply_coupon_redemption(uuid) to service_role;
grant execute on function public.record_site_visit(text,text,text,text,text,text,text,text,text) to service_role;
grant execute on function public.run_temporal_automations(timestamptz,integer) to service_role;
grant execute on function public.execute_temporal_automation_actions(uuid,uuid,uuid,text,uuid,text) to service_role;

-- Tabelas internas são acessadas somente via RPC/backend. RLS já é deny-by-default;
-- removemos também privilégios diretos da role authenticated por least privilege.
revoke all privileges on table public.api_keys from authenticated;
revoke all privileges on table public.api_request_logs from authenticated;
revoke all privileges on table public.api_usage_windows from authenticated;
revoke all privileges on table public.billing_webhook_events from authenticated;
revoke all privileges on table public.coupon_redemptions from authenticated;
revoke all privileges on table public.coupons from authenticated;
revoke all privileges on table public.custom_domains from authenticated;
revoke all privileges on table public.external_outbox from authenticated;
revoke all privileges on table public.integration_secrets from authenticated;
revoke all privileges on table public.oauth_states from authenticated;
revoke all privileges on table public.provider_webhook_events from authenticated;
revoke all privileges on table public.rate_limit_windows from authenticated;
revoke all privileges on table public.webhook_deliveries from authenticated;
revoke all privileges on table public.webhook_endpoint_secrets from authenticated;
revoke all privileges on table public.webhook_endpoints from authenticated;

-- ============================================================================
-- 202608150034_performance_advisor_hardening.sql
-- ============================================================================

-- 2026-08-15 — Ajustes objetivos apontados pelo Supabase Performance Advisor.
-- Não removemos índices 'unused' em banco recém-criado: ainda não existe carga real para medir uso.

-- Evita reavaliar auth.uid() por linha nas policies sinalizadas.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists platform_admins_select_self on public.platform_admins;
create policy platform_admins_select_self on public.platform_admins
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()) and public.is_org_member(organization_id));

drop policy if exists organization_member_units_select on public.organization_member_units;
create policy organization_member_units_select on public.organization_member_units
  for select to authenticated
  using (
    public.has_feature(organization_id,'multi_unit')
    and (user_id = (select auth.uid()) or public.has_org_role(organization_id,array['owner','admin']))
  );

drop policy if exists events_insert_staff on public.events;
create policy events_insert_staff on public.events
  for insert to authenticated
  with check (
    public.has_org_role(organization_id,array['owner','admin','sales','support'])
    and actor_user_id = (select auth.uid())
    and event_type in ('lead_created','lead_stage_changed','note_added','task_completed')
    and public.can_access_unit_scope(organization_id,unit_id)
  );

-- FKs mais usadas em joins, deleções/cascatas e filtros operacionais.
create index if not exists appointments_customer_idx on public.appointments(customer_id) where customer_id is not null;
create index if not exists appointments_lead_idx on public.appointments(lead_id) where lead_id is not null;
create index if not exists appointments_service_idx on public.appointments(service_id) where service_id is not null;
create index if not exists appointment_external_events_org_idx on public.appointment_external_events(organization_id);
create index if not exists audit_logs_org_idx on public.audit_logs(organization_id) where organization_id is not null;
create index if not exists automation_runs_source_event_idx on public.automation_runs(source_event_id) where source_event_id is not null;
create index if not exists billing_checkout_plan_idx on public.billing_checkout_sessions(plan_id);
create index if not exists billing_checkout_coupon_idx on public.billing_checkout_sessions(coupon_id) where coupon_id is not null;
create index if not exists billing_webhook_org_idx on public.billing_webhook_events(organization_id) where organization_id is not null;
create index if not exists communication_messages_lead_fk_idx on public.communication_messages(lead_id) where lead_id is not null;
create index if not exists communication_messages_customer_fk_idx on public.communication_messages(customer_id) where customer_id is not null;
create index if not exists coupon_redemptions_org_idx on public.coupon_redemptions(organization_id);
create index if not exists customers_source_lead_idx on public.customers(source_lead_id) where source_lead_id is not null;
create index if not exists external_outbox_source_event_idx on public.external_outbox(source_event_id) where source_event_id is not null;
create index if not exists leads_pipeline_idx on public.leads(pipeline_id) where pipeline_id is not null;
create index if not exists leads_stage_idx on public.leads(stage_id) where stage_id is not null;
create index if not exists leads_responsible_idx on public.leads(responsible_user_id) where responsible_user_id is not null;
create index if not exists notifications_org_idx on public.notifications(organization_id);
create index if not exists oauth_states_org_idx on public.oauth_states(organization_id);
create index if not exists oauth_states_user_idx on public.oauth_states(user_id);
create index if not exists pipeline_stages_org_idx on public.pipeline_stages(organization_id);
create index if not exists pipelines_org_fk_idx on public.pipelines(organization_id);
create index if not exists products_category_idx on public.products(category_id) where category_id is not null;
create index if not exists services_category_idx on public.services(category_id) where category_id is not null;
create index if not exists quote_items_quote_idx on public.quote_items(quote_id);
create index if not exists quote_requests_lead_idx on public.quote_requests(lead_id);
create index if not exists quotes_customer_idx on public.quotes(customer_id) where customer_id is not null;
create index if not exists quotes_lead_idx on public.quotes(lead_id) where lead_id is not null;
create index if not exists site_sections_org_idx on public.site_sections(organization_id);
create index if not exists subscriptions_org_idx on public.subscriptions(organization_id);
create index if not exists subscriptions_plan_idx on public.subscriptions(plan_id);
create index if not exists tasks_assigned_idx on public.tasks(assigned_to) where assigned_to is not null;
create index if not exists tasks_customer_idx on public.tasks(customer_id) where customer_id is not null;
create index if not exists tasks_lead_idx on public.tasks(lead_id) where lead_id is not null;
create index if not exists webhook_deliveries_event_idx on public.webhook_deliveries(event_id);

-- ============================================================================
-- 202608150035_temporal_automation_cron.sql
-- ============================================================================

-- 2026-08-15 — Scheduler real das automações temporais no Supabase Cron.
-- O mesmo nome de job atualiza/substitui a definição anterior de forma idempotente.

create extension if not exists pg_cron;

select cron.schedule(
  'platform-temporal-automations',
  '*/5 * * * *',
  $$select public.run_temporal_automations(now(), 500);$$
);

-- ============================================================================
-- 202608150036_unit_visibility_hardening.sql
-- ============================================================================

-- 2026-08-15 — Hardening de visibilidade multiunidade.
-- Membros restritos só podem ler unidades explicitamente atribuídas.
-- Owners/admins continuam com visão completa da organização.

drop policy if exists organization_units_select_member on public.organization_units;
create policy organization_units_select_member on public.organization_units
for select to authenticated
using (
  public.has_feature(organization_id, 'multi_unit')
  and public.can_access_unit_scope(organization_id, id)
);

create or replace function public.list_enterprise_units(p_organization_id uuid)
returns table(
  id uuid,
  name text,
  code text,
  phone text,
  email text,
  address text,
  city text,
  state text,
  timezone text,
  status text,
  is_headquarters boolean,
  assigned_members bigint,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.id,
    u.name,
    u.code,
    u.phone,
    u.email,
    u.address,
    u.city,
    u.state,
    u.timezone,
    u.status,
    u.is_headquarters,
    (
      select count(*)
      from public.organization_member_units mu
      where mu.organization_id = u.organization_id
        and mu.unit_id = u.id
    ) as assigned_members,
    u.created_at
  from public.organization_units u
  where u.organization_id = p_organization_id
    and public.has_feature(p_organization_id, 'multi_unit')
    and public.can_access_unit_scope(p_organization_id, u.id)
  order by u.is_headquarters desc, u.name;
$$;

revoke all on function public.list_enterprise_units(uuid) from public;
grant execute on function public.list_enterprise_units(uuid) to authenticated;
