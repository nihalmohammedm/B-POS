# BPOS — Claude Development Specification

## 1. Project Overview

BPOS is a new restaurant Point-of-Sale system designed for multi-outlet restaurant operations.

The system consists of:

1. **Main POS**

   * Flutter application
   * Runs primarily on an Android tablet/device
   * Acts as the local authority for the outlet
   * Stores operational data locally
   * Runs the local network API/WebSocket service
   * Handles printing
   * Syncs data to Supabase when Internet is available

2. **Captain App**

   * Flutter application
   * Runs on Android and iOS
   * Used by waiters/captains to take orders
   * Connects directly to the Main POS over the restaurant's local Wi-Fi
   * Must continue working without Internet
   * Does NOT directly depend on Supabase for normal restaurant operations

3. **Supabase**

   * Cloud backend
   * Shared with the existing B Ops application
   * Contains historical data and configuration
   * Receives synchronized data from Main POS
   * B Ops can manage outlets, menus, users, etc.
   * Supabase is NOT the real-time operational dependency of the POS

4. **B Ops**

   * Existing application
   * Uses the same Supabase project
   * Should be able to display relevant BPOS data
   * Can manage menu/configuration data
   * Can manage multiple outlets

---

# 2. Core Architectural Principle

The most important architectural rule:

> Main POS is the local operational authority.

Do NOT build the system as:

```text
Flutter → Supabase
```

Instead:

```text
Captain
    ↓
Local Wi-Fi
    ↓
Main POS
    ↓
Local Database
    ↓
Print Queue
```

and separately:

```text
Main POS Local Database
    ↓
Background Sync
    ↓
Supabase
    ↓
B Ops
```

Internet failure must NOT stop normal restaurant operations.

---

# 3. Offline-First Requirements

The restaurant must continue operating if the Internet disappears.

The Main POS must locally store:

* Outlet configuration
* Menu
* Categories
* Products
* Variants
* Modifier groups
* Modifiers
* Tables
* Table occupancy
* Users/captains
* Printers
* KOT groups
* Orders
* Order items
* KOTs
* Bills
* Payments
* Print jobs
* Sync queue

Supabase is used for synchronization and historical data.

## Local data retention

Main POS should retain approximately:

* Current day order data
* Previous day order data

Older order data can be fetched from Supabase when needed.

However:

> Any active/open order must remain locally available until completely closed and synchronized.

---

# 4. First-Time Main POS Setup

Main POS requires Internet during first-time setup.

Initial setup:

```text
Install Main POS
    ↓
Internet required
    ↓
Select/register Outlet
    ↓
Authenticate
    ↓
Download outlet configuration
    ↓
Download menu
    ↓
Download tables
    ↓
Download users/captains
    ↓
Download printers
    ↓
Download KOT groups
    ↓
Initialize local database
    ↓
Ready for offline operation
```

After initialization, Internet is optional for normal operations.

---

# 5. Multi-Outlet Architecture

Everything operational is outlet-specific.

Every relevant Supabase table must contain:

```text
outlet_id
```

unless the entity is inherently global.

Examples:

```text
Outlet A
 ├── Menu
 ├── Categories
 ├── Products
 ├── Variants
 ├── Modifiers
 ├── Tables
 ├── Printers
 ├── KOT Groups
 ├── Captains
 └── Orders

Outlet B
 ├── Menu
 ├── Categories
 ├── Products
 ├── Variants
 ├── Modifiers
 ├── Tables
 ├── Printers
 ├── KOT Groups
 ├── Captains
 └── Orders
```

Do not assume one restaurant/outlet.

---

# 6. Supabase Schema

The BPOS database lives in:

```text
bpos
```

schema.

The existing Supabase project is shared with B Ops.

Do not create BPOS tables in `public` unless explicitly required.

Current core tables:

```text
bpos.outlets
bpos.users
bpos.roles
bpos.permissions
bpos.role_permissions
bpos.outlet_users
bpos.pos_devices
bpos.captain_devices
bpos.payment_methods
bpos.outlet_settings
```

Current menu tables:

```text
bpos.categories
bpos.kot_groups

bpos.menu_versions
bpos.products
bpos.product_variants
bpos.product_kot_groups

bpos.modifier_groups
bpos.modifiers
bpos.product_modifier_groups
bpos.variant_modifier_groups
```

---

# 7. Existing Roles

The current roles are:

```text
owner
manager
cashier
captain
```

Current permission counts:

```text
captain = 7
cashier = 7
manager = 24
owner = 24
```

