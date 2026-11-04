-- BPOS: outlet-wide POS configuration stored in bpos.outlet_settings.
--
-- Audit (before this migration):
--   bpos.outlet_settings exists, one row per outlet (outlet_id = PK, FK outlets.id) with
--   inventory_enabled, currency_code, tax_enabled, allow_split_payment, updated_at.
--   Nothing for print layout, payment QR or meal periods: those lived only on each
--   till's local database, so a second till or a reinstall started from defaults.
--
-- Adds:
--   print_layout jsonb  bill + KOT layout, including the UPI IDs used for the payment QR
--                       on bills (PrintLayout.toJson in lib/print_layout.dart)
--   meal_periods jsonb  [{id, name, start, end, cats}] (MealPeriod.toJson in lib/models.dart)
--   updated_by   uuid   bpos.users.id of whoever saved last; set by trigger, not the client
--   updated_at          now kept current by the same trigger
-- Printers and KOT-group → printer routing stay on each device: they are local hardware.
--
-- Access: read by anyone with access to the outlet; insert/update need settings.manage.
-- Depends on bpos.current_user_id / has_outlet_access / has_permission from
-- supabase_orders_bills_payments_rls.sql — run that first.
--
-- Safe to re-run.

begin;

alter table bpos.outlet_settings add column if not exists print_layout jsonb;
alter table bpos.outlet_settings add column if not exists meal_periods jsonb;
alter table bpos.outlet_settings add column if not exists updated_by uuid;

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'bpos.outlet_settings'::regclass and conname = 'outlet_settings_updated_by_fkey') then
    alter table bpos.outlet_settings
      add constraint outlet_settings_updated_by_fkey foreign key (updated_by) references bpos.users(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint
                 where conrelid = 'bpos.outlet_settings'::regclass and conname = 'outlet_settings_print_layout_object') then
    alter table bpos.outlet_settings
      add constraint outlet_settings_print_layout_object check (print_layout is null or jsonb_typeof(print_layout) = 'object');
  end if;
  if not exists (select 1 from pg_constraint
                 where conrelid = 'bpos.outlet_settings'::regclass and conname = 'outlet_settings_meal_periods_array') then
    alter table bpos.outlet_settings
      add constraint outlet_settings_meal_periods_array check (meal_periods is null or jsonb_typeof(meal_periods) = 'array');
  end if;
end $$;

-- Who/when for every save, taken from the caller's own login so it can't be faked.
create or replace function bpos.outlet_settings_stamp()
returns trigger
language plpgsql security definer set search_path = bpos, public
as $$
begin
  new.updated_at := now();
  new.updated_by := bpos.current_user_id();
  return new;
end;
$$;

drop trigger if exists outlet_settings_stamp on bpos.outlet_settings;
create trigger outlet_settings_stamp
before insert or update on bpos.outlet_settings
for each row execute function bpos.outlet_settings_stamp();

grant select, insert, update on bpos.outlet_settings to authenticated;

alter table bpos.outlet_settings enable row level security;

drop policy if exists outlet_settings_select on bpos.outlet_settings;
create policy outlet_settings_select on bpos.outlet_settings for select to authenticated
using (bpos.has_outlet_access(outlet_id));

drop policy if exists outlet_settings_insert on bpos.outlet_settings;
create policy outlet_settings_insert on bpos.outlet_settings for insert to authenticated
with check (bpos.has_permission(outlet_id, 'settings.manage'));

drop policy if exists outlet_settings_update on bpos.outlet_settings;
create policy outlet_settings_update on bpos.outlet_settings for update to authenticated
using (bpos.has_permission(outlet_id, 'settings.manage'))
with check (bpos.has_permission(outlet_id, 'settings.manage'));

commit;

-- Verify
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'bpos' and table_name = 'outlet_settings'
order by ordinal_position;

select polname, polcmd from pg_policy where polrelid = 'bpos.outlet_settings'::regclass order by polname;
