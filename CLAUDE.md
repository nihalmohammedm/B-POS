BPOS --- Claude Project Context

1. Project Overview

BPOS is a restaurant Point of Sale and operations system being built for
multi-outlet restaurant businesses.

The system is designed around:

Main POS

Captain devices

Cashier workflow

Manager/Owner administration

Offline-first operation

Supabase backend

Outlet-specific configuration

Menu versioning and complete menu replacement

KOT routing and printer sharing

Bill requests

Payments

Auditability

The database uses the PostgreSQL schema:

bpos

Do not create another schema unless explicitly requested.

2. Core Design Principles

Outlet-specific by default

Everything operational should be associated with an outlet.

The system may eventually support multiple outlets under one business.

Examples:

Menu

Tables

Users

Printers

KOT groups

Settings

Devices

Payments

Orders

Reports

Do not assume data is global unless it is clearly reusable
infrastructure.

3. Roles

Existing roles:

Code      Name

captain   Captain
cashier   Cashier
manager   Manager
owner     Owner

Existing permissions include:

bill.create
bill.request
bill.split
bill.view

device.manage

discount.apply

inventory.manage
inventory.view

kot.reprint

menu.manage
menu.view

order.cancel
order.create
order.view

payment.create
payment.refund
payment.split

printer.manage
printer.view

report.view

settings.manage
settings.view

table.view

user.manage

Captain and Cashier have restricted permissions.

Manager and Owner currently have the full permission set.

Do not change role permissions casually. Inspect the current database
before modifying them.

4. Menu Architecture

The menu is outlet-specific and versioned.

The user wants the ability to:

Upload/replace the entire menu

Import menu data from Excel

Configure products

Configure variants

Configure modifier groups

Reuse modifier groups across multiple products

Have different modifier groups for different items/variants

Assign KOT groups

Have product types:

veg

non-veg

egg

Example Excel structure discussed:

item_code,product,category,variant,variant_price,kot_group,type
001,Alfaham,Grill,1 Quarter,150.00,Grill,non-veg
001,Alfaham,Grill,1 Half,300.00,Grill,non-veg
001,Alfaham,Grill,1 Full,550.00,Grill,non-veg
002,Shawarma,Grill,,,Grill,non-veg
003,Porotta,Bread,,,Bread,veg
004,Chicken Fried Rice,Rice,,,Rice,non-veg
005,Fresh Lime,Drinks,,,Drinks,veg

The exact Excel format can evolve, but the database must support the
same concepts.

5. Menu Versioning

Existing table:

bpos.menu_versions

It already contains:

id

outlet_id

version_number

status

source

source_file_name

created_by

activated_at

archived_at

created_at

scheduled_at

Menu version statuses already have a check constraint.

Expected lifecycle:

draft
  ↓
scheduled
  ↓
active
  ↓
archived

Immediate activation should also be supported.

Each menu version owns its products/categories/modifier configuration.

Important:

Historical orders must NOT change when a new menu is uploaded.

Old orders must retain their original item/price information.

6. Menu Tables

Existing tables:

categories
products
product_variants
modifier_groups
modifiers
product_modifier_groups
variant_modifier_groups
product_kot_groups
kot_groups

Categories

categories contains:

id

outlet_id

name

display_order

is_active

created_at

updated_at

menu_version_id

Categories were updated to belong to a menu version.

Products

products contains:

id

menu_version_id

outlet_id

item_code

name

category_id

description

base_price

has_variants

display_order

is_active

created_at

updated_at

type

type represents:

veg
non-veg
egg

Products are versioned through menu_version_id.

Product Variants

Variants belong to products.

Example:

Alfaham
├── 1 Quarter
├── 1 Half
└── 1 Full

Variants contain:

product_id

kot_group_id

name

price

display_order

is_default

is_active

created_at

Do NOT add menu_version_id to variants unnecessarily because the
product already determines the menu version.

Modifier Groups

Modifier groups are reusable.

Example:

Sauces
  ├── Mayo
  ├── Garlic Sauce
  └── Chutney

Extras
  ├── Cheese
  └── Egg

A modifier group can be reused across multiple products.

Existing modifier_groups includes:

id

outlet_id

name

