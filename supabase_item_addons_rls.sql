-- Lets signed-in staff with `menu.manage` create/edit add-ons from the POS: an item's own add-ons
-- (item editor) and reusable add-on groups (Settings > Add-on groups), and attach groups to items. They are stored as a modifier group per item (modifier_groups,
-- modifiers, product_modifier_groups). Removing an add-on sets is_active = false; nothing is deleted.
--
-- Depends on bpos.has_permission(outlet_id, code) from supabase_orders_bills_payments_rls.sql.
-- Safe to re-run. Fixes: "permission denied for table modifier_groups" (42501) when saving an item.

alter table bpos.modifier_groups         enable row level security;
alter table bpos.modifiers               enable row level security;
alter table bpos.product_modifier_groups enable row level security;

-- READ: the POS reads these to show add-ons. Menu data is not sensitive (the web menu exposes it too);
-- writes stay gated by menu.manage below.
grant select on bpos.modifier_groups, bpos.modifiers, bpos.product_modifier_groups to anon, authenticated;
grant insert, update on bpos.modifier_groups, bpos.modifiers to authenticated;
grant insert on bpos.product_modifier_groups to authenticated;

do $$
declare t text;
begin
  foreach t in array array['modifier_groups','modifiers','product_modifier_groups'] loop
    execute format('drop policy if exists %I on bpos.%I', t || '_read_all', t);
    execute format('create policy %I on bpos.%I for select to anon, authenticated using (true)', t || '_read_all', t);
  end loop;
end $$;

-- WRITE: modifier_groups has outlet_id; modifiers and product_modifier_groups go through their parent.
drop policy if exists modifier_groups_menu_manage_ins on bpos.modifier_groups;
create policy modifier_groups_menu_manage_ins on bpos.modifier_groups for insert to authenticated
with check (bpos.has_permission(outlet_id, 'menu.manage'));

drop policy if exists modifier_groups_menu_manage_upd on bpos.modifier_groups;
create policy modifier_groups_menu_manage_upd on bpos.modifier_groups for update to authenticated
using (bpos.has_permission(outlet_id, 'menu.manage'))
with check (bpos.has_permission(outlet_id, 'menu.manage'));

drop policy if exists modifiers_menu_manage_ins on bpos.modifiers;
create policy modifiers_menu_manage_ins on bpos.modifiers for insert to authenticated
with check (exists (select 1 from bpos.modifier_groups g where g.id = modifier_group_id and bpos.has_permission(g.outlet_id, 'menu.manage')));

drop policy if exists modifiers_menu_manage_upd on bpos.modifiers;
create policy modifiers_menu_manage_upd on bpos.modifiers for update to authenticated
using (exists (select 1 from bpos.modifier_groups g where g.id = modifier_group_id and bpos.has_permission(g.outlet_id, 'menu.manage')))
with check (exists (select 1 from bpos.modifier_groups g where g.id = modifier_group_id and bpos.has_permission(g.outlet_id, 'menu.manage')));

drop policy if exists pmg_menu_manage_ins on bpos.product_modifier_groups;
create policy pmg_menu_manage_ins on bpos.product_modifier_groups for insert to authenticated
with check (exists (select 1 from bpos.products p where p.id = product_id and bpos.has_permission(p.outlet_id, 'menu.manage')));

-- Unlinking a reusable add-on group from an item (the link row is the only thing ever deleted).
grant delete on bpos.product_modifier_groups to authenticated;
drop policy if exists pmg_menu_manage_del on bpos.product_modifier_groups;
create policy pmg_menu_manage_del on bpos.product_modifier_groups for delete to authenticated
using (exists (select 1 from bpos.products p where p.id = product_id and bpos.has_permission(p.outlet_id, 'menu.manage')));

-- Verify
select tablename, policyname, cmd, roles from pg_policies
where schemaname = 'bpos' and tablename in ('modifier_groups','modifiers','product_modifier_groups')
order by tablename, policyname;
