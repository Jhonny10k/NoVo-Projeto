-- 2026-08-15 — Contato comercial real + índice público para sitemap.

create table public.platform_contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 160),
  email text not null check (char_length(email) between 3 and 254),
  phone text,
  message text not null check (char_length(message) between 5 and 5000),
  status text not null default 'new' check (status in ('new','in_progress','resolved','spam')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index platform_contact_messages_status_created_idx on public.platform_contact_messages(status,created_at desc);
alter table public.platform_contact_messages enable row level security;
create policy platform_contact_select_admin on public.platform_contact_messages for select to authenticated using (public.is_platform_admin());
create policy platform_contact_update_admin on public.platform_contact_messages for update to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());
-- Sem INSERT para anon/authenticated: gravação ocorre somente pelo backend secreto após rate limit.

create or replace function public.list_public_sites()
returns table(slug text, published_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select o.slug, sc.published_at
  from public.organizations o
  join public.site_configs sc on sc.organization_id=o.id and sc.status='published'
  where o.status='active' and public.organization_has_entitlement(o.id,'site')
  order by sc.published_at desc nulls last;
$$;
revoke all on function public.list_public_sites() from public;
grant execute on function public.list_public_sites() to anon,authenticated;
