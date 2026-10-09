-- Public web menu + customer web ordering. Idempotent: safe to run more than once.
--
-- What this adds
--   * bpos.products.show_on_web      - per-product "visible on the public menu" flag (default off).
--   * bpos.outlets.web_menu_enabled  - per-outlet master switch (default off).
--   * bpos.web_orders / web_order_items - customer submissions waiting for staff to accept on the Main POS.
--     They are a separate inbox on purpose: a web order only becomes a real bpos.orders row (and a KOT)
--     once the cashier accepts it, so a stranger on the internet can never inject kitchen tickets.
--   * Three anon-callable SECURITY DEFINER functions (the ONLY public surface; anon gets no table access):
--       bpos.web_menu(outlet_code)            -> menu JSON, web-visible items only
--       bpos.web_place_order(...)             -> validates, prices from the DB, inserts a pending order
--       bpos.web_order_status(public_token)   -> status for the customer's tracking link
--   * RLS so staff only see/decide their own outlet's web orders (CLAUDE.md §25).
--
-- Assumes the columns the Flutter app already reads (lib/backoffice_api.dart): outlets(id, code, name, ...),
-- categories(id, name, display_order, parent_id, outlet_id, is_active), products(id, outlet_id, name, category_id,
-- description, base_price, type, display_order, is_active, menu_version_id), product_variants(id, product_id, name,
-- price, display_order, is_active), modifier_groups / modifiers / product_modifier_groups / variant_modifier_groups,
-- menu_versions(id, status). Run the verification query at the bottom afterwards.

begin;

-- ---------- 1. flags ----------
alter table bpos.products add column if not exists show_on_web boolean not null default false;
alter table bpos.outlets  add column if not exists web_menu_enabled boolean not null default false;

create index if not exists products_outlet_show_on_web_idx
  on bpos.products (outlet_id) where show_on_web and is_active;

-- ---------- 2. web order inbox ----------
create table if not exists bpos.web_orders (
  id              uuid primary key default gen_random_uuid(),
  outlet_id       uuid not null references bpos.outlets(id),
  order_number    integer not null,
  public_token    uuid not null default gen_random_uuid() unique,
  order_type      text not null check (order_type in ('dine_in', 'takeaway')),
  customer_name   text not null check (char_length(customer_name) between 1 and 80),
  customer_phone  text not null check (customer_phone ~ '^[0-9]{10,15}$'),
  table_label     text check (table_label is null or char_length(table_label) <= 20),
  notes           text check (notes is null or char_length(notes) <= 300),
  subtotal        numeric(12,2) not null check (subtotal >= 0),
  status          text not null default 'pending'
                  check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  reject_reason   text,
  decided_by      uuid references bpos.users(id),
  decided_at      timestamptz,
  created_at      timestamptz not null default now(),
  unique (outlet_id, order_number)
);

create table if not exists bpos.web_order_items (
  id            uuid primary key default gen_random_uuid(),
  web_order_id  uuid not null references bpos.web_orders(id) on delete cascade,
  product_id    uuid references bpos.products(id) on delete set null,
  -- Snapshots: a later menu replacement must not change what the customer ordered (CLAUDE.md §26).
  item_name     text not null,
  variant_name  text,
  modifiers     jsonb not null default '[]'::jsonb,   -- [{"name": "...", "price": 10}]
  unit_price    numeric(12,2) not null check (unit_price >= 0),   -- variant/base price + modifiers
  quantity      integer not null check (quantity between 1 and 50),
  note          text check (note is null or char_length(note) <= 200)
);

create index if not exists web_orders_outlet_status_idx on bpos.web_orders (outlet_id, status, created_at desc);
create index if not exists web_orders_phone_idx          on bpos.web_orders (outlet_id, customer_phone, created_at desc);
create index if not exists web_order_items_order_idx     on bpos.web_order_items (web_order_id);

-- ---------- 3. RLS: staff only, per outlet. anon has no direct table access. ----------
alter table bpos.web_orders      enable row level security;
alter table bpos.web_order_items enable row level security;

revoke all on bpos.web_orders, bpos.web_order_items from anon;
grant select, update on bpos.web_orders      to authenticated;
grant select          on bpos.web_order_items to authenticated;

drop policy if exists web_orders_select on bpos.web_orders;
create policy web_orders_select on bpos.web_orders for select to authenticated
using (bpos.has_permission(outlet_id, 'order.view'));

