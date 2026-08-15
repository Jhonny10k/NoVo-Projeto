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
