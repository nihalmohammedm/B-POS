import 'package:drift/drift.dart';

import 'connection/connection.dart' as conn;

part 'app_database.g.dart';

/// Every collection is stored as one row per entity, keyed by id, with the
/// full object as a JSON payload — reusing the `toJson`/`fromJson` already
/// on every model in `lib/models.dart`. This isn't a normalized relational
/// schema; nothing in the app does SQL-level filtering today (it's all
/// in-memory Dart list filtering via [Store]), so there's no benefit to
/// splitting these into joined tables, and doing so would be a much bigger,
/// riskier rewrite for no behavior change. What this buys over the previous
/// shared_preferences approach is real per-row CRUD — updating one order no
/// longer means re-serializing every order.
class MenuItemRows extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class CategoryRows extends Table {
  TextColumn get name => text()();
  IntColumn get displayOrder => integer()();
  @override
  Set<Column> get primaryKey => {name};
}

/// Dining tables (the restaurant floor layout) — named to avoid clashing
/// with both Drift's own [Table] and the app's [TableModel].
class DiningTableRows extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class PrinterRows extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class OrderRows extends Table {
  IntColumn get id => integer()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class KotRows extends Table {
  IntColumn get no => integer()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {no};
}

/// Settled/cancelled orders, archived instead of discarded. Same row shape
/// as [OrderRows].
class HistoryRows extends Table {
  IntColumn get id => integer()();
  TextColumn get json => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class StockRows extends Table {
  TextColumn get itemId => text()();
  IntColumn get qty => integer()();
  @override
  Set<Column> get primaryKey => {itemId};
}

/// Existence of a row = "turned off". No payload needed.
class ItemOffRows extends Table {
  TextColumn get id => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class CatOffRows extends Table {
  TextColumn get id => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Scalar config: backoffice connection, outlet info, last-sync timestamp,
/// sequence counters — anything that used to be a single shared_preferences
/// key/value pair.
class SettingsRows extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

/// Settled orders waiting to be pushed to Supabase (background bill sync).
/// Pure local bookkeeping — this table is never itself synced. Every remote
/// row the push creates uses an id derived deterministically from [orderId]
/// (see lib/sync/bill_sync_api.dart), so a retry after a partial failure is
/// naturally idempotent without needing to record what already landed.
class PendingBillSyncRows extends Table {
  IntColumn get orderId => integer()();
  /// pending | synced | failed
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  @override
  Set<Column> get primaryKey => {orderId};
}

@DriftDatabase(tables: [
  MenuItemRows,
  CategoryRows,
  DiningTableRows,
  PrinterRows,
  OrderRows,
  KotRows,
  HistoryRows,
  StockRows,
  ItemOffRows,
  CatOffRows,
  SettingsRows,
  PendingBillSyncRows,
])
class AppDatabase extends _$AppDatabase {
  /// [name] picks the database file: the POS and a captain mirror on the same
  /// computer must not share one.
  AppDatabase({String name = 'bistro_pos'}) : super(conn.openConnection(name: name));
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(pendingBillSyncRows);
        },
      );
}