drop policy if exists web_orders_decide on bpos.web_orders;
create policy web_orders_decide on bpos.web_orders for update to authenticated
using (bpos.has_permission(outlet_id, 'order.create'))
with check (bpos.has_permission(outlet_id, 'order.create'));

drop policy if exists web_order_items_select on bpos.web_order_items;
create policy web_order_items_select on bpos.web_order_items for select to authenticated
using (bpos.has_permission((select o.outlet_id from bpos.web_orders o where o.id = web_order_id), 'order.view'));

-- Staff may only move a pending order to a decision; who/when is stamped here, not trusted from the client.
create or replace function bpos.web_orders_guard() returns trigger
language plpgsql security definer set search_path = bpos, public
as $$
begin
  -- Only staff decisions are guarded. Internal updates (web_place_order totalling the order) and
  -- admin/service sessions pass through untouched.
  if coalesce(auth.role(), '') <> 'authenticated' then
    return new;
  end if;
  if old.status <> 'pending' then
    raise exception 'This web order was already %', old.status using errcode = 'P0001';
  end if;
  if new.status not in ('accepted', 'rejected', 'cancelled') then
    raise exception 'Invalid status' using errcode = 'P0001';
  end if;
  -- Everything except the decision itself is immutable after submission.
  new.id := old.id; new.outlet_id := old.outlet_id; new.order_number := old.order_number;
  new.public_token := old.public_token; new.order_type := old.order_type;
  new.customer_name := old.customer_name; new.customer_phone := old.customer_phone;
  new.table_label := old.table_label; new.notes := old.notes; new.subtotal := old.subtotal;
  new.created_at := old.created_at;
  new.decided_by := bpos.current_user_id();
  new.decided_at := now();
  return new;
end $$;

drop trigger if exists web_orders_guard on bpos.web_orders;
create trigger web_orders_guard before update on bpos.web_orders
for each row execute function bpos.web_orders_guard();

-- ---------- 4. public menu ----------
create or replace function bpos.web_menu(p_outlet_code text)
returns jsonb
language plpgsql stable security definer set search_path = bpos, public
as $$
declare
  v_outlet bpos.outlets%rowtype;
  v_result jsonb;
begin
  select * into v_outlet from bpos.outlets where code = p_outlet_code limit 1;
  if not found or not v_outlet.web_menu_enabled then
    return jsonb_build_object('enabled', false);
  end if;

  select jsonb_build_object(
    'enabled', true,
    'outlet', jsonb_build_object('name', v_outlet.name, 'phone', v_outlet.phone, 'address', v_outlet.address),
    'items', coalesce(jsonb_agg(item order by sort_cat, sort_item), '[]'::jsonb)
  ) into v_result
  from (
    select
      coalesce(parent.display_order, c.display_order, 9999) as sort_cat,
      p.display_order as sort_item,
      jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'description', p.description,
        'type', p.type,
        'category', coalesce(parent.name, c.name, 'Others'),
        'sub_category', case when parent.id is null then null else c.name end,
        'price', p.base_price,
        'variants', coalesce((
          select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'price', v.price) order by v.display_order)
          from bpos.product_variants v where v.product_id = p.id and v.is_active), '[]'::jsonb),
        'modifiers', coalesce((
          select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'price', m.price) order by m.display_order)
          from (
            select modifier_group_id from bpos.product_modifier_groups where product_id = p.id
            union
            select vg.modifier_group_id from bpos.variant_modifier_groups vg
              join bpos.product_variants pv on pv.id = vg.variant_id where pv.product_id = p.id and pv.is_active
          ) g
          join bpos.modifiers m on m.modifier_group_id = g.modifier_group_id and m.is_active), '[]'::jsonb)
      ) as item
    from bpos.products p
    left join bpos.categories c on c.id = p.category_id
    left join bpos.categories parent on parent.id = c.parent_id
    left join bpos.menu_versions mv on mv.id = p.menu_version_id
    where p.outlet_id = v_outlet.id
      and p.is_active and p.show_on_web
      and (mv.id is null or mv.status = 'active')
  ) q;

  return v_result;
end $$;

