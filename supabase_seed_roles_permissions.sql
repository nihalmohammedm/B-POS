-- BPOS: roles/permissions seed + first-owner bootstrap, in the bpos schema.
-- Run once in the Supabase SQL editor for https://v2database.bollgattea.com.
--
-- Confirmed before writing this (via the anon key already embedded in the app):
--   - bpos.roles / bpos.permissions / bpos.role_permissions / bpos.users /
--     bpos.outlet_users are all empty.
--   - anon has SELECT but NOT INSERT on bpos.* (inserting a throwaway test role
--     returned 42501 permission denied). RLS/grants for writes aren't set up yet
--     (matches CLAUDE.md's own "Implement RLS" item still being open), so the
--     app's in-app "create first Owner account" flow can't just INSERT into
--     bpos.users/outlet_users directly — it goes through the guarded function
--     below instead.
--
-- Safe to re-run: every insert/grant/constraint is idempotent.

begin;

-- ---------- 1. unique constraints the seed's ON CONFLICT relies on ----------
-- Guarded existence checks (Postgres has no `ADD CONSTRAINT IF NOT EXISTS`),
-- per this project's own migration convention.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conrelid = 'bpos.roles'::regclass and contype = 'u' and conname = 'roles_code_key'
  ) then
    alter table bpos.roles add constraint roles_code_key unique (code);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conrelid = 'bpos.permissions'::regclass and contype = 'u' and conname = 'permissions_code_key'
  ) then
    alter table bpos.permissions add constraint permissions_code_key unique (code);
  end if;
end $$;

-- ---------- 2. reference data (CLAUDE.md §3) ----------
insert into bpos.roles (code, name, description, is_system_role) values
  ('captain', 'Captain', 'Takes orders and requests bills tableside', true),
  ('cashier', 'Cashier', 'Creates and settles bills at the counter', true),
  ('manager', 'Manager', 'Full operational access for one or more outlets', true),
  ('owner',   'Owner',   'Full access, including settings and user management', true)
on conflict (code) do nothing;

insert into bpos.permissions (code, name) values
  ('bill.create',      'Create bill'),
  ('bill.request',     'Request bill'),
  ('bill.split',       'Split bill'),
  ('bill.view',        'View bills'),
  ('device.manage',    'Manage devices'),
  ('discount.apply',   'Apply discount'),
  ('inventory.manage', 'Manage inventory'),
  ('inventory.view',   'View inventory'),
  ('kot.reprint',      'Reprint KOT'),
  ('menu.manage',      'Manage menu'),
  ('menu.view',        'View menu'),
  ('order.cancel',     'Cancel order'),
  ('order.create',     'Create order'),
  ('order.view',       'View orders'),
  ('payment.create',   'Create payment'),
  ('payment.refund',   'Refund payment'),
  ('payment.split',    'Split payment'),
  ('printer.manage',   'Manage printers'),
  ('printer.view',     'View printers'),
  ('report.view',      'View reports'),
  ('settings.manage',  'Manage settings'),
  ('settings.view',    'View settings'),
  ('table.view',       'View tables'),
  ('user.manage',      'Manage users')
on conflict (code) do nothing;

-- manager/owner: every permission.
insert into bpos.role_permissions (role_id, permission_id)
select r.id, p.id
from bpos.roles r
cross join bpos.permissions p
where r.code in ('manager', 'owner')
on conflict do nothing;

-- captain: tableside order-taking + bill requests, no settings/user/payment admin.
insert into bpos.role_permissions (role_id, permission_id)
select r.id, p.id
from bpos.roles r
join bpos.permissions p on p.code in (
  'order.create', 'order.view', 'order.cancel',
  'bill.request', 'bill.view',
  'menu.view', 'table.view',
  'kot.reprint'
)
where r.code = 'captain'
on conflict do nothing;

-- cashier: counter billing/payments, no settings/user/menu/printer admin.
insert into bpos.role_permissions (role_id, permission_id)
select r.id, p.id
from bpos.roles r
join bpos.permissions p on p.code in (
  'order.create', 'order.view', 'order.cancel',
  'bill.create', 'bill.view', 'bill.split',
  'payment.create', 'payment.split',
  'discount.apply',
  'menu.view', 'table.view', 'inventory.view',
  'kot.reprint'
)
where r.code = 'cashier'
on conflict do nothing;

-- ---------- 3. first-owner bootstrap RPC ----------
-- Called once, right after BPOS's in-app "Set up this outlet" screen signs a new
-- Supabase Auth user up. Runs as the function owner (bypassing the currently-
-- withheld INSERT grants on bpos.users/outlet_users) but only ever succeeds while
-- the target outlet truly has zero linked staff — so it can't be used to add a
-- second account, or to self-grant owner on an outlet that already has one.
create or replace function bpos.bootstrap_first_owner(p_outlet_id uuid, p_full_name text)
returns table(user_id uuid, role_code text, role_name text)
language plpgsql
security definer
set search_path = bpos, public
as $$
declare
  v_uid uuid := auth.uid();
  v_user_id uuid;
  v_role_id uuid;
  v_role_name text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if exists (select 1 from bpos.outlet_users where outlet_id = p_outlet_id) then
    raise exception 'This outlet already has staff — ask an existing owner/manager to add you instead.';
  end if;

  select id, name into v_role_id, v_role_name from bpos.roles where code = 'owner' limit 1;
  if v_role_id is null then
    raise exception 'No "owner" role found — the seed above must run before this function.';
  end if;

  select id into v_user_id from bpos.users where auth_user_id = v_uid limit 1;
  if v_user_id is null then
    insert into bpos.users (auth_user_id, full_name, is_active)
    values (v_uid, p_full_name, true)
    returning id into v_user_id;
  end if;

  insert into bpos.outlet_users (outlet_id, user_id, role_id, is_active)
  values (p_outlet_id, v_user_id, v_role_id, true);

  return query select v_user_id, 'owner'::text, v_role_name;
end;
$$;

grant execute on function bpos.bootstrap_first_owner(uuid, text) to authenticated;

-- ---------- 4. read access for signed-in staff ----------
-- The app reads its own profile/role/permissions with the *signed-in user's*
-- access token (not the anon key) after login, so the `authenticated` Postgres
-- role needs at least the same read access `anon` already has on these tables.
-- Read-only; full outlet isolation still lands with the RLS work in CLAUDE.md §25.
grant select on bpos.users, bpos.outlet_users, bpos.roles, bpos.permissions, bpos.role_permissions, bpos.outlets to authenticated;

commit;

-- Verify:
-- select r.code as role, array_agg(p.code order by p.code) as permissions
-- from bpos.roles r
-- join bpos.role_permissions rp on rp.role_id = r.id
-- join bpos.permissions p on p.id = rp.permission_id
-- group by r.code order by r.code;
