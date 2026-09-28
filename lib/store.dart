import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'backoffice_api.dart';
import 'db/app_database.dart';
import 'models.dart';

class Store extends ChangeNotifier {
  Store() {
    _loadPersisted();
  }

  List<String> categories = [];
  List<String> get floors => {for (final t in tables) t.floor}.toList()..sort();

  final List<MenuItem> menu = [];
  final Set<String> itemOff = {};
  final Set<String> catOff = {};
  final Map<String, int> stock = {};
  final List<TableModel> tables = [];
  final List<Order> orders = [];
  final List<Order> history = [];
  final List<Kot> kots = [];
  final List<PosPrinter> printers = [];
  int _orderSeq = 0, _kotSeq = 0, _billSeq = 0, _taSeq = 0, _printerSeq = 0;

  void touch() => notifyListeners();

  // ---------- debounced operational save ----------
  Timer? _saveDebounce;
  @override
  void notifyListeners() {
    super.notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _saveOperational);
  }

  // ---------- local persistence (Drift/SQLite) ----------
  // A real local database, not just a bag of shared_preferences strings — every
  // collection is its own table (one row per entity, id + JSON payload, see
  // lib/db/app_database.dart), so a single changed order no longer means
  // re-serializing every order. Keeps a synced menu/printer/order setup across
  // app restarts, so re-opening the app doesn't fall back to empty state.
  final AppDatabase _db = AppDatabase();

  Future<String?> _getSetting(String key) async {
    final row = await (_db.select(_db.settingsRows)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setSetting(String key, String value) async {
    await _db.into(_db.settingsRows).insertOnConflictUpdate(SettingsRowsCompanion.insert(key: key, value: value));
  }

  Future<void> _loadPersisted() async {
    backofficeUrl = await _getSetting('backofficeUrl') ?? backofficeUrl;
    backofficeKey = await _getSetting('backofficeKey') ?? backofficeKey;
    backofficeOutletCode = await _getSetting('backofficeOutletCode') ?? backofficeOutletCode;
    outletName = await _getSetting('outletName') ?? outletName;
    outletAddress = await _getSetting('outletAddress') ?? outletAddress;
    outletPhone = await _getSetting('outletPhone') ?? outletPhone;

    final menuRows = await _db.select(_db.menuItemRows).get();
    final catRows = await (_db.select(_db.categoryRows)
          ..orderBy([(t) => OrderingTerm(expression: t.displayOrder)]))
        .get();
    final hasMenuCache = menuRows.isNotEmpty;
    if (hasMenuCache) {
      menu
        ..clear()
        ..addAll(menuRows.map((r) => MenuItem.fromJson(jsonDecode(r.json) as Map<String, dynamic>)));
      categories = catRows.map((r) => r.name).toList();
    }
    final syncStr = await _getSetting('lastMenuSync');
    if (syncStr != null) lastMenuSync = DateTime.tryParse(syncStr);

    final printerRows = await _db.select(_db.printerRows).get();
    printers
      ..clear()
      ..addAll(printerRows.map((r) => PosPrinter.fromJson(jsonDecode(r.json) as Map<String, dynamic>)));

    final tableRows = await _db.select(_db.diningTableRows).get();
    tables
      ..clear()
      ..addAll(tableRows.map((r) => TableModel.fromJson(jsonDecode(r.json) as Map<String, dynamic>)));

    final orderRows = await _db.select(_db.orderRows).get();
    orders.addAll(orderRows.map((r) => Order.fromJson(jsonDecode(r.json) as Map<String, dynamic>)));

    final kotRows = await _db.select(_db.kotRows).get();
    kots.addAll(kotRows.map((r) => Kot.fromJson(jsonDecode(r.json) as Map<String, dynamic>)));

    final historyRows = await _db.select(_db.historyRows).get();
    history.addAll(historyRows.map((r) => Order.fromJson(jsonDecode(r.json) as Map<String, dynamic>)));

    final itemOffRows = await _db.select(_db.itemOffRows).get();
    itemOff.addAll(itemOffRows.map((r) => r.id));
    final catOffRows = await _db.select(_db.catOffRows).get();
    catOff.addAll(catOffRows.map((r) => r.id));

    final stockRows = await _db.select(_db.stockRows).get();
    for (final r in stockRows) {
      stock[r.itemId] = r.qty;
    }

    _orderSeq = int.tryParse(await _getSetting('orderSeq') ?? '') ?? _orderSeq;
    _kotSeq = int.tryParse(await _getSetting('kotSeq') ?? '') ?? _kotSeq;
    _billSeq = int.tryParse(await _getSetting('billSeq') ?? '') ?? _billSeq;
    _taSeq = int.tryParse(await _getSetting('taSeq') ?? '') ?? _taSeq;
    notifyListeners();

    // First-ever launch (nothing cached yet): pull the real menu straight away instead
    // of sitting empty until someone finds Settings.
    if (!hasMenuCache) {
      try {
        await syncMenu();
      } catch (_) {
        // Stays empty with lastSyncError set; Settings surfaces it for a manual retry.
      }
    }

    _wireBackgroundSync();
  }

  Future<void> _saveMenu() async {
    await _db.batch((b) {
      b.deleteAll(_db.menuItemRows);
      b.insertAll(_db.menuItemRows,
          menu.map((m) => MenuItemRowsCompanion.insert(id: m.id, json: jsonEncode(m.toJson()))));
      b.deleteAll(_db.categoryRows);
      b.insertAll(_db.categoryRows, [
        for (var i = 0; i < categories.length; i++) CategoryRowsCompanion.insert(name: categories[i], displayOrder: i),
      ]);
    });
    if (lastMenuSync != null) await _setSetting('lastMenuSync', lastMenuSync!.toIso8601String());
    await _setSetting('outletName', outletName);
    await _setSetting('outletAddress', outletAddress);
    await _setSetting('outletPhone', outletPhone);
  }

  Future<void> _savePrinters() async {
    await _db.batch((b) {
      b.deleteAll(_db.printerRows);
      b.insertAll(
          _db.printerRows, printers.map((p) => PrinterRowsCompanion.insert(id: p.id, json: jsonEncode(p.toJson()))));
    });
  }

  Future<void> _saveTables() async {
    await _db.batch((b) {
      b.deleteAll(_db.diningTableRows);
      b.insertAll(_db.diningTableRows,
          tables.map((t) => DiningTableRowsCompanion.insert(id: t.id, json: jsonEncode(t.toJson()))));
    });
  }

  /// Everything that changes during a shift — active/settled orders, KOTs, seated
  /// parties, availability toggles, stock, sequence counters — saved as one
  /// debounced bundle (see the `notifyListeners` override) so nothing needs its
  /// own explicit save call at every call site.
  Future<void> _saveOperational() async {
    await _db.batch((b) {
      b.deleteAll(_db.orderRows);
      b.insertAll(_db.orderRows,
          orders.map((o) => OrderRowsCompanion.insert(id: Value(o.id), json: jsonEncode(o.toJson()))));

      b.deleteAll(_db.kotRows);
      b.insertAll(
          _db.kotRows, kots.map((k) => KotRowsCompanion.insert(no: Value(k.no), json: jsonEncode(k.toJson()))));

      b.deleteAll(_db.historyRows);
      b.insertAll(_db.historyRows,
          history.map((o) => HistoryRowsCompanion.insert(id: Value(o.id), json: jsonEncode(o.toJson()))));

      b.deleteAll(_db.diningTableRows);
      b.insertAll(_db.diningTableRows,
          tables.map((t) => DiningTableRowsCompanion.insert(id: t.id, json: jsonEncode(t.toJson()))));

      b.deleteAll(_db.itemOffRows);
      b.insertAll(_db.itemOffRows, itemOff.map((id) => ItemOffRowsCompanion.insert(id: id)));

      b.deleteAll(_db.catOffRows);
      b.insertAll(_db.catOffRows, catOff.map((id) => CatOffRowsCompanion.insert(id: id)));

      b.deleteAll(_db.stockRows);
      b.insertAll(_db.stockRows, stock.entries.map((e) => StockRowsCompanion.insert(itemId: e.key, qty: e.value)));
    });
    await _setSetting('orderSeq', '$_orderSeq');
    await _setSetting('kotSeq', '$_kotSeq');
    await _setSetting('billSeq', '$_billSeq');
    await _setSetting('taSeq', '$_taSeq');
  }

  Future<void> _saveBackofficeConfig() async {
    await _setSetting('backofficeUrl', backofficeUrl);
    await _setSetting('backofficeKey', backofficeKey);
    await _setSetting('backofficeOutletCode', backofficeOutletCode);
  }

  // ---------- background sync ----------
  bool isOnline = true;
  bool autoSyncEnabled = true;
  DateTime? lastSyncAttempt;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicSyncTimer;

  void _wireBackgroundSync() {
    Connectivity().checkConnectivity().then((r) => _applyConnectivity(r, triggerSync: false));
    _connectivitySub = Connectivity().onConnectivityChanged.listen(_applyConnectivity);
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 15), (_) => _backgroundSync());
  }

  void _applyConnectivity(List<ConnectivityResult> result, {bool triggerSync = true}) {
    final wasOnline = isOnline;
    isOnline = result.any((r) => r != ConnectivityResult.none);
    notifyListeners();
    if (triggerSync && isOnline && !wasOnline) _backgroundSync();
  }

  Future<void> _backgroundSync() async {
    if (!autoSyncEnabled || !isOnline || syncingMenu) return;
    try {
      await syncMenu();
    } catch (_) {
      // lastSyncError is already set by syncMenu; Settings surfaces it.
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _periodicSyncTimer?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }

  // ---------- printers ----------
  List<PosPrinter> get billPrinters => printers.where((p) => p.forBill).toList();
  List<PosPrinter> get kotPrinters => printers.where((p) => p.forKot).toList();

  String nextPrinterId() => 'pr${++_printerSeq}';

  void addPrinter(PosPrinter p) {
    printers.add(p);
    notifyListeners();
    _savePrinters();
  }

  void updatePrinter(PosPrinter p) {
    final i = printers.indexWhere((x) => x.id == p.id);
    if (i != -1) printers[i] = p;
    notifyListeners();
    _savePrinters();
  }

  void removePrinter(String id) {
    printers.removeWhere((p) => p.id == id);
    notifyListeners();
    _savePrinters();
  }

  /// Sends a short test ticket to [p]. Stands in for real ESC/POS I/O over
  /// USB / Bluetooth SPP / a raw LAN socket — the transport [p.conn] picks between.
  Future<bool> testPrint(PosPrinter p) async {
    await Future.delayed(const Duration(milliseconds: 900));
    p.lastTestAt = DateTime.now();
    p.lastTestOk = true;
    notifyListeners();
    _savePrinters();
    return true;
  }

  // ---------- backoffice sync ----------
  String backofficeUrl = 'https://v2database.bollgattea.com';
  String backofficeKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3ODQ0NTc0ODQsImV4cCI6MTg5MzQ1NjAwMCwicm9sZSI6ImFub24iLCJpc3MiOiJzdXBhYmFzZSJ9.WXyhtM_v3dP2_P1BwNmVdEXHwhfQ2fHanofZ3Prn_BQ';
  String backofficeOutletCode = 'BOLGATTY';
  String outletName = '', outletAddress = '', outletPhone = '';
  DateTime? lastMenuSync;
  bool syncingMenu = false;
  MenuSyncResult? lastSyncResult;
  String? lastSyncError;

  void setBackofficeConfig({String? url, String? key, String? outletCode}) {
    if (url != null) backofficeUrl = url;
    if (key != null) backofficeKey = key;
    if (outletCode != null) backofficeOutletCode = outletCode;
    notifyListeners();
    _saveBackofficeConfig();
  }

  void setAutoSync(bool on) {
    autoSyncEnabled = on;
    notifyListeners();
  }

  /// Pulls the active menu for [backofficeOutletCode] from the backoffice (a self-hosted
  /// Supabase/PostgREST instance, `bpos` schema) and replaces the local menu with it.
  Future<MenuSyncResult> syncMenu() async {
    syncingMenu = true;
    lastSyncError = null;
    lastSyncAttempt = DateTime.now();
    notifyListeners();
    try {
      final result =
          await BackofficeApi(baseUrl: backofficeUrl, apiKey: backofficeKey).fetchMenu(outletCode: backofficeOutletCode);
      int added = 0, updated = 0;
      final seenIds = <String>{};
      for (final m in result.items) {
        seenIds.add(m.id);
        final i = menu.indexWhere((x) => x.id == m.id);
        if (i == -1) {
          menu.add(m);
          added++;
        } else if (menu[i] != m) {
          menu[i] = m;
          updated++;
        }
      }
      final removed = menu.where((m) => !seenIds.contains(m.id)).length;
      menu.removeWhere((m) => !seenIds.contains(m.id));
      if (result.categories.isNotEmpty) categories = result.categories;
      if (result.outlet.name.isNotEmpty) outletName = result.outlet.name;
      outletAddress = result.outlet.address;
      outletPhone = result.outlet.phone;

      // Merge tables in place so a table with a live party mid-sync keeps its seated guests.
      final seenTableIds = <String>{};
      for (final t in result.tables) {
        seenTableIds.add(t.id);
        final i = tables.indexWhere((x) => x.id == t.id);
        if (i == -1) {
          tables.add(t);
        } else {
          tables[i]
            ..floor = t.floor
            ..seats = t.seats
            ..w = t.w
            ..h = t.h;
        }
      }
      tables.removeWhere((t) => !seenTableIds.contains(t.id) && t.parties.isEmpty);

      final r = MenuSyncResult(added: added, updated: updated, removed: removed, at: DateTime.now());
      lastMenuSync = r.at;
      lastSyncResult = r;
      await _saveMenu();
      await _saveTables();
      return r;
    } catch (e) {
      lastSyncError = e is BackofficeException ? e.message : e.toString();
      rethrow;
    } finally {
      syncingMenu = false;
      notifyListeners();
    }
  }

  // ---------- menu ----------
  MenuItem item(String id) => menu.firstWhere((m) => m.id == id);
  List<MenuItem> itemsIn(String cat) => menu.where((m) => m.cat == cat).toList();

  String? offReason(MenuItem m) {
    if (catOff.contains(m.cat)) return 'Category off';
    if (itemOff.contains(m.id)) return 'Turned off';
    if (stock[m.id] == 0) return 'Sold out';
    return null;
  }

  void setItemOn(String id, bool on) {
    on ? itemOff.remove(id) : itemOff.add(id);
    notifyListeners();
  }

  void setCatOn(String c, bool on) {
    on ? catOff.remove(c) : catOff.add(c);
    notifyListeners();
  }

  void allItemsOn(String c) {
    for (final m in itemsIn(c)) {
      itemOff.remove(m.id);
    }
    notifyListeners();
  }

  void setStock(String id, int? v) {
    if (v == null) {
      stock.remove(id);
    } else {
      stock[id] = math.max(0, v);
    }
    notifyListeners();
  }

  // ---------- tables & parties ----------
  TableModel table(String id) => tables.firstWhere((t) => t.id == id);
  List<TableModel> tablesOn(String floor) => tables.where((t) => t.floor == floor).toList();

  String partyLabel(TableModel t, String key) =>
      (t.parties.length == 1 && t.parties.first.key == key && t.parties.first.pax == t.seats) ? t.id : '${t.id}·$key';

  Party? party(String tableId, String key) {
    for (final p in table(tableId).parties) {
      if (p.key == key) return p;
    }
    return null;
  }

  Order? orderById(int id) {
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  Order? orderOfParty(TableModel t, Party p) => p.orderId == null ? null : orderById(p.orderId!);

  Party seatParty(TableModel t, int pax) {
    const letters = 'ABCDEFGHIJKL';
    final k = letters.split('').firstWhere((l) => !t.parties.any((p) => p.key == l));
    final p = Party(k, math.max(1, math.min(pax, t.free)));
    t.parties.add(p);
    notifyListeners();
    return p;
  }

  bool freeParty(TableModel t, Party p) {
    final o = orderOfParty(t, p);
    if (o != null && o.lines.isNotEmpty) return false;
    if (o != null) orders.remove(o);
    t.parties.remove(p);
    notifyListeners();
    return true;
  }

  bool setPax(TableModel t, Party p, int pax) {
    if (pax < 1 || pax - p.pax > t.free) return false;
    p.pax = pax;
    orderOfParty(t, p)?.pax = pax;
    notifyListeners();
    return true;
  }

  Order ensurePartyOrder(TableModel t, Party p, {String server = ''}) {
    final ex = orderOfParty(t, p);
    if (ex != null) return ex;
    final o = Order(
        id: ++_orderSeq, type: OrderType.dineIn, tableId: t.id, partyKey: p.key, pax: p.pax, server: server, at: p.seatedAt);
    p.orderId = o.id;
    orders.add(o);
    notifyListeners();
    return o;
  }

  // ---------- orders ----------
  Order draft(OrderType type, {String server = ''}) => Order(id: 0, type: type, server: server);
  String get nextTaToken => 'TA-${_taSeq + 1}';
  int get nextKotNo => _kotSeq + 1;
  String previewBillNo(Order o) => o.billNo ?? 'B${_billSeq + 1}';

  String labelOf(Order o) {
    if (o.type == OrderType.dineIn) return partyLabel(table(o.tableId!), o.partyKey!);
    return o.token.isEmpty ? (o.type == OrderType.takeaway ? nextTaToken : 'New') : o.token;
  }

  String titleOf(Order o) =>
      o.type == OrderType.dineIn ? 'Table ${labelOf(o)}' : (o.customer.isEmpty ? 'Walk-in' : o.customer);

  OrderStage stageOf(Order o) {
    if (o.billed) return OrderStage.billing;
    if (o.dispatched) return OrderStage.outForDelivery;
    if (o.lines.isEmpty) return OrderStage.placed;
    if (o.lines.every((l) => l.state == LineState.served)) {
      return o.type == OrderType.dineIn ? OrderStage.served : OrderStage.ready;
    }
    if (o.lines.every((l) => l.state.index >= LineState.ready.index)) return OrderStage.ready;
    return OrderStage.preparing;
  }

  List<Order> get activeOrders => orders.where((o) => o.lines.isNotEmpty).toList()..sort((a, b) => a.at.compareTo(b.at));

  Kot sendKot(Order o, List<OrderLine> lines) {
    if (!orders.contains(o)) {
      o.id = ++_orderSeq;
      if (o.type == OrderType.takeaway) {
        o.token = 'TA-${++_taSeq}';
      } else if (o.type == OrderType.delivery) {
        o.token = '#${o.id}';
      }
      orders.add(o);
    }
    final k = Kot(++_kotSeq, o.id, DateTime.now(), []);
    for (final l in lines) {
      final c = l.copy()
        ..state = LineState.queued
        ..kotNo = k.no;
      k.lines.add(c);
      o.lines.add(c);
      final s = stock[l.item.id];
      if (s != null) stock[l.item.id] = math.max(0, s - l.qty);
    }
    kots.add(k);
    notifyListeners();
    return k;
  }

  Kot? lastKot(Order o) {
    Kot? r;
    for (final k in kots) {
      if (k.orderId == o.id) r = k;
    }
    return r;
  }

  String assignBillNo(Order o) => o.billNo ??= 'B${++_billSeq}';

  String printBill(Order o) {
    o.billed = true;
    final no = assignBillNo(o);
    notifyListeners();
    return no;
  }

  String? reopen(Order o) {
    final v = o.billNo;
    o.billed = false;
    o.billNo = null;
    notifyListeners();
    return v;
  }

  void markServed(Order o) {
    for (final l in o.lines) {
      l.state = LineState.served;
    }
    notifyListeners();
  }

  void markReady(Order o) {
    for (final l in o.lines) {
      if (l.state.index < LineState.ready.index) l.state = LineState.ready;
    }
    notifyListeners();
  }

  void dispatch(Order o) {
    o.dispatched = true;
    for (final l in o.lines) {
      l.state = LineState.served;
    }
    notifyListeners();
  }

  void settle(Order o, {List<Payment> payments = const []}) {
    assignBillNo(o);
    o.payments.addAll(payments);
    orders.remove(o);
    kots.removeWhere((k) => k.orderId == o.id);
    if (o.type == OrderType.dineIn) table(o.tableId!).parties.removeWhere((p) => p.orderId == o.id);
    history.add(o);
    notifyListeners();
  }

  bool canCancel(Order o) => !o.billed && o.lines.every((l) => l.state == LineState.queued);

  bool cancel(Order o) {
    if (!canCancel(o)) return false;
    orders.remove(o);
    kots.removeWhere((k) => k.orderId == o.id);
    if (o.type == OrderType.dineIn) table(o.tableId!).parties.removeWhere((p) => p.orderId == o.id);
    notifyListeners();
    return true;
  }

  // ---------- kitchen ----------
  List<Kot> get activeKots =>
      kots.where((k) => orderById(k.orderId) != null && k.stage != KotStage.done).toList()..sort((a, b) => a.at.compareTo(b.at));

  void startKot(Kot k) {
    for (final l in k.lines) {
      if (l.state == LineState.queued) l.state = LineState.preparing;
    }
    notifyListeners();
  }

  void toggleLine(OrderLine l) {
    l.state = l.state.index >= LineState.ready.index ? LineState.preparing : LineState.ready;
    notifyListeners();
  }

  void readyKot(Kot k) {
    for (final l in k.lines) {
      if (l.state.index < LineState.ready.index) l.state = LineState.ready;
    }
    notifyListeners();
  }

  void bumpKot(Kot k) {
    for (final l in k.lines) {
      l.state = LineState.served;
    }
    notifyListeners();
  }

  void recallKot(Kot k) {
    for (final l in k.lines) {
      l.state = LineState.preparing;
    }
    notifyListeners();
  }
}
