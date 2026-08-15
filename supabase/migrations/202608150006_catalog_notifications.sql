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
