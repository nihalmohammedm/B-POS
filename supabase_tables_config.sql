-- BPOS: table setup and floor-plan layout stored in bpos.tables (shared by every till).
--
-- Audit (before this migration)
--   bpos.tables has at least: id, outlet_id (FK outlets, cascade), table_number (unique per outlet),
--   maximum_occupancy (> 0), display_order, is_active. The POS read those and guessed the rest:
--   every table was put on one "Tables" floor, its size came from the seat count, and where it sat
--   on the floor plan was saved only on the device that dragged it.
--   The audit query for the full column list was not available when this was written, so nothing
--   here assumes columns beyond the ones above. Check the query at the bottom after running.
--
-- Adds (all nullable or defaulted, so existing rows stay valid)
--   floor   text  not null default 'Tables'   floor / section name shown as a tab on the Tables screen
--   grid_x, grid_y  integer                   cell of the floor plan (null = not placed yet, auto-placed)
--   grid_w, grid_h  integer 1..6, default 1   size in grid cells
--   RLS: read = anyone with access to the outlet; insert/update need settings.manage.
--   There is no delete policy: removing a table sets is_active = false, so past orders, parties and
--   bills that point at it stay valid (CLAUDE.md §26).
--
-- Depends on bpos.has_outlet_access / has_permission (supabase_orders_bills_payments_rls.sql).
-- Safe to re-run.

begin;

do $$
declare v_fresh boolean;
begin
  -- Remember whether the size columns are new, so the one-off backfill below runs only once.
  v_fresh := not exists (select 1 from information_schema.columns
                         where table_schema = 'bpos' and table_name = 'tables' and column_name = 'grid_w');

  alter table bpos.tables add column if not exists floor  text    not null default 'Tables';
  alter table bpos.tables add column if not exists grid_x integer;
  alter table bpos.tables add column if not exists grid_y integer;
  alter table bpos.tables add column if not exists grid_w integer not null default 1;
  alter table bpos.tables add column if not exists grid_h integer not null default 1;

  -- Keep today's look: the POS used 1x1 up to 4 seats, 2x1 up to 8, 2x2 above.
  if v_fresh then
    update bpos.tables
       set grid_w = case when maximum_occupancy <= 4 then 1 else 2 end,
           grid_h = case when maximum_occupancy <= 8 then 1 else 2 end;
  end if;

  if not exists (select 1 from pg_constraint where conrelid = 'bpos.tables'::regclass and conname = 'tables_grid_size_check') then
    alter table bpos.tables add constraint tables_grid_size_check
      check (grid_w between 1 and 6 and grid_h between 1 and 6);
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'bpos.tables'::regclass and conname = 'tables_grid_pos_check') then
    alter table bpos.tables add constraint tables_grid_pos_check
      check ((grid_x is null) = (grid_y is null) and (grid_x is null or (grid_x >= 0 and grid_y >= 0)));
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'bpos.tables'::regclass and conname = 'tables_floor_check') then
    alter table bpos.tables add constraint tables_floor_check check (char_length(btrim(floor)) between 1 and 40);
  end if;
end $$;

create index if not exists tables_outlet_active_idx on bpos.tables (outlet_id) where is_active;

-- ---------- RLS ----------
alter table bpos.tables enable row level security;
grant select, insert, update on bpos.tables to authenticated;

drop policy if exists tables_select_outlet on bpos.tables;
create policy tables_select_outlet on bpos.tables for select to authenticated
using (bpos.has_outlet_access(outlet_id));

drop policy if exists tables_insert_manage on bpos.tables;
create policy tables_insert_manage on bpos.tables for insert to authenticated
with check (bpos.has_permission(outlet_id, 'settings.manage'));

drop policy if exists tables_update_manage on bpos.tables;
create policy tables_update_manage on bpos.tables for update to authenticated
using (bpos.has_permission(outlet_id, 'settings.manage'))
with check (bpos.has_permission(outlet_id, 'settings.manage'));

commit;

-- ---------- Verify (run separately) ----------
-- Every column of bpos.tables. Any NOT NULL column without a default that is not in this list
-- (id, outlet_id, table_number, maximum_occupancy) would make "Add table" in the app fail:
-- send me the result if so.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'bpos' and table_name = 'tables'
order by ordinal_position;

select polname, polcmd from pg_policy where polrelid = 'bpos.tables'::regclass order by polname;
