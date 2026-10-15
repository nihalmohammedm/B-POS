-- BPOS: add the missing UPDATE policies that make the app's retried sync fail with 403.
--
-- The app pushes with `Prefer: resolution=merge-duplicates` (an upsert). When a
-- row already exists (e.g. a previous push got partway and is being retried),
-- PostgREST runs INSERT .. ON CONFLICT DO UPDATE, which needs an UPDATE policy.
-- These four tables had UPDATE granted but no UPDATE policy -> 403.
-- Safe to re-run.

begin;

drop policy if exists bill_items_update on bpos.bill_items;
create policy bill_items_update on bpos.bill_items for update to authenticated
using (
  bpos.has_permission(bpos.bill_outlet_id(bill_id), 'bill.create')
  or bpos.has_permission(bpos.bill_outlet_id(bill_id), 'bill.split')
)
with check (
  bpos.has_permission(bpos.bill_outlet_id(bill_id), 'bill.create')
  or bpos.has_permission(bpos.bill_outlet_id(bill_id), 'bill.split')
);

drop policy if exists order_item_modifiers_update on bpos.order_item_modifiers;
create policy order_item_modifiers_update on bpos.order_item_modifiers for update to authenticated
using (bpos.has_permission(bpos.order_item_outlet_id(order_item_id), 'order.create'))
with check (bpos.has_permission(bpos.order_item_outlet_id(order_item_id), 'order.create'));

drop policy if exists order_item_cancellations_update on bpos.order_item_cancellations;
create policy order_item_cancellations_update on bpos.order_item_cancellations for update to authenticated
using (bpos.has_permission(bpos.order_item_outlet_id(order_item_id), 'order.cancel'))
with check (bpos.has_permission(bpos.order_item_outlet_id(order_item_id), 'order.cancel'));

drop policy if exists payment_refunds_update on bpos.payment_refunds;
create policy payment_refunds_update on bpos.payment_refunds for update to authenticated
using (bpos.has_permission(outlet_id, 'payment.refund'))
with check (bpos.has_permission(outlet_id, 'payment.refund'));

commit;

-- Verify:
-- select tablename, policyname, cmd from pg_policies
-- where schemaname = 'bpos' and policyname in
--   ('bill_items_update','order_item_modifiers_update','order_item_cancellations_update','payment_refunds_update');
