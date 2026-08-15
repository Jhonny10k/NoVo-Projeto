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