## Captain permissions

```text
table.view
order.create
order.view
order.cancel
kot.reprint
bill.request
bill.view
```

## Cashier permissions

```text
table.view
order.view
kot.reprint
bill.view
bill.create
payment.create
payment.split
```

Manager and Owner currently receive all available permissions.

Permissions are database-driven and should eventually be configurable through B Ops.

---

# 8. Payment Methods

Payment methods are outlet-specific.

Default methods:

```text
Cash
UPI
Card
```

The system supports split payments.

Example:

```text
Bill = ₹1500

Cash = ₹500
UPI  = ₹700
Card = ₹300
```

Payment methods are represented as separate payment records.

Current outlet settings include:

```text
inventory_enabled
currency_code
tax_enabled
allow_split_payment
```

Default currency:

```text
INR
```

---

# 9. Main POS

The Main POS is the central authority inside the restaurant.

Responsibilities:

* Maintain local database
* Receive Captain requests
* Validate operations
* Create orders
* Create parties
* Create KOTs
* Queue printing
* Create bills
* Process payments
* Broadcast updates to Captain devices
* Maintain local sync queue
* Sync to Supabase
* Receive menu/configuration updates
* Maintain printer connections
* Maintain device registrations

Captains should NOT directly mutate the operational database.

They send commands to Main POS.

---

# 10. Captain App

Captain devices connect to the Main POS over the same local Wi-Fi network.

Supported:

* Android
* iOS

The Captain app must work without Internet as long as the Main POS and local Wi-Fi are available.

Normal architecture:

```text
Captain App
    ↓
Local network
    ↓
Main POS API/WebSocket
```

Do not make Captain depend on Supabase for normal order-taking.

---

# 11. Main POS Local Networking

Main POS should expose a local service.

Use:

* HTTP API for commands/requests
* WebSocket for real-time updates
* mDNS/Bonjour for local discovery

Captain should NOT permanently store the Main POS IP address.

Example:

```text
Main POS
Service: bollgattea-pos
IP: 192.168.1.10
```

If the router changes the POS IP:

```text
192.168.1.10
       ↓
192.168.1.25
```

Captain should rediscover the POS automatically.

---

# 12. Captain Device Registration

Captain devices are registered through QR pairing.

Flow:

```text
Main POS
    ↓
Generate pairing QR
    ↓
Captain scans QR
    ↓
Captain discovers Main POS
    ↓
Verify pairing token
    ↓
Register Captain device
    ↓
Associate Captain with User
```

The QR should not simply contain a permanent secret.

Use a short-lived pairing token / secure pairing mechanism.

Captain should only become usable after Main POS accepts the pairing.

The Main POS must be synchronized/configured before initial device registration when required by the setup flow.

---

# 13. Real-Time Local Synchronization

All Captain devices connected to the same Main POS should see changes in real time.

Example:

```text
Captain A opens Table 12

        ↓

Main POS

        ↓

Captain B
Captain C
Cashier
```

If Captain A adds:

```text
Alfaham Half × 2
```

Captain B opening the same table should immediately see it.

---

# 14. Shared Tables

Tables can be shared by multiple customers/parties.

When tables are initially created, each table has:

```text
maximum_occupancy
```

Example:

```text
Table 12
Maximum occupancy = 6
```

When creating a new party/order, Captain enters the number of people.

Example:

```text
Table 12
Existing Party A = 4 people

New Party B = 2 people

Available capacity = 0
```

The system must prevent:

```text
Existing = 4
New = 3
Maximum = 6
```

from being accepted.

The capacity calculation must happen atomically on Main POS.

---

# 15. Shared Table Party Model

Do not model the table as belonging to only one order.

Correct model:

```text
Table
  ↓
Table Session
  ├── Party A
  │     └── Order
  │
  └── Party B
        └── Order
```

This allows multiple independent bills on one physical table.

Each party should have:

* Party ID
* Number of guests
* Created by Captain
* Created timestamp
* Status

---

# 16. Order Ownership

A Captain creates an order, but the order belongs to the table/party, not permanently to the Captain.

Therefore:

```text
Captain A
    ↓
Table 12 / Party A
    ↓
Order
```

Captain B can later open Table 12 and see:

```text
Captain A
Party A
Guests: 3

Items:
Alfaham Half × 1
Porotta × 4
```

Captain B can continue adding items.

---

# 17. Order Data

Order items should store historical snapshots.

Example:

```text
product_id
variant_id

product_name_snapshot
variant_name_snapshot

unit_price
quantity

created_by_user_id
created_at

status
```

