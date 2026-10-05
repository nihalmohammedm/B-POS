-- Takeaway / delivery bill sync. Idempotent: safe to run more than once.
--
-- Dine-in orders hang off table_sessions -> parties. Takeaway and delivery
-- have no table, so the push skips those two rows and the links to them must
-- be nullable. Orders also gain an explicit type plus the customer fields the
-- POS already records locally.

do $$
declare
  c record;
begin
  -- Drop NOT NULL only where the column exists and currently has it.
  for c in
    select table_name, column_name
    from information_schema.columns
    where table_schema = 'bpos'
      and is_nullable = 'NO'
      and (table_name, column_name) in (
        ('orders', 'table_session_id'),
        ('orders', 'party_id'),
        ('bills',  'table_session_id'),
        ('bills',  'party_id')
      )
  loop
    execute format('alter table bpos.%I alter column %I drop not null', c.table_name, c.column_name);
  end loop;
end $$;

alter table bpos.orders add column if not exists order_type text not null default 'dine_in';
alter table bpos.orders add column if not exists customer_name text;
alter table bpos.orders add column if not exists customer_phone text;
alter table bpos.orders add column if not exists delivery_address text;
alter table bpos.orders add column if not exists token_number text;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'bpos.orders'::regclass and conname = 'orders_order_type_check') then
    alter table bpos.orders
      add constraint orders_order_type_check check (order_type in ('dine_in', 'takeaway', 'delivery'));
  end if;
end $$;

create index if not exists orders_outlet_type_idx on bpos.orders (outlet_id, order_type);

-- Verify:
-- select table_name, column_name, is_nullable from information_schema.columns
-- where table_schema = 'bpos'
--   and ((table_name in ('orders','bills') and column_name in ('table_session_id','party_id'))
--     or (table_name = 'orders' and column_name in ('order_type','customer_name','customer_phone','delivery_address','token_number')))
-- order by table_name, column_name;
