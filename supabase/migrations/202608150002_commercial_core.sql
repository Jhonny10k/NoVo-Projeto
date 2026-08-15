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