description

is_required

min_selections

max_selections

display_order

is_active

created_at

updated_at

menu_version_id

Modifiers belong to modifier groups.

product_modifier_groups maps products to modifier groups.

variant_modifier_groups maps variants to modifier groups.

Unique relationships should be enforced:

product_id + modifier_group_id
variant_id + modifier_group_id

7. KOT Architecture

KOT = Kitchen Order Ticket.

KOT groups are operational sections such as:

Grill
Bread
Rice
Drinks

A product or variant can route to a KOT group.

The important requirement:

One order can generate multiple KOTs.

Example:

Order #1001

Grill KOT
  Alfaham

Bread KOT
  Porotta

The system must NOT assume one order = one KOT.

8. Printer Sharing

This is a critical requirement.

A single physical printer can print multiple KOT groups.

Example:

Grill KOT ──┐
            ├── Printer 1
Bread KOT ──┘

Therefore:

bpos.kot_group_printers

maps KOT groups to printers.

The relationship must allow:

one KOT group → multiple printers

one printer → multiple KOT groups

A uniqueness constraint exists on:

kot_group_id + printer_id

Do not remove this many-to-many relationship.

9. Printers

Existing table:

bpos.printers

Supports:

connection_type:
  lan
  bluetooth

LAN printers use:

ip_address

port

Bluetooth printers use:

bluetooth_address

The current database validates connection configuration.

Do not invent other connection types without changing the design
intentionally.

Printers are outlet-specific.

10. Print Queue

Existing table:

bpos.print_jobs

Supports immediate print processing with retries.

Fields include:

outlet_id

printer_id

document_type

document_id

status

priority

attempts

max_attempts

error_message

queued_at

started_at

printed_at

failed_at

created_at

updated_at

Existing document types include:

kot
kot_cancellation
bill
bill_reprint
free_bill

Existing statuses:

queued
printing
printed
failed
cancelled

Printing is intended to be immediate but processed through a queue so
failures can be retried.

11. KOT Quantity Tracking

Orders may receive additional items after the first KOT.

Example:

Initial order:
Porotta × 2

Later:
Porotta × 2

The second KOT must print only the newly added quantity.

order_items therefore tracks:

quantity
kot_quantity
last_kot_at

Concept:

quantity = total ordered
kot_quantity = quantity already sent to KOT
remaining = quantity - kot_quantity

Do not reprint the entire order whenever an item is added.

12. KOT Cancellation

Captains and Cashiers can cancel order items.

Cancellation uses predefined configurable reasons.

Existing table:

bpos.cancellation_reasons

Reasons are outlet-specific.

Examples:

Customer changed mind
Wrong item entered
Out of stock
Kitchen unable to prepare
Duplicate order
Captain mistake
Other

Existing table:

bpos.order_item_cancellations

records:

order_item_id

cancellation_reason_id

quantity

reason_snapshot

cancelled_by_user_id

kot_id

created_at

Important:

If an item quantity is 4 and 1 is cancelled:

Ordered = 4
Cancelled = 1
Remaining = 3

Do not simply overwrite the original order quantity.

A cancellation KOT should be generated and printed.

13. Captains

Captain devices are registered separately from POS devices.

Existing tables:

captain_devices
captain_device_sessions
pos_devices

Main POS

pos_devices represents POS devices.

A primary Main POS can be identified using:

is_primary

Captain Device Pairing

captain_devices already contains:

outlet_id

main_pos_device_id

device_name

device_identifier

paired_user_id

pairing_token_hash

paired_at

last_seen_at

is_active

created_at

updated_at

pairing_expires_at

pairing_used_at

QR pairing should use a short-lived token.

Never store the raw pairing token.

Store only its hash.

Flow:

Main POS
  ↓
Generate short-lived pairing token
  ↓
Create QR
  ↓
Captain scans QR
  ↓
Verify token hash + expiry
  ↓
Register Captain device
  ↓
Create device session

The QR is for pairing, not permanent authentication.

Captain Sessions

captain_device_sessions stores hashed session tokens.

Never store raw session tokens.

14. Captain Visibility

Captain A and Captain B must be able to see each other's orders when
operating at the same outlet/table.

