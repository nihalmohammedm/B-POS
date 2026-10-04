-- BPOS: RLS + grants for the operational tables behind orders/bills/payments/table
-- occupancy, in the bpos schema. Run once in the Supabase SQL editor for
-- https://v2database.bollgattea.com.
--
-- Audit done before writing this (via the service_role key, bypasses RLS/grants):
--   - Every table this migration touches already exists with the exact columns
--     CLAUDE.md describes (orders, order_items, order_item_modifiers,
--     order_item_cancellations, cancellation_reasons, bills, bill_items,
--     bill_requests, payments, payment_refunds, table_sessions, parties,
--     party_captains) — nothing here is a new table, per CLAUDE.md §22-24.
--   - All of them currently have RLS *off* and zero grants to `anon` or
--     `authenticated` — they're completely unreachable from the app today.
--   - bpos.users / outlet_users / roles / permissions / role_permissions already
--     have SELECT granted to `authenticated` (from supabase_seed_roles_permissions.sql)
--     but also have RLS off, so any signed-in user can currently read every staff
--     row across every outlet. This migration turns RLS on there too.
--   - bpos.tables, categories, products, etc. (the menu-sync path, read with the
--     anon key pre-login) are untouched — they keep working exactly as they do now.
--   - Live data: 1 outlet, 5 tables, 0 table_sessions/parties/orders/bills/payments.
--     Nothing here is destructive; there's no historical data to break.
--
-- Design (CLAUDE.md §14, §25, §31): access is gated by the caller's own
-- bpos.outlet_users membership + bpos.role_permissions, never by "am I the one
-- who created this row" — a Captain must see another Captain's orders at the
-- same outlet. Every policy below reuses the same four helper functions so the
-- permission logic lives in one place.
--
-- Safe to re-run: every grant/enable/policy/function here is idempotent.

begin;

-- ---------- 1. helper functions ----------
-- security definer + owned by the migration-running role (postgres, which has
-- BYPASSRLS like service_role) so a policy that calls these doesn't recurse into
-- its own RLS check when the function internally re-reads outlet_users/orders/etc.

create or replace function bpos.current_user_id()
returns uuid
language sql stable security definer set search_path = bpos, public
as $$
  select id from bpos.users where auth_user_id = auth.uid();
$$;

create or replace function bpos.has_outlet_access(p_outlet_id uuid)
returns boolean
language sql stable security definer set search_path = bpos, public
as $$
  select exists (
    select 1 from bpos.outlet_users
    where outlet_id = p_outlet_id
      and user_id = bpos.current_user_id()
      and is_active
  );
$$;

create or replace function bpos.has_permission(p_outlet_id uuid, p_permission_code text)
returns boolean
language sql stable security definer set search_path = bpos, public
as $$
  select exists (
    select 1
    from bpos.outlet_users ou
    join bpos.role_permissions rp on rp.role_id = ou.role_id
    join bpos.permissions p on p.id = rp.permission_id
    where ou.user_id = bpos.current_user_id()
      and ou.outlet_id = p_outlet_id
      and ou.is_active
      and p.code = p_permission_code
  );
$$;

-- outlet_id lookups for the child tables that don't carry outlet_id directly,
-- so their policies don't need an inline join on every check.
create or replace function bpos.order_outlet_id(p_order_id uuid) returns uuid
language sql stable security definer set search_path = bpos, public
as $$ select outlet_id from bpos.orders where id = p_order_id; $$;

create or replace function bpos.order_item_outlet_id(p_order_item_id uuid) returns uuid
language sql stable security definer set search_path = bpos, public
as $$
  select o.outlet_id from bpos.order_items oi join bpos.orders o on o.id = oi.order_id
  where oi.id = p_order_item_id;
$$;

create or replace function bpos.bill_outlet_id(p_bill_id uuid) returns uuid
language sql stable security definer set search_path = bpos, public
as $$ select outlet_id from bpos.bills where id = p_bill_id; $$;

create or replace function bpos.party_outlet_id(p_party_id uuid) returns uuid
language sql stable security definer set search_path = bpos, public
as $$ select outlet_id from bpos.parties where id = p_party_id; $$;