-- ---------- 5. place an order ----------
create or replace function bpos.web_place_order(
  p_outlet_code text,
  p_name        text,
  p_phone       text,
  p_order_type  text,
  p_table       text,
  p_notes       text,
  p_items       jsonb
) returns jsonb
language plpgsql security definer set search_path = bpos, public
as $$
declare
  v_outlet   bpos.outlets%rowtype;
  v_phone    text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_name     text := btrim(coalesce(p_name, ''));
  v_order_id uuid;
  v_number   integer;
  v_token    uuid;
  it         jsonb;
  v_prod     bpos.products%rowtype;
  v_var      bpos.product_variants%rowtype;
  v_unit     numeric(12,2);
  v_qty      integer;
  v_mods     jsonb;
  v_mod_ids  uuid[];
  v_found    integer;
begin
  select * into v_outlet from bpos.outlets where code = p_outlet_code limit 1;
  if not found or not v_outlet.web_menu_enabled then
    raise exception 'Online ordering is not available' using errcode = 'P0001';
  end if;
  if char_length(v_name) not between 1 and 80 then
    raise exception 'Please enter your name' using errcode = 'P0001';
  end if;
  -- Indian mobiles are typed with or without +91 / 0; keep the last 10 digits when longer.
  if char_length(v_phone) > 10 then v_phone := right(v_phone, 10); end if;
  if v_phone !~ '^[0-9]{10}$' then
    raise exception 'Please enter a valid 10-digit mobile number' using errcode = 'P0001';
  end if;
  if p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'Choose Dine In or Takeaway' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 40 then
    raise exception 'Your cart is empty' using errcode = 'P0001';
  end if;

  -- Abuse limits: one phone can't flood the counter, and the outlet's inbox has a ceiling.
  if (select count(*) from bpos.web_orders
        where outlet_id = v_outlet.id and customer_phone = v_phone
          and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many orders from this number. Please call the restaurant.' using errcode = 'P0001';
  end if;
  if (select count(*) from bpos.web_orders where outlet_id = v_outlet.id and status = 'pending') >= 100 then
    raise exception 'The restaurant is busy right now. Please try again shortly.' using errcode = 'P0001';
  end if;

  -- Serialise number allocation per outlet so two simultaneous orders can't collide.
  perform pg_advisory_xact_lock(hashtextextended(v_outlet.id::text, 0));
  select coalesce(max(order_number), 0) + 1 into v_number from bpos.web_orders where outlet_id = v_outlet.id;

  insert into bpos.web_orders (outlet_id, order_number, order_type, customer_name, customer_phone,
                               table_label, notes, subtotal)
  values (v_outlet.id, v_number, p_order_type, v_name, v_phone,
          nullif(left(btrim(coalesce(p_table, '')), 20), ''),
          nullif(left(btrim(coalesce(p_notes, '')), 300), ''), 0)
  returning id, public_token into v_order_id, v_token;

  for it in select * from jsonb_array_elements(p_items) loop
    v_qty := coalesce((it ->> 'quantity')::integer, 0);
    if v_qty not between 1 and 50 then
      raise exception 'Invalid quantity' using errcode = 'P0001';
    end if;

    -- Only products the owner marked visible on the web, in this outlet, can be ordered.
    select p.* into v_prod
    from bpos.products p
    left join bpos.menu_versions mv on mv.id = p.menu_version_id
    where p.id = (it ->> 'product_id')::uuid
      and p.outlet_id = v_outlet.id and p.is_active and p.show_on_web
      and (mv.id is null or mv.status = 'active');
    if not found then
      raise exception 'An item in your cart is no longer available. Please refresh the menu.' using errcode = 'P0001';
    end if;

    v_unit := coalesce(v_prod.base_price, 0);
    v_var := null;
    if nullif(it ->> 'variant_id', '') is not null then
      select * into v_var from bpos.product_variants
      where id = (it ->> 'variant_id')::uuid and product_id = v_prod.id and is_active;
      if not found then
        raise exception 'An option in your cart is no longer available. Please refresh the menu.' using errcode = 'P0001';
      end if;
      v_unit := v_var.price;
    elsif exists (select 1 from bpos.product_variants where product_id = v_prod.id and is_active) then
      raise exception 'Please choose a size for %', v_prod.name using errcode = 'P0001';
    end if;

    -- Add-ons: only modifiers actually attached to this product/variant; prices come from the DB.
    v_mods := '[]'::jsonb;
    v_mod_ids := array(select (x)::uuid from jsonb_array_elements_text(coalesce(it -> 'modifier_ids', '[]'::jsonb)) x);
    if coalesce(array_length(v_mod_ids, 1), 0) > 0 then
      select coalesce(jsonb_agg(jsonb_build_object('name', m.name, 'price', m.price)), '[]'::jsonb), count(*)
        into v_mods, v_found
      from bpos.modifiers m
      where m.id = any (v_mod_ids) and m.is_active
        and m.modifier_group_id in (
          select modifier_group_id from bpos.product_modifier_groups where product_id = v_prod.id
          union
          select vg.modifier_group_id from bpos.variant_modifier_groups vg
            join bpos.product_variants pv on pv.id = vg.variant_id where pv.product_id = v_prod.id);
      if v_found <> (select count(distinct x) from unnest(v_mod_ids) x) then
        raise exception 'An add-on in your cart is no longer available. Please refresh the menu.' using errcode = 'P0001';
      end if;
      v_unit := v_unit + (select coalesce(sum((e ->> 'price')::numeric), 0) from jsonb_array_elements(v_mods) e);
    end if;

    insert into bpos.web_order_items (web_order_id, product_id, item_name, variant_name, modifiers, unit_price, quantity, note)
    values (v_order_id, v_prod.id, v_prod.name, v_var.name, v_mods, v_unit, v_qty,
            nullif(left(btrim(coalesce(it ->> 'note', '')), 200), ''));
  end loop;

  update bpos.web_orders
     set subtotal = (select coalesce(sum(unit_price * quantity), 0) from bpos.web_order_items where web_order_id = v_order_id)
   where id = v_order_id;

  return jsonb_build_object(
    'order_number', v_number,
    'public_token', v_token,
    'subtotal', (select subtotal from bpos.web_orders where id = v_order_id));
end $$;

-- ---------- 6. customer tracking link ----------
create or replace function bpos.web_order_status(p_token uuid)
returns jsonb
language sql stable security definer set search_path = bpos, public
as $$
  select jsonb_build_object(
    'order_number', o.order_number,
    'status', o.status,
    'order_type', o.order_type,
    'customer_name', o.customer_name,
    'subtotal', o.subtotal,
    'reject_reason', o.reject_reason,
    'outlet_name', ou.name,
    'outlet_phone', ou.phone,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'name', i.item_name, 'variant', i.variant_name, 'modifiers', i.modifiers,
        'quantity', i.quantity, 'unit_price', i.unit_price) )
      from bpos.web_order_items i where i.web_order_id = o.id), '[]'::jsonb))
  from bpos.web_orders o join bpos.outlets ou on ou.id = o.outlet_id
  where o.public_token = p_token;
