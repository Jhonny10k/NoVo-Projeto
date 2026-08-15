-- 2026-08-15 — Hardening de visibilidade multiunidade.
-- Membros restritos só podem ler unidades explicitamente atribuídas.
-- Owners/admins continuam com visão completa da organização.

drop policy if exists organization_units_select_member on public.organization_units;
create policy organization_units_select_member on public.organization_units
for select to authenticated
using (
  public.has_feature(organization_id, 'multi_unit')
  and public.can_access_unit_scope(organization_id, id)
);

create or replace function public.list_enterprise_units(p_organization_id uuid)
returns table(
  id uuid,
  name text,
  code text,
  phone text,
  email text,
  address text,
  city text,
  state text,
  timezone text,
  status text,
  is_headquarters boolean,
  assigned_members bigint,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.id,
    u.name,
    u.code,
    u.phone,
    u.email,
    u.address,
    u.city,
    u.state,
    u.timezone,
    u.status,
    u.is_headquarters,
    (
      select count(*)
      from public.organization_member_units mu
      where mu.organization_id = u.organization_id
        and mu.unit_id = u.id
    ) as assigned_members,
    u.created_at
  from public.organization_units u
  where u.organization_id = p_organization_id
    and public.has_feature(p_organization_id, 'multi_unit')
    and public.can_access_unit_scope(p_organization_id, u.id)
  order by u.is_headquarters desc, u.name;
$$;

revoke all on function public.list_enterprise_units(uuid) from public;
grant execute on function public.list_enterprise_units(uuid) to authenticated;