grant execute on function
  bpos.current_user_id(), bpos.has_outlet_access(uuid), bpos.has_permission(uuid, text),
  bpos.order_outlet_id(uuid), bpos.order_item_outlet_id(uuid), bpos.bill_outlet_id(uuid),
  bpos.party_outlet_id(uuid)
to authenticated;

-- ---------- 2. tighten identity/role tables (already granted, RLS was off) ----------

alter table bpos.users enable row level security;
alter table bpos.outlet_users enable row level security;
alter table bpos.roles enable row level security;
alter table bpos.permissions enable row level security;
alter table bpos.role_permissions enable row level security;

-- Self-row only. No table lookup inside either USING clause, on purpose:
-- has_outlet_access()/current_user_id() both read bpos.outlet_users, so an
-- "also see my outlet-mates" branch here would make this policy call a
-- function that queries a table gated by this same policy — infinite
-- recursion (42P17), which is exactly what shipped here originally. This is
-- also all fetchProfile actually needs (it only ever reads its own row).
-- Broader roster visibility, if it's ever needed, should be a SECURITY
-- DEFINER function returning a filtered result set, not a raw policy here.
drop policy if exists users_select on bpos.users;
create policy users_select on bpos.users for select to authenticated
using (auth_user_id = auth.uid());

drop policy if exists outlet_users_select on bpos.outlet_users;
create policy outlet_users_select on bpos.outlet_users for select to authenticated
using (user_id = bpos.current_user_id());

-- Reference data: global, not outlet-scoped, not sensitive — any signed-in
-- staff member can read the full role/permission catalogue.
drop policy if exists roles_select on bpos.roles;
create policy roles_select on bpos.roles for select to authenticated using (true);

drop policy if exists permissions_select on bpos.permissions;
create policy permissions_select on bpos.permissions for select to authenticated using (true);

drop policy if exists role_permissions_select on bpos.role_permissions;
create policy role_permissions_select on bpos.role_permissions for select to authenticated using (true);

-- ---------- 3. table occupancy: table_sessions, parties, party_captains ----------

grant select, insert, update on bpos.table_sessions, bpos.parties, bpos.party_captains to authenticated;

alter table bpos.table_sessions enable row level security;
alter table bpos.parties enable row level security;
alter table bpos.party_captains enable row level security;

drop policy if exists table_sessions_select on bpos.table_sessions;
create policy table_sessions_select on bpos.table_sessions for select to authenticated
using (bpos.has_permission(outlet_id, 'table.view'));

drop policy if exists table_sessions_write on bpos.table_sessions;
create policy table_sessions_write on bpos.table_sessions for insert to authenticated
with check (bpos.has_permission(outlet_id, 'order.create'));

drop policy if exists table_sessions_update on bpos.table_sessions;
create policy table_sessions_update on bpos.table_sessions for update to authenticated
using (bpos.has_permission(outlet_id, 'order.create'))
with check (bpos.has_permission(outlet_id, 'order.create'));

drop policy if exists parties_select on bpos.parties;
create policy parties_select on bpos.parties for select to authenticated
using (bpos.has_permission(outlet_id, 'table.view'));

drop policy if exists parties_insert on bpos.parties;
create policy parties_insert on bpos.parties for insert to authenticated
with check (bpos.has_permission(outlet_id, 'order.create'));

drop policy if exists parties_update on bpos.parties;
create policy parties_update on bpos.parties for update to authenticated
using (
  bpos.has_permission(outlet_id, 'order.create')
  or bpos.has_permission(outlet_id, 'bill.request')
  or bpos.has_permission(outlet_id, 'bill.create')
)
with check (
  bpos.has_permission(outlet_id, 'order.create')
  or bpos.has_permission(outlet_id, 'bill.request')
  or bpos.has_permission(outlet_id, 'bill.create')
);

drop policy if exists party_captains_select on bpos.party_captains;
create policy party_captains_select on bpos.party_captains for select to authenticated
using (bpos.has_permission(bpos.party_outlet_id(party_id), 'table.view'));

drop policy if exists party_captains_insert on bpos.party_captains;
create policy party_captains_insert on bpos.party_captains for insert to authenticated
with check (bpos.has_permission(bpos.party_outlet_id(party_id), 'order.create'));

drop policy if exists party_captains_update on bpos.party_captains;
create policy party_captains_update on bpos.party_captains for update to authenticated
using (bpos.has_permission(bpos.party_outlet_id(party_id), 'order.create'))
with check (bpos.has_permission(bpos.party_outlet_id(party_id), 'order.create'));