Never depend exclusively on the current menu to display historical orders.

If:

```text
Alfaham Half = ₹300
```

and tomorrow it becomes:

```text
Alfaham Half = ₹330
```

yesterday's order must remain ₹300.

---

# 18. Menu Architecture

Menu is outlet-specific.

B Ops controls the menu.

Main POS downloads/synchronizes it.

The system supports complete menu replacement.

Example:

```text
Outlet A

Menu v1
  ↓ archived

Menu v2
  ↓ archived

Menu v3
  ↓ active
```

Historical orders continue referencing their historical menu/product records.

---

# 19. Menu Import

Menu will likely be imported through Excel.

Initial conceptual format:

```text
Item Code
Item Name
Price
Category
Variants
Variant Name
Variant Pricing
```

Example:

```text
001 | Alfaham |      | Grill |       | 1 Quarter | 150
001 | Alfaham |      | Grill |       | 1 Half    | 300
001 | Alfaham |      | Grill |       | 1 Full    | 550
```

The final Excel importer should support:

* Products
* Categories
* Variants
* Variant prices
* KOT groups
* Modifier groups
* Modifiers
* Modifier pricing
* Relationships

The exact Excel format must remain configurable.

---

# 20. Menu Versions

Current schema:

```text
bpos.menu_versions
```

Fields include:

```text
outlet_id
version_number
status
source
source_file_name
created_by
activated_at
archived_at
created_at
```

Statuses:

```text
draft
processing
active
archived
failed
```

Sources:

```text
manual
excel
```

Only one menu version should be active for an outlet.

A menu can be:

* Created
* Validated
* Scheduled
* Activated immediately
* Activated at a scheduled time
* Archived

---

# 21. Categories

Categories are outlet-specific.

Example:

```text
Grill
Bread
Rice
Drinks
```

Current table:

```text
bpos.categories
```

---

# 22. KOT Groups

KOT Groups are NOT the same thing as Categories.

Example:

```text
Category: Grill
KOT Group: Grill

Category: Drinks
KOT Group: Juice
```

KOT groups determine kitchen/production routing.

Current dummy KOT groups:

```text
GRILL → Grill
BREAD → Bread
RICE  → Rice
JUICE → Juice
```

---

# 23. Products

Current table:

```text
bpos.products
```

Important fields:

```text
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
```

`item_code` is the restaurant's menu/import identifier.

---

# 24. Variants

Current table:

```text
bpos.product_variants
```

Example:

```text
Alfaham

1 Quarter → ₹150 → Grill
1 Half    → ₹300 → Grill
1 Full    → ₹550 → Grill
```

A variant can have its own KOT group.

This is important because KOT routing may differ by variant.

---

# 25. Simple Product KOT Routing

Products without variants use:

```text
bpos.product_kot_groups
```

Example:

```text
Shawarma → Grill
Porotta → Bread
Chicken Fried Rice → Rice
Fresh Lime → Juice
```

For products with variants:

```text
product_variants.kot_group_id
```

takes precedence.

---

# 26. Modifiers

Modifier groups are reusable across products.

Current tables:

```text
bpos.modifier_groups
bpos.modifiers
bpos.product_modifier_groups
bpos.variant_modifier_groups
```

Example:

```text
Sauce
 ├── Mayo +₹20
 ├── Chutney +₹10
 └── Garlic Sauce +₹20
```

A modifier group belongs to an outlet.

A modifier belongs to a modifier group.

---

# 27. Modifier Selection Rules

Modifier groups support:

```text
is_required
min_selections
max_selections
```

Example:

```text
Sauce

Required: false
Minimum: 0
Maximum: 1
```

Example:

```text
Extras

Required: false
Minimum: 0
Maximum: 3
```

---

# 28. Product vs Variant Modifiers

Modifier groups can be assigned at either:

```text
Product level
```

or:

```text
Variant level
```

If a product has variants, the application should use the variant's modifier configuration rather than blindly merging product-level and variant-level groups.

Avoid duplicate modifier groups in the UI.

Example:

```text
Alfaham

Quarter
 └── Sauce

Half
 ├── Sauce
 └── Extras

Full
 ├── Sauce
 └── Extras
```

---

# 29. Current Dummy Menu

Current test outlet:

```text
Code: BOLGATTY
Name: Bollgattea Food Court
```

Categories:

```text
Grill
Bread
Rice
Drinks
```

Products:

