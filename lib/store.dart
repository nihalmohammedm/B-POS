import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backoffice_api.dart';
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
  List<String> quickNotes = ['No onions', 'Extra spicy', 'Less oil', 'Pack separately'];
  int _orderSeq = 0, _kotSeq = 0, _billSeq = 0, _taSeq = 0, _printerSeq = 0;

  void touch() => notifyListeners();

  void addQuickNote(String note) {
    final v = note.trim();
    if (v.isEmpty || quickNotes.contains(v)) return;
    quickNotes.add(v);
    notifyListeners();
  }

  void removeQuickNote(String note) {
    quickNotes.remove(note);
    notifyListeners();
  }

  // ---------- debounced operational save ----------
  Timer? _saveDebounce;
  @override
  void notifyListeners() {
    super.notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _saveOperational);
  }

  // ---------- local persistence ----------
  // Keeps a synced menu/printer setup across app restarts, so re-opening the APK
  // doesn't fall back to the bundled demo data and force a re-sync every time.
  static const _kMenu = 'menu', _kCategories = 'categories', _kLastSync = 'lastMenuSync';
  static const _kPrinters = 'printers';
  static const _kTables = 'tables';
  static const _kUrl = 'backofficeUrl', _kKey = 'backofficeKey', _kOutlet = 'backofficeOutletCode';
  static const _kOutletName = 'outletName', _kOutletAddress = 'outletAddress', _kOutletPhone = 'outletPhone';
  static const _kOrders = 'orders', _kKots = 'kots', _kHistory = 'history';
  static const _kItemOff = 'itemOff', _kCatOff = 'catOff', _kStock = 'stock';
  static const _kQuickNotes = 'quickNotes', _kCounters = 'counters';

  Future<void> _loadPersisted() async {
    final sp = await SharedPreferences.getInstance();

    backofficeUrl = sp.getString(_kUrl) ?? backofficeUrl;
    backofficeKey = sp.getString(_kKey) ?? backofficeKey;
    backofficeOutletCode = sp.getString(_kOutlet) ?? backofficeOutletCode;
    outletName = sp.getString(_kOutletName) ?? outletName;
    outletAddress = sp.getString(_kOutletAddress) ?? outletAddress;
    outletPhone = sp.getString(_kOutletPhone) ?? outletPhone;

    final menuJson = sp.getString(_kMenu);
    final cats = sp.getStringList(_kCategories);
    if (menuJson != null && cats != null) {
      final items = (jsonDecode(menuJson) as List).map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
      menu
        ..clear()
        ..addAll(items);
      categories = cats;
    }
    final syncStr = sp.getString(_kLastSync);
    if (syncStr != null) lastMenuSync = DateTime.tryParse(syncStr);

    final printersJson = sp.getString(_kPrinters);
    if (printersJson != null) {
      final saved = (jsonDecode(printersJson) as List).map((e) => PosPrinter.fromJson(e as Map<String, dynamic>)).toList();
      printers
        ..clear()
        ..addAll(saved);
    }

    final tablesJson = sp.getString(_kTables);
    if (tablesJson != null) {
      final saved = (jsonDecode(tablesJson) as List).map((e) => TableModel.fromJson(e as Map<String, dynamic>)).toList();
      tables
        ..clear()
        ..addAll(saved);
    }

    final ordersJson = sp.getString(_kOrders);
    if (ordersJson != null) {
      orders.addAll((jsonDecode(ordersJson) as List).map((e) => Order.fromJson(e as Map<String, dynamic>)));
    }
    final kotsJson = sp.getString(_kKots);
    if (kotsJson != null) {
      kots.addAll((jsonDecode(kotsJson) as List).map((e) => Kot.fromJson(e as Map<String, dynamic>)));
    }
    final historyJson = sp.getString(_kHistory);
    if (historyJson != null) {
      history.addAll((jsonDecode(historyJson) as List).map((e) => Order.fromJson(e as Map<String, dynamic>)));
    }
    final itemOffList = sp.getStringList(_kItemOff);
    if (itemOffList != null) itemOff.addAll(itemOffList);
    final catOffList = sp.getStringList(_kCatOff);
    if (catOffList != null) catOff.addAll(catOffList);
    final stockJson = sp.getString(_kStock);
    if (stockJson != null) {
      (jsonDecode(stockJson) as Map<String, dynamic>).forEach((k, v) => stock[k] = v as int);
    }
    final savedNotes = sp.getStringList(_kQuickNotes);
    if (savedNotes != null) quickNotes = savedNotes;
    final countersJson = sp.getString(_kCounters);
    if (countersJson != null) {
      final c = jsonDecode(countersJson) as Map<String, dynamic>;
      _orderSeq = c['orderSeq'] as int? ?? _orderSeq;
      _kotSeq = c['kotSeq'] as int? ?? _kotSeq;
      _billSeq = c['billSeq'] as int? ?? _billSeq;
      _taSeq = c['taSeq'] as int? ?? _taSeq;
    }
    notifyListeners();

    // First-ever launch (nothing cached yet): pull the real menu straight away instead
    // of sitting empty until someone finds Settings.
    if (menuJson == null) {
      try {
        await syncMenu();
      } catch (_) {
        // Stays empty with lastSyncError set; Settings surfaces it for a manual retry.
      }
    }
  }

  Future<void> _saveMenu() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kMenu, jsonEncode(menu.map((m) => m.toJson()).toList()));
    await sp.setStringList(_kCategories, categories);
    if (lastMenuSync != null) await sp.setString(_kLastSync, lastMenuSync!.toIso8601String());
    await sp.setString(_kOutletName, outletName);
    await sp.setString(_kOutletAddress, outletAddress);
    await sp.setString(_kOutletPhone, outletPhone);
  }

  Future<void> _savePrinters() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPrinters, jsonEncode(printers.map((p) => p.toJson()).toList()));
  }

  Future<void> _saveTables() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kTables, jsonEncode(tables.map((t) => t.toJson()).toList()));
  }

  /// Everything that changes during a shift — active/settled orders, KOTs, seated
  /// parties, availability toggles, stock, quick notes, sequence counters — saved as
  /// one debounced bundle (see the `notifyListeners` override) so nothing needs its
  /// own explicit save call at every call site.
  Future<void> _saveOperational() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kOrders, jsonEncode(orders.map((o) => o.toJson()).toList()));
    await sp.setString(_kKots, jsonEncode(kots.map((k) => k.toJson()).toList()));
    await sp.setString(_kHistory, jsonEncode(history.map((o) => o.toJson()).toList()));
    await sp.setString(_kTables, jsonEncode(tables.map((t) => t.toJson()).toList()));
    await sp.setStringList(_kItemOff, itemOff.toList());
    await sp.setStringList(_kCatOff, catOff.toList());
    await sp.setString(_kStock, jsonEncode(stock));
    await sp.setStringList(_kQuickNotes, quickNotes);
    await sp.setString(_kCounters,
        jsonEncode({'orderSeq': _orderSeq, 'kotSeq': _kotSeq, 'billSeq': _billSeq, 'taSeq': _taSeq}));
  }

  Future<void> _saveBackofficeConfig() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUrl, backofficeUrl);
    await sp.setString(_kKey, backofficeKey);
    await sp.setString(_kOutlet, backofficeOutletCode);
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

  /// Pulls the active menu for [backofficeOutletCode] from the backoffice (a self-hosted
  /// Supabase/PostgREST instance, `bpos` schema) and replaces the local menu with it.
  Future<MenuSyncResult> syncMenu() async {
    syncingMenu = true;
    lastSyncError = null;
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