Assignment does NOT equal visibility restriction.

Existing table:

party_captains

records Captain assignment history.

A Captain may be assigned to a party, but the application must not
filter all orders using:

text captain_id = current_user

Instead, Captains should be able to see relevant active
outlet/table/party orders according to role permissions.

15. Tables and Parties

Existing tables:

tables
table_sessions
parties
party_captains

Multiple parties can share a physical table.

Example:

Table 12
├── Party A
│   └── Captain A
│
└── Party B
    └── Captain B

These parties must have separate orders/bills.

The system must support splitting unrelated parties sharing the same
table.

16. Orders

Existing core tables:

orders
order_items
order_item_modifiers
kots
kot_items

Orders belong to the appropriate outlet/session/party context.

Order items must preserve historical item information needed for old
bills and reports.

Do not rely solely on current menu records for historical orders.

17. Bill Workflow

There are two different concepts:

Cashier-created bill

Cashier can create/complete a bill directly.

Captain bill request

Captain requests a bill from the Main POS.

Example notification:

Captain 1 is asking for Bill
Table 12

This appears as an in-UI notification/modal in the Main POS.

Existing table:

bill_requests

and:

notifications

are used for this workflow.

The Captain should be able to request a bill without directly
controlling the cashier's final payment process.

18. Free Bills

The system must support a free bill for:

Owner guests

Complimentary meals

Other authorized free transactions

A free bill should be explicitly identified.

It should NOT simply be a normal bill with payment amount manually
changed to zero.

Printing uses:

document_type = free_bill

Permissions should determine who can create/approve free bills.

The database should preserve:

reason

user

outlet

order

bill

timestamp

19. Payments

Existing tables:

payments
payment_methods
payment_refunds

The system should support:

cash

configured digital payment methods

split payments

refunds

bill splitting

Do not hard-code payment methods into application logic if they can be
outlet-configured.

20. Offline Architecture

The system is intended to work offline.

Main POS and Captain devices should retain enough local data to operate
without internet.

Initial local/syncable configuration includes:

menu
tables
printers
KOT configuration
captain configuration
outlet settings

The application should be able to continue basic operation while offline
and synchronize when connectivity returns.

Current sync tables:

device_sync_state
sync_logs
sync_versions

Device Sync State

Tracks current synchronization state per device and sync key.

Example:

menu       → synced
tables     → synced
printers   → synced
kot_config → synced
captains   → synced

Sync Logs

Tracks individual sync attempts:

download
upload
started
completed
failed

Sync Versions

Tracks monotonically increasing versions per outlet/sync key.

Example:

menu       → 42
tables     → 8
printers   → 13
kot_config → 7

Future incremental sync can use these versions to download only changes.

21. Device Architecture

Existing:

pos_devices
captain_devices
captain_device_sessions

Main POS is the authoritative local operational device for an outlet
when configured that way.

Captain devices can operate independently while connected/offline, then
sync.

Do not assume every device has unrestricted administrative capability.

22. Existing Database Tables

Current bpos schema contains:

bill_items
bill_requests
bills
cancellation_reasons
captain_device_sessions
captain_devices
categories
device_sync_state
kot_group_printers
kot_groups
kot_items
kots
menu_versions
modifier_groups
modifiers
notifications
order_item_cancellations
order_item_modifiers
order_items
orders
outlet_settings
outlet_users
outlets
parties
party_captains
payment_methods
payment_refunds
payments
permissions
pos_devices
print_jobs
printers
product_kot_groups
product_modifier_groups
product_variants
products
role_permissions
roles
sync_logs
sync_versions
table_sessions
tables
users
variant_modifier_groups

Before creating ANY new table, inspect this list/database first.

Do not duplicate an existing table.

23. Critical Development Rule

DO NOT blindly run ALTER TABLE statements.

The schema has already been partially built.

Before adding:

table

column

constraint

index

enum/check

foreign key

inspect whether it already exists.

Use PostgreSQL catalog queries such as:

select
    column_name,
    data_type,
    is_nullable
from information_schema.columns
where table_schema = 'bpos'
  and table_name = 'TABLE_NAME'
order by ordinal_position;

For constraints:

select
    conname,
    pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'bpos.TABLE_NAME'::regclass;

