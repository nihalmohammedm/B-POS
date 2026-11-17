-- BPOS: Main POS device registry + outlet-wide POS config.
--
-- Audit (before this migration)
--   bpos.pos_devices  exists: id, outlet_id, device_code (unique per outlet), device_name, device_type
--                     (only 'main_pos'), is_primary, is_active, last_seen_at, last_sync_at, app_version,
--                     registered_at, updated_at. Nothing in the app wrote to it, so an outlet could not
--                     see how many Main POS devices were running.
--   bpos.outlet_settings exists (print_layout, meal_periods added by supabase_outlet_config.sql).
--   Already in Supabase and unchanged here: menu, KOT groups, tables, outlet name/address/phone,
--   add-on groups, print layout, meal periods.
--
-- Adds
--   pos_devices.platform                 text (android / ios / macos / windows / linux ...)
--   outlet_settings.pos_config jsonb     {web_menu_base_url, kot_routes, printers}: what was still only
--                                        on each till. Printers here are LAN printers only; Bluetooth/USB
--                                        printers belong to the one device they are paired with.
--   bpos.register_pos_device(...)        register + heartbeat in one call (device_code = the POS id).
--                                        The first device of an outlet becomes primary if none is.
--   bpos.remove_pos_device(id)           needs device.manage; marks the device inactive.
--   bpos.set_primary_pos_device(id)      needs device.manage; exactly one primary per outlet.
--   RLS on pos_devices                   read = anyone with access to the outlet; no direct writes
--                                        (all changes go through the functions above).
--
-- Depends on bpos.current_user_id / has_outlet_access / has_permission
-- (supabase_orders_bills_payments_rls.sql) and supabase_outlet_config.sql. Safe to re-run.

begin;

alter table bpos.pos_devices     add column if not exists platform text;
alter table bpos.outlet_settings add column if not exists pos_config jsonb;

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'bpos.outlet_settings'::regclass and conname = 'outlet_settings_pos_config_object') then
    alter table bpos.outlet_settings
      add constraint outlet_settings_pos_config_object check (pos_config is null or jsonb_typeof(pos_config) = 'object');
  end if;
end $$;

create index if not exists pos_devices_outlet_active_idx on bpos.pos_devices (outlet_id) where is_active;

-- ---------- RLS ----------
alter table bpos.pos_devices enable row level security;
revoke insert, update, delete on bpos.pos_devices from anon, authenticated;
grant select on bpos.pos_devices to authenticated;

drop policy if exists pos_devices_select_outlet on bpos.pos_devices;
create policy pos_devices_select_outlet on bpos.pos_devices for select to authenticated
using (bpos.has_outlet_access(outlet_id));

-- ---------- register / heartbeat ----------
create or replace function bpos.register_pos_device(
  p_outlet_code text,
  p_device_code text,
  p_device_name text,
  p_app_version text default null,
  p_platform    text default null,
  p_synced      boolean default false
) returns jsonb
language plpgsql security definer set search_path = bpos, public
as $$
declare
  v_outlet uuid;
  v_dev    bpos.pos_devices%rowtype;
  v_code   text := btrim(coalesce(p_device_code, ''));
  v_name   text := left(btrim(coalesce(p_device_name, '')), 80);
begin
  select id into v_outlet from bpos.outlets where code = p_outlet_code;
  if v_outlet is null or not bpos.has_outlet_access(v_outlet) then
    raise exception 'No access to this outlet' using errcode = 'P0001';
  end if;
  if v_code = '' or char_length(v_code) > 64 then
    raise exception 'Invalid device id' using errcode = 'P0001';
  end if;
  if v_name = '' then v_name := 'Main POS'; end if;

  select * into v_dev from bpos.pos_devices where outlet_id = v_outlet and device_code = v_code;

  if not found then
    insert into bpos.pos_devices (outlet_id, device_code, device_name, device_type, is_primary, is_active,
                                  last_seen_at, last_sync_at, app_version, platform)
    values (v_outlet, v_code, v_name, 'main_pos',
            not exists (select 1 from bpos.pos_devices where outlet_id = v_outlet and is_active and is_primary),
            true, now(), case when p_synced then now() end, p_app_version, p_platform)
    returning * into v_dev;
  elsif v_dev.is_active then
    update bpos.pos_devices
       set last_seen_at = now(),
           last_sync_at = case when p_synced then now() else last_sync_at end,
           app_version  = coalesce(p_app_version, app_version),
           platform     = coalesce(p_platform, platform),
           updated_at   = now()
     where id = v_dev.id
    returning * into v_dev;
  end if;
  -- A device a manager removed stays removed until a manager re-adds it; it just learns so.

  return jsonb_build_object('id', v_dev.id, 'is_primary', v_dev.is_primary, 'active', v_dev.is_active);
end $$;

-- ---------- manager actions ----------
create or replace function bpos.remove_pos_device(p_device_id uuid)
returns boolean
language plpgsql security definer set search_path = bpos, public
as $$
declare v_outlet uuid;
begin
  select outlet_id into v_outlet from bpos.pos_devices where id = p_device_id;
  if v_outlet is null or not bpos.has_permission(v_outlet, 'device.manage') then
    raise exception 'You do not have permission to change this' using errcode = 'P0001';
  end if;
  update bpos.pos_devices set is_active = false, is_primary = false, updated_at = now() where id = p_device_id;
  return true;
end $$;

create or replace function bpos.set_primary_pos_device(p_device_id uuid)
returns boolean
language plpgsql security definer set search_path = bpos, public
as $$
declare v_outlet uuid;
begin
  select outlet_id into v_outlet from bpos.pos_devices where id = p_device_id and is_active;
  if v_outlet is null or not bpos.has_permission(v_outlet, 'device.manage') then
    raise exception 'You do not have permission to change this' using errcode = 'P0001';
  end if;
  update bpos.pos_devices set is_primary = false, updated_at = now()
   where outlet_id = v_outlet and is_primary and id <> p_device_id;
  update bpos.pos_devices set is_primary = true, updated_at = now() where id = p_device_id;
  return true;
end $$;

revoke all on function bpos.register_pos_device(text, text, text, text, text, boolean),
  bpos.remove_pos_device(uuid), bpos.set_primary_pos_device(uuid) from public, anon;
grant execute on function bpos.register_pos_device(text, text, text, text, text, boolean),
  bpos.remove_pos_device(uuid), bpos.set_primary_pos_device(uuid) to authenticated;

commit;

-- ---------- Verify (run separately) ----------
-- select column_name from information_schema.columns
--  where table_schema = 'bpos' and ((table_name = 'pos_devices' and column_name = 'platform')
--     or (table_name = 'outlet_settings' and column_name = 'pos_config'));
-- select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'bpos' and proname in ('register_pos_device', 'remove_pos_device', 'set_primary_pos_device');
-- select polname from pg_policy where polrelid = 'bpos.pos_devices'::regclass;
