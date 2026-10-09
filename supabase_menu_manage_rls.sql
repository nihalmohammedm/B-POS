-- Lets signed-in staff with the `menu.manage` permission edit THEIR outlet's menu
-- from the POS (Settings > Menu items): products, sizes, KOT group of a product.
-- Nothing is ever hard-deleted by the app; removing an item or size sets is_active = false.
--
-- Depends on bpos.has_permission(outlet_id, code) from supabase_orders_bills_payments_rls.sql.
-- Safe to re-run. Audit first (CLAUDE.md): run the check at the bottom and compare with what you
-- already have; if you already have write policies on these tables, keep those and skip the clash.
--
-- NOTE: product_variants and product_kot_groups have no outlet_id, so their policies go through
-- the parent product. If product_kot_groups carries extra NOT NULL columns, the POS insert will
-- fail with the column named in the error - add it to MenuAdminApi._setKotGroup.

alter table bpos.products              enable row level security;
alter table bpos.product_variants      enable row level security;
alter table bpos.product_kot_groups    enable row level security;

grant insert, update, delete on bpos.products, bpos.product_variants, bpos.product_kot_groups to authenticated;

drop policy if exists products_menu_manage_ins on bpos.products;
create policy products_menu_manage_ins on bpos.products for insert to authenticated
with check (bpos.has_permission(outlet_id, 'menu.manage'));

drop policy if exists products_menu_manage_upd on bpos.products;
create policy products_menu_manage_upd on bpos.products for update to authenticated
using (bpos.has_permission(outlet_id, 'menu.manage'))
with check (bpos.has_permission(outlet_id, 'menu.manage'));

drop policy if exists variants_menu_manage_ins on bpos.product_variants;
create policy variants_menu_manage_ins on bpos.product_variants for insert to authenticated
with check (exists (select 1 from bpos.products p where p.id = product_id and bpos.has_permission(p.outlet_id, 'menu.manage')));

drop policy if exists variants_menu_manage_upd on bpos.product_variants;
create policy variants_menu_manage_upd on bpos.product_variants for update to authenticated
using (exists (select 1 from bpos.products p where p.id = product_id and bpos.has_permission(p.outlet_id, 'menu.manage')))
with check (exists (select 1 from bpos.products p where p.id = product_id and bpos.has_permission(p.outlet_id, 'menu.manage')));

drop policy if exists pkg_menu_manage_ins on bpos.product_kot_groups;
create policy pkg_menu_manage_ins on bpos.product_kot_groups for insert to authenticated
with check (exists (select 1 from bpos.products p where p.id = product_id and bpos.has_permission(p.outlet_id, 'menu.manage')));

drop policy if exists pkg_menu_manage_del on bpos.product_kot_groups;
create policy pkg_menu_manage_del on bpos.product_kot_groups for delete to authenticated
using (exists (select 1 from bpos.products p where p.id = product_id and bpos.has_permission(p.outlet_id, 'menu.manage')));

-- Signed-in users (role `authenticated`) need to READ these tables too: the POS reads them with the
-- user's token after login, and every insert/update asks for the saved row back, which needs select.
-- (An existing `anon_read` policy usually covers only the anon role.) Menu data is not sensitive,
-- and the web menu already exposes it; writes stay gated by menu.manage above.
do $$
declare t text;
begin
  foreach t in array array['products','product_variants','product_kot_groups','categories','kot_groups','menu_versions'] loop
    execute format('drop policy if exists %I on bpos.%I', t || '_auth_read', t);
    execute format('create policy %I on bpos.%I for select to authenticated using (true)', t || '_auth_read', t);
  end loop;
end $$;

-- Creating a menu item under a new category creates the category too.
alter table bpos.categories enable row level security;
grant insert, update on bpos.categories to authenticated;

drop policy if exists categories_menu_manage_ins on bpos.categories;
create policy categories_menu_manage_ins on bpos.categories for insert to authenticated
with check (bpos.has_permission(outlet_id, 'menu.manage'));

drop policy if exists categories_menu_manage_upd on bpos.categories;
create policy categories_menu_manage_upd on bpos.categories for update to authenticated
using (bpos.has_permission(outlet_id, 'menu.manage'))
with check (bpos.has_permission(outlet_id, 'menu.manage'));

-- IMPORTANT: enabling RLS on a table that anon/authenticated could read before will hide every row
-- unless a select policy exists. The POS already reads these tables, so check first that you have one:
--   select tablename, policyname, cmd, roles from pg_policies
--   where schemaname = 'bpos' and tablename in ('products','product_variants','product_kot_groups','categories','menu_versions');
-- and add `create policy ... for select to anon, authenticated using (true)` for any table missing it.