```text
001 Alfaham
002 Shawarma
003 Porotta
004 Chicken Fried Rice
005 Fresh Lime
```

Variants:

```text
Alfaham
 ├── 1 Quarter ₹150
 ├── 1 Half ₹300
 └── 1 Full ₹550
```

KOT routing:

```text
Alfaham → Grill
Shawarma → Grill
Porotta → Bread
Chicken Fried Rice → Rice
Fresh Lime → Juice
```

Modifiers:

```text
Sauce
 ├── Mayo ₹20
 ├── Chutney ₹10
 └── Garlic Sauce ₹20

Extras
 ├── Cheese ₹40
 └── Egg ₹20
```

---

# 30. KOT Architecture

One order can create multiple KOTs.

Example:

```text
Order #1001

Grill KOT
 └── Alfaham × 2

Bread KOT
 └── Porotta × 4

Juice KOT
 └── Fresh Lime × 2
```

A single order can therefore produce multiple KOTs.

---

# 31. Printer Sharing

Printer routing must support multiple KOT groups per printer.

Example:

```text
Printer 1

Grill KOT
Bread KOT
```

Therefore one physical printer can print multiple KOT groups.

Another printer might be:

```text
Printer 2

Juice KOT
```

Do NOT assume:

```text
1 KOT Group = 1 Printer
```

The relationship is many-to-many.

Conceptually:

```text
KOT Group
    ↕
Printer
```

---

# 32. KOT Printing

KOT printing happens from Main POS only.

Captain does NOT directly connect to kitchen printers.

Flow:

```text
Captain
    ↓
Main POS
    ↓
Create KOT
    ↓
Print Queue
    ↓
Printer
```

Printing should happen immediately, but through a queue.

Do not block order creation waiting indefinitely for a printer.

---

# 33. Printer Connectivity

Printers may use:

* LAN
* Bluetooth

Printer configuration should therefore include a connection type.

Possible types:

```text
lan
bluetooth
```

LAN printers need appropriate network configuration.

Bluetooth printers require device pairing/identification.

---

# 34. Print Queue

Every print operation should create a local print job.

Conceptually:

```text
print_job

id
printer_id
document_type
document_id
status
attempts
created_at
printed_at
error_message
```

Statuses could include:

```text
queued
printing
printed
failed
cancelled
```

A printer failure must not corrupt the order.

---

# 35. KOT Cancellation

Captains and Cashiers can cancel order items.

Cancellation is NOT implemented by silently deleting the original KOT item.

Example:

```text
Original KOT

Alfaham × 2
```

Captain cancels 1:

```text
Cancellation KOT

CANCELLED
Alfaham × 1
Reason: Customer changed mind
```

The kitchen receives a cancellation KOT.

Predefined cancellation reasons should exist.

Examples:

```text
Customer changed mind
Wrong item
Wrong quantity
Duplicate order
Out of stock
Other
```

The list should eventually be configurable.

---

# 36. Bill Requests

Captain can request a bill.

Example:

```text
Captain 1
    ↓
REQUEST BILL
    ↓
Main POS
```

Main POS shows a UI notification/modal:

```text
Captain 1 is requesting Bill
Table 12
Party 2

[View Order]
[Create Bill]
[Dismiss]
```

The request should be stored locally and synchronized later.

---

# 37. Bill Creation

Bills are created by Main POS.

Captain may request a bill.

The actual bill creation/payment processing happens through Main POS.

Captain can trigger:

```text
Request Bill
```

but should not bypass the Main POS authority.

---

# 38. Payment

Supported payment methods:

```text
Cash
UPI
Card
```

Split payments are supported.

Example:

```text
Total = ₹2000

Cash = ₹500
UPI = ₹1000
Card = ₹500
```

Payment records must be separate.

---

# 39. Main POS Printing of Bills

All physical bill printing is done by Main POS.

Captain may select:

```text
Print Bill
```

but the request goes:

```text
Captain
    ↓
Main POS
    ↓
Bill Printer
```

Captain does not need a directly connected printer.

---

# 40. Local Transaction Authority

Any operation affecting money, order state, occupancy, KOT state, or billing should be committed by Main POS.

Examples:

```text
Create Party
Create Order
Add Order Item
Cancel Item
Create KOT
Create Bill
Create Payment
Close Party
Close Table Session
```

Captains send commands.

Main POS validates and commits.

---

# 41. Concurrency

Multiple Captains can operate simultaneously.

Example:

```text
Captain A opens Table 12
Captain B opens Table 12
```

The Main POS must serialize critical operations.

