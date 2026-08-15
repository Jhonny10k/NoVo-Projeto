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
