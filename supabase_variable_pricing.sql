-- Variable pricing. Idempotent: safe to run more than once.
--
--   * products.is_open_price  - price is typed when the item is ordered (e.g. fish by size).
--                               base_price / variant prices are only a guide for staff.
--   * products.is_daily_price - price changes day to day; listed on the POS "Today's prices"
--                               screen, which updates base_price / product_variants.price in place.
--
-- Historical orders are unaffected: order lines store their own unit price when taken.
-- Writes go through the existing menu.manage RLS policies (supabase_menu_manage_rls.sql).
-- Open-price items should not be shown on the public web menu (show_on_web), which prices
-- from base_price.

begin;

alter table bpos.products add column if not exists is_open_price  boolean not null default false;
alter table bpos.products add column if not exists is_daily_price boolean not null default false;

commit;

-- Verify
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'bpos' and table_name = 'products'
  and column_name in ('is_open_price', 'is_daily_price')
order by column_name;