-- ---------- 4. orders + items (§16, §11, §12) ----------

grant select, insert, update on
  bpos.orders, bpos.order_items, bpos.order_item_modifiers, bpos.order_item_cancellations
to authenticated;
grant select on bpos.cancellation_reasons to authenticated;

alter table bpos.orders enable row level security;
alter table bpos.order_items enable row level security;
alter table bpos.order_item_modifiers enable row level security;
alter table bpos.order_item_cancellations enable row level security;
alter table bpos.cancellation_reasons enable row level security;

drop policy if exists orders_select on bpos.orders;
create policy orders_select on bpos.orders for select to authenticated
using (bpos.has_permission(outlet_id, 'order.view'));

drop policy if exists orders_insert on bpos.orders;
create policy orders_insert on bpos.orders for insert to authenticated
with check (bpos.has_permission(outlet_id, 'order.create'));

drop policy if exists orders_update on bpos.orders;
create policy orders_update on bpos.orders for update to authenticated
using (bpos.has_permission(outlet_id, 'order.create') or bpos.has_permission(outlet_id, 'order.cancel'))
with check (bpos.has_permission(outlet_id, 'order.create') or bpos.has_permission(outlet_id, 'order.cancel'));

drop policy if exists order_items_select on bpos.order_items;
create policy order_items_select on bpos.order_items for select to authenticated
using (bpos.has_permission(bpos.order_outlet_id(order_id), 'order.view'));

drop policy if exists order_items_insert on bpos.order_items;
create policy order_items_insert on bpos.order_items for insert to authenticated
with check (bpos.has_permission(bpos.order_outlet_id(order_id), 'order.create'));

drop policy if exists order_items_update on bpos.order_items;
create policy order_items_update on bpos.order_items for update to authenticated
using (
  bpos.has_permission(bpos.order_outlet_id(order_id), 'order.create')
  or bpos.has_permission(bpos.order_outlet_id(order_id), 'order.cancel')
)
with check (
  bpos.has_permission(bpos.order_outlet_id(order_id), 'order.create')
  or bpos.has_permission(bpos.order_outlet_id(order_id), 'order.cancel')
);

drop policy if exists order_item_modifiers_select on bpos.order_item_modifiers;
create policy order_item_modifiers_select on bpos.order_item_modifiers for select to authenticated
using (bpos.has_permission(bpos.order_item_outlet_id(order_item_id), 'order.view'));

drop policy if exists order_item_modifiers_insert on bpos.order_item_modifiers;
create policy order_item_modifiers_insert on bpos.order_item_modifiers for insert to authenticated
with check (bpos.has_permission(bpos.order_item_outlet_id(order_item_id), 'order.create'));

drop policy if exists order_item_cancellations_select on bpos.order_item_cancellations;
create policy order_item_cancellations_select on bpos.order_item_cancellations for select to authenticated
using (bpos.has_permission(bpos.order_item_outlet_id(order_item_id), 'order.view'));

drop policy if exists order_item_cancellations_insert on bpos.order_item_cancellations;
create policy order_item_cancellations_insert on bpos.order_item_cancellations for insert to authenticated
with check (bpos.has_permission(bpos.order_item_outlet_id(order_item_id), 'order.cancel'));

drop policy if exists cancellation_reasons_select on bpos.cancellation_reasons;
create policy cancellation_reasons_select on bpos.cancellation_reasons for select to authenticated
using (bpos.has_permission(outlet_id, 'order.view'));
-- No insert/update policy: reasons are admin-configured for now (via the SQL
-- editor / service_role), matching how this migration doesn't seed any rows.

-- ---------- 5. bills + bill requests (§17, §18, §28) ----------

grant select, insert, update on bpos.bills, bpos.bill_items, bpos.bill_requests to authenticated;

alter table bpos.bills enable row level security;
alter table bpos.bill_items enable row level security;
alter table bpos.bill_requests enable row level security;

drop policy if exists bills_select on bpos.bills;
create policy bills_select on bpos.bills for select to authenticated
using (bpos.has_permission(outlet_id, 'bill.view'));

