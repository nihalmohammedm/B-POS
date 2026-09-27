# Bistro 21 — POS + Captain (Flutter)

A single Flutter app with two entry points on the launcher:

- **Main POS** (tablet / desktop): New order · Tables · Orders · Kitchen display
- **Captain app** (mobile): Dine-in tables with sharing, takeaway, typing-first item search, KOT, bill

All screens share one in-memory `Store` (ChangeNotifier), so a KOT sent from the Captain app shows up
immediately on the POS Orders and Kitchen screens, a bill printed by a captain locks the table on the POS, etc.

## Run

```bash
cd flutter
flutter create .          # generates android/ios/web/desktop folders (keeps lib/ and pubspec.yaml)
flutter pub get
flutter run -d chrome     # or any device; try a tablet emulator for the POS and a phone for Captain
```

Requires Flutter 3.22+ (Dart 3.3+). No third-party packages.

## Structure

```
lib/
  main.dart                 launcher (POS / Captain)
  theme.dart                colours, category palette, ThemeData
  models.dart               MenuItem, OrderLine, Order, Kot, Party, TableModel, Payment
  data.dart                 seed menu + floor plan
  store.dart                all business logic + seed orders
  widgets/common.dart       StoreScope, INR formatting, pills, segmented, toggle, stepper, buttons, sheets, toast
  widgets/receipt.dart      80mm KOT / Bill (GST) receipt + print preview
  pos/pos_shell.dart        POS header + tab navigation
  pos/order_taking.dart     categories, item cards, long-press manage, cart, order types, Confirm & Print KOT
  pos/dialogs.dart          customise (variants/add-ons), edit note, item & category on/off + stock, table picker
  pos/payment.dart          split payment (Cash/UPI, cash tendered + change), settle / print-bill flows
  pos/tables_screen.dart    floor plan, table sharing (any split up to seat count), details, bill, settle, reopen
  pos/orders_screen.dart    ongoing orders (Dine in / Takeaway / Delivery) with stage actions
  pos/kitchen_screen.dart   KDS tickets with timers, item bump, ready / served
  captain/captain.dart      Captain home, seat / billing sheets, typing order screen, cart, bill
```

## Notes

- Currency INR with Indian digit grouping; tax 5% shown as CGST 2.5% + SGST 2.5%; totals rounded to the rupee.
- Printing is simulated (preview + "sent to printer" toast). Hook `showPrintPreview`'s result to your ESC/POS driver.
- Replace `Store` persistence with your API; every mutation goes through a `Store` method and calls `notifyListeners()`.
