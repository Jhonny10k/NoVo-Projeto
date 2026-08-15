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