drop policy if exists bills_insert on bpos.bills;
create policy bills_insert on bpos.bills for insert to authenticated
with check (bpos.has_permission(outlet_id, 'bill.create'));

drop policy if exists bills_update on bpos.bills;
create policy bills_update on bpos.bills for update to authenticated
using (
  bpos.has_permission(outlet_id, 'bill.create')
  or bpos.has_permission(outlet_id, 'bill.split')
  or bpos.has_permission(outlet_id, 'discount.apply')
)
with check (
  bpos.has_permission(outlet_id, 'bill.create')
  or bpos.has_permission(outlet_id, 'bill.split')
  or bpos.has_permission(outlet_id, 'discount.apply')
);

drop policy if exists bill_items_select on bpos.bill_items;
create policy bill_items_select on bpos.bill_items for select to authenticated
using (bpos.has_permission(bpos.bill_outlet_id(bill_id), 'bill.view'));

drop policy if exists bill_items_insert on bpos.bill_items;
create policy bill_items_insert on bpos.bill_items for insert to authenticated
with check (
  bpos.has_permission(bpos.bill_outlet_id(bill_id), 'bill.create')
  or bpos.has_permission(bpos.bill_outlet_id(bill_id), 'bill.split')
);

drop policy if exists bill_requests_select on bpos.bill_requests;
create policy bill_requests_select on bpos.bill_requests for select to authenticated
using (bpos.has_permission(outlet_id, 'bill.view') or bpos.has_permission(outlet_id, 'bill.request'));

drop policy if exists bill_requests_insert on bpos.bill_requests;
create policy bill_requests_insert on bpos.bill_requests for insert to authenticated
with check (bpos.has_permission(outlet_id, 'bill.request'));

drop policy if exists bill_requests_update on bpos.bill_requests;
create policy bill_requests_update on bpos.bill_requests for update to authenticated
using (bpos.has_permission(outlet_id, 'bill.create'))
with check (bpos.has_permission(outlet_id, 'bill.create'));

-- ---------- 6. payments + refunds (§19) ----------

grant select, insert, update on bpos.payments, bpos.payment_refunds to authenticated;

alter table bpos.payments enable row level security;
alter table bpos.payment_refunds enable row level security;

drop policy if exists payments_select on bpos.payments;
create policy payments_select on bpos.payments for select to authenticated
using (bpos.has_permission(outlet_id, 'bill.view'));

drop policy if exists payments_insert on bpos.payments;
create policy payments_insert on bpos.payments for insert to authenticated
with check (
  bpos.has_permission(outlet_id, 'payment.create')
  or bpos.has_permission(outlet_id, 'payment.split')
);

drop policy if exists payments_update on bpos.payments;
create policy payments_update on bpos.payments for update to authenticated
using (bpos.has_permission(outlet_id, 'payment.create'))
with check (bpos.has_permission(outlet_id, 'payment.create'));

drop policy if exists payment_refunds_select on bpos.payment_refunds;
create policy payment_refunds_select on bpos.payment_refunds for select to authenticated
using (bpos.has_permission(outlet_id, 'bill.view'));

drop policy if exists payment_refunds_insert on bpos.payment_refunds;
create policy payment_refunds_insert on bpos.payment_refunds for insert to authenticated
with check (bpos.has_permission(outlet_id, 'payment.refund'));

commit;

-- Verify (run separately, read-only):
--
-- 1. RLS is now on everywhere it should be:
-- select relname, relrowsecurity
-- from pg_class
-- where relnamespace = 'bpos'::regnamespace
--   and relname in ('users','outlet_users','roles','permissions','role_permissions',
--     'table_sessions','parties','party_captains','orders','order_items',
--     'order_item_modifiers','order_item_cancellations','cancellation_reasons',
--     'bills','bill_items','bill_requests','payments','payment_refunds')
-- order by relname;
--
-- 2. Every policy landed:
-- select tablename, policyname, cmd
-- from pg_policies where schemaname = 'bpos' order by tablename, policyname;
--
-- 3. End-to-end, as a real signed-in user (via the app or a REST call with that
--    user's access_token, not the anon/service_role key): confirm a captain can
--    create an order at their own outlet, see another captain's orders at the
--    same outlet, but a request against a *different* outlet_id (one they have
--    no bpos.outlet_users row for) returns an empty set rather than an error.
