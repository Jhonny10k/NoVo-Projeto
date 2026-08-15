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
