-- MRP items: packaged products sold at their printed price. Takeaway adds the parcel
-- charge only for products where is_mrp = false.
alter table bpos.products add column if not exists is_mrp boolean not null default false;

-- Verify
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'bpos' and table_name = 'products' and column_name = 'is_mrp';
