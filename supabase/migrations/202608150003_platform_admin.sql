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