$$;

revoke all on function bpos.web_menu(text), bpos.web_place_order(text, text, text, text, text, text, jsonb),
  bpos.web_order_status(uuid) from public;
grant execute on function bpos.web_menu(text), bpos.web_place_order(text, text, text, text, text, text, jsonb),
  bpos.web_order_status(uuid) to anon, authenticated;

-- ---------- 7. staff switch (Settings -> Web ordering) ----------
-- outlets has no staff UPDATE policy, so the on/off switch is a permission-checked function instead.
create or replace function bpos.set_web_menu_enabled(p_outlet_code text, p_enabled boolean)
returns boolean
language plpgsql security definer set search_path = bpos, public
as $$
declare v_outlet uuid;
begin
  select id into v_outlet from bpos.outlets where code = p_outlet_code;
  if v_outlet is null or not bpos.has_permission(v_outlet, 'settings.manage') then
    raise exception 'You do not have permission to change this' using errcode = 'P0001';
  end if;
  update bpos.outlets set web_menu_enabled = p_enabled where id = v_outlet;
  return p_enabled;
end $$;

revoke all on function bpos.set_web_menu_enabled(text, boolean) from public, anon;
grant execute on function bpos.set_web_menu_enabled(text, boolean) to authenticated;

commit;

-- ---------- Verify (run separately) ----------
-- select table_name, column_name from information_schema.columns
--  where table_schema = 'bpos' and (table_name, column_name) in
--   (('products','show_on_web'), ('outlets','web_menu_enabled'), ('web_orders','public_token'), ('web_order_items','modifiers'));
-- select tablename, rowsecurity from pg_tables where schemaname = 'bpos' and tablename like 'web_order%';
--
-- Turn it on for an outlet and mark a few products:
--   update bpos.outlets  set web_menu_enabled = true where code = '<OUTLET CODE>';
--   update bpos.products set show_on_web = true where outlet_id = (select id from bpos.outlets where code = '<OUTLET CODE>') and name in ('Alfaham');