Especially:

```text
Party creation
Occupancy calculation
Order modifications
Payment
Bill closing
```

Do not trust client-side occupancy calculations.

Example:

```text
Maximum occupancy = 6

Party A = 4

Captain A requests Party B = 2
Captain B requests Party C = 2
```

Only one transaction should succeed if capacity is exhausted.

---

# 42. Local Database

Recommended Flutter local database:

```text
Drift + SQLite
```

Do not use SharedPreferences for operational data.

Local DB should contain:

```text
Configuration
Orders
KOTs
Bills
Payments
Print Queue
Sync Queue
```

---

# 43. Sync Architecture

Main POS syncs to Supabase in the background.

Basic model:

```text
Local DB
    ↓
Sync Queue
    ↓
Sync Worker
    ↓
Supabase
```

Internet availability:

```text
Internet available
    ↓
Sync automatically

Internet unavailable
    ↓
Continue operating
    ↓
Queue changes
    ↓
Sync later
```

Never make the UI wait for Supabase.

---

# 44. Idempotency

Every locally-created entity must have a UUID.

Sync operations must be idempotent.

Example:

```text
Local Order ID:
7f5e9a...
```

If sync fails and retries:

```text
Attempt 1 → timeout
Attempt 2 → retry
Attempt 3 → success
```

It must NOT create three orders.

Use UUIDs and appropriate unique constraints/upsert behavior.

---

# 45. Sync Status

B Ops should eventually show sync status.

Example:

```text
Outlet: Bolgatty

Main POS
Status: Online

Last Sync:
27 Sep 2026 20:42

Pending:
0

Menu Version:
14

Menu Sync:
✓ Synced
```

If menu is waiting:

```text
Menu Sync:
● Pending
```

If failed:

```text
Menu Sync:
⚠ Failed
```

---

# 46. Menu Sync

B Ops is the configuration authority for menu.

Menu changes can be:

* Immediate
* Scheduled

Example:

```text
Menu Version 15

Scheduled:
Tomorrow 11:00 AM
```

Main POS receives/downloads the new menu and activates it according to schedule.

Do not replace the currently active local menu until the new menu is successfully downloaded and validated.

---

# 47. Configuration Sync

The following configuration must initially come from Supabase:

```text
Outlet
Menu
Categories
Products
Variants
Modifiers
Modifier Groups
Tables
Users
KOT Groups
Printers
Payment Methods
Settings
```

After initial sync, Main POS owns the local operational copy.

---

# 48. Historical Data

Current/active operational data should be local.

Older historical data can be fetched from Supabase.

Do not unnecessarily load years of orders into the Main POS local database.

---

# 49. Security

Never trust Captain devices.

Main POS must validate:

* Device registration
* User identity
* Outlet
* Permissions
* Order ownership/context
* Table/session state
* Payment operations

A Captain should not be able to manually call:

```text
/create-payment
```

without the appropriate permission.

---

# 50. RLS

Supabase RLS should protect outlet isolation.

A user associated with:

```text
Outlet A
```

must not automatically access:

```text
Outlet B
```

BPOS tables should use appropriate outlet-scoped policies.

However:

> Do not make the Captain app dependent on Supabase RLS for local operation.

Local authorization is handled by Main POS.

---

# 51. B Ops Integration

B Ops and BPOS share the same Supabase project.

B Ops should eventually provide management for:

```text
Outlets
Users
Roles
Menus
Categories
Products
Variants
Modifiers
Tables
Printers
KOT Groups
Payment Methods
Settings
```

B Ops should also display:

```text
Orders
Bills
Payments
KOT history
Sync status
```

Do not duplicate business data unnecessarily between BPOS and B Ops.

---

# 52. Flutter Architecture

Recommended repository structure:

```text
restaurant-pos/
│
├── apps/
│   ├── main_pos/
│   └── captain/
│
├── packages/
│   ├── core/
│   ├── models/
│   ├── database/
│   ├── networking/
│   ├── sync/
│   ├── auth/
│   ├── printing/
│   ├── menu/
│   ├── orders/
│   ├── billing/
│   └── inventory/
│
└── supabase/
    ├── migrations/
    ├── functions/
    └── seed/
```

Main POS and Captain should share models and protocol definitions.

---

# 53. Important Development Rule

Do NOT build two completely unrelated Flutter applications.

Shared business models/protocols should be reused.

Example:

```text
packages/models

Order
OrderItem
Product
Variant
Modifier
Table
Party
KOT
Bill
Payment
Printer
```

