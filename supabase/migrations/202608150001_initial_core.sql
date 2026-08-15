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
