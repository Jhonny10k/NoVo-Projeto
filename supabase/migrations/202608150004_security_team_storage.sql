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