Both applications use these models.

---

# 54. Main POS vs Captain Responsibilities

## Main POS

```text
Local DB
Local API
WebSocket
mDNS
Order authority
Table authority
Party authority
Billing
Payments
Printing
Sync
Configuration
```

## Captain

```text
Login
Table browsing
Party creation
Order taking
Order viewing
Cancellation
Bill request
Bill viewing
Real-time updates
```

---

# 55. What NOT to Do

Do not:

* Make Captain directly write to Supabase during normal operation
* Make Internet mandatory for taking orders
* Store the POS IP permanently
* Let Captains directly control printers
* Store operational data only in memory
* Use SharedPreferences as the POS database
* Delete printed KOT items when cancelled
* Recalculate historical prices from the current menu
* Assume one printer per KOT group
* Assume one KOT per order
* Assume one party per table
* Assume one Captain owns a table/order
* Trust client-side occupancy calculations
* Make Supabase calls block restaurant operations
* Couple the new BPOS schema directly to unknown existing B Ops tables without inspection

---

# 56. Current Supabase Schema Progress

Already created:

```text
bpos
├── outlets
├── users
├── roles
├── permissions
├── role_permissions
├── outlet_users
├── pos_devices
├── captain_devices
├── payment_methods
├── outlet_settings
│
├── categories
├── kot_groups
│
├── menu_versions
├── products
├── product_variants
├── product_kot_groups
│
├── modifier_groups
├── modifiers
├── product_modifier_groups
└── variant_modifier_groups
```

Dummy outlet/menu data has also been created.

Dummy outlet:

```text
BOLGATTY
Bollgattea Food Court
```

---

# 57. Current Dummy Menu

```text
Grill
 ├── Alfaham
 │    ├── 1 Quarter ₹150
 │    ├── 1 Half ₹300
 │    └── 1 Full ₹550
 │
 └── Shawarma ₹120

Bread
 └── Porotta ₹25

Rice
 └── Chicken Fried Rice ₹180

Drinks
 └── Fresh Lime ₹60
```

KOT routing:

```text
Alfaham → Grill
Shawarma → Grill
Porotta → Bread
Chicken Fried Rice → Rice
Fresh Lime → Juice
```

Modifier examples:

```text
Sauce
 ├── Mayo +₹20
 ├── Chutney +₹10
 └── Garlic Sauce +₹20

Extras
 ├── Cheese +₹40
 └── Egg +₹20
```

---

# 58. Current Development Sequence

Do not jump randomly between features.

Recommended sequence:

```text
1. Core Supabase schema
2. Menu schema
3. Printer/KOT schema
4. Table/session/party schema
5. Order schema
6. Bill/payment schema
7. Sync schema
8. RLS
9. Main POS local database
10. Main POS local server
11. mDNS discovery
12. Captain pairing
13. Captain UI
14. Main POS UI
15. Printing
16. Supabase sync
17. B Ops integration
18. Testing
```

---

# 59. Engineering Philosophy

This is a restaurant POS, not a normal SaaS application.

The system must prioritize:

1. Local reliability
2. Transaction correctness
3. Printing reliability
4. Fast UI
5. Offline operation
6. Data integrity
7. Sync reliability
8. Cloud reporting

A restaurant should be able to continue taking orders and printing KOTs even when the Internet is completely unavailable.

---

# 60. When Making Architectural Decisions

When there is a choice between:

```text
Cloud-dependent
```

and:

```text
Local-first
```

prefer local-first for operational POS functionality.

When there is a choice between:

```text
Convenient but eventually consistent
```

and:

```text
Atomic local transaction
```

prefer the atomic local transaction for:

* Tables
* Parties
* Orders
* KOTs
* Bills
* Payments

When there is a choice between:

```text
Deleting history
```

and:

```text
Recording a correction/cancellation
```

prefer recording the correction.

Historical restaurant transactions must remain auditable.

---

# 61. Current Next Task

The next Supabase schema component should be:

```text
PRINTERS
KOT GROUP ↔ PRINTER
PRINT QUEUE
```

It must support:

```text
Multiple printers
LAN printers
Bluetooth printers
Multiple KOT groups per printer
Multiple printers per KOT group
Immediate printing
Print queue
Retry
Print failure
Bill printing
KOT cancellation printing
```

After that, build:

```text
Tables
→ Table Sessions
→ Parties
→ Orders
→ KOTs
→ Bills
→ Payments
→ Sync
```

Do not start implementing the Captain UI before these core data/protocol contracts are defined.
