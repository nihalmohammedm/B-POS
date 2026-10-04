-- BPOS: grant + RLS for bpos.payment_methods.
--
-- Why: the settled-bill background sync (lib/sync/bill_sync_api.dart,
-- fetchPaymentMethodIds) looks up payment_methods under the signed-in staff
-- member's own access token (not the anon key), to resolve a local
-- Payment.method string ("Cash", "UPI", ...) to the payment_method_id FK
-- bpos.payments.payment_method_id requires. That call fails today with
-- HTTP 403 / Postgres 42501 (insufficient_privilege) — the table has no
-- GRANT to `authenticated` at all, so this isn't an RLS policy being too
-- strict, it's that there's no privilege to even attempt the query.
--
-- payment_methods was never in scope of supabase_orders_bills_payments_rls.sql
-- (that migration only touched orders/bills/payments/table-occupancy tables)
-- and nothing read it under an authenticated user's token before now — the
-- existing menu sync (lib/backoffice_api.dart) uses the anon key and never
-- queried this table either.
--
-- Depends on bpos.has_permission(outlet_id, permission_code), created by
-- supabase_orders_bills_payments_rls.sql — run that one first if this errors
-- with "function bpos.has_permission does not exist".
--
-- Safe to re-run.

begin;

grant select on bpos.payment_methods to authenticated;

alter table bpos.payment_methods enable row level security;

-- Same permission payments_insert already requires to create a payment
-- (supabase_orders_bills_payments_rls.sql) — whoever can take a payment can
-- see what payment methods are configured for their outlet.
drop policy if exists payment_methods_select on bpos.payment_methods;
create policy payment_methods_select on bpos.payment_methods for select to authenticated
using (bpos.has_permission(outlet_id, 'payment.create'));

-- No insert/update policy: like cancellation_reasons, payment methods are
-- admin-configured for now (via the SQL editor / service_role).

commit;

-- Verify (run separately, read-only):
--
-- select relrowsecurity from pg_class
-- where relnamespace = 'bpos'::regnamespace and relname = 'payment_methods';
--
-- select policyname, cmd from pg_policies
-- where schemaname = 'bpos' and tablename = 'payment_methods';
--
-- End-to-end: as a real signed-in user with payment.create at their outlet
-- (via the app, or a REST call using that user's access_token), confirm
-- GET .../payment_methods?outlet_id=eq.<their outlet> now returns 200 with
-- rows instead of 403.