For tables:

select table_name
from information_schema.tables
where table_schema = 'bpos'
  and table_type = 'BASE TABLE'
order by table_name;

24. Migration Strategy

Do NOT make the developer execute dozens of tiny changes one by one.

For future schema changes:

Audit the current schema.

Compare it against requirements.

Produce ONE consolidated migration.

Use safe guards such as:

create table if not exists

add column if not exists

explicit constraint existence checks where PostgreSQL does not
support if not exists

Handle existing data before adding NOT NULL.

Add indexes and constraints in the same migration where appropriate.

Give one complete SQL block for the migration.

Verify after execution with a focused query.

Never tell the developer to blindly recreate an existing object.

25. RLS

Supabase/PostgREST is being used with the bpos schema.

The schema must be included in:

PGRST_DB_SCHEMAS

The system should use Row Level Security to ensure users can access only
authorized outlet data.

Important:

Owner/Manager may have broader outlet access according to
configuration.

Captain should be limited to authorized outlet(s).

Cashier should be limited to authorized outlet(s).

Users should not be able to access another outlet's
orders/menu/printers merely by changing an ID in the request.

Device authentication does not replace database authorization.

RLS policies must be designed around outlet_users and role/permission
membership.

Do not disable RLS as a shortcut.

26. Historical Data

Historical orders, bills, payments, cancellations, and printed documents
must remain valid after:

menu replacement

product deactivation

category changes

modifier changes

price changes

KOT routing changes

Never make historical transactions depend exclusively on the current
menu.

27. Printing Requirements

Printing must support:

immediate printing

queueing

retry

failure reporting

multiple printers

LAN printers

Bluetooth printers

printer sharing

multiple KOT groups from one order

KOT cancellation printing

bill printing

bill reprint

free bill printing

Example:

Order #500

Items:
Alfaham × 1
Porotta × 2
Fresh Lime × 1

Routing:

Grill KOT
  Alfaham
  → Printer A

Bread KOT
  Porotta
  → Printer A

Drinks KOT
  Fresh Lime
  → Printer B

Printer A therefore receives two separate KOT print jobs for the same
order.

28. Bill Splitting

The system should support:

splitting a bill

splitting payments

multiple parties

separate bills for unrelated customers sharing a table

Do not confuse:

party split
bill split
payment split

They are different operations.

29. Reporting and Audit

Reports should eventually cover:

sales

payments

refunds

cancellations

free bills

discounts

KOT activity

printer failures

device sync

user actions

For important destructive/financial actions, preserve:

who did it

what happened

when

outlet

reason where applicable

30. UI/UX Direction

The system is intended for real restaurant use.

Prioritize:

fast touch interaction

minimal typing

large tap targets

clear order state

clear KOT status

clear printer status

offline indication

sync status

immediate feedback

simple Captain workflow

simple Cashier workflow

Avoid unnecessarily gentle/pastel UI.

The POS should feel operational, fast, and information-dense.

31. Development Behavior for Claude

When working on this project:

Read this file before making architectural decisions.

Inspect the current database before proposing schema changes.

Do not recreate tables that already exist.

Do not assume an earlier schema is empty.

Do not blindly add columns/constraints.

Prefer one complete migration over many tiny SQL commands.

Keep outlet isolation in mind.

Keep offline behavior in mind.

Keep historical transaction integrity in mind.

Do not simplify away printer sharing.

Do not simplify one-order/multiple-KOT behavior.

Do not restrict Captain visibility to only their own orders.

Do not store raw pairing/session tokens.

Do not use the current menu as the source of truth for historical
transactions.

Ask before making a major architectural change.

When a schema change is needed, first produce a concise audit of what
already exists and what is missing, then provide the complete migration.

32. Current Priority

The database structure is substantially built.

Do NOT continue adding random tables.

Next work should be:

Complete schema audit

Fix/verify constraints and indexes

Verify foreign keys

Verify outlet isolation

Implement RLS

Seed sensible configuration/dummy data

Build sync behavior

Build KOT generation/print queue

Build Captain pairing/session flow

Build Main POS ↔ Captain bill request notifications

Test offline/online synchronization

Test menu replacement and historical orders