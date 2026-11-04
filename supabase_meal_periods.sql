-- Per-item meal periods: ids of the Meal times (Settings → Meal times) an item is served in.
-- Empty = follow the item's category (all day when no period claims it).
alter table bpos.products add column if not exists meal_periods text[] not null default '{}';

-- Verify
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'bpos' and table_name = 'products' and column_name = 'meal_periods';
