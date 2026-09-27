import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backoffice_api.dart';
import 'data.dart';
import 'models.dart';

class Store extends ChangeNotifier {
  Store() {
    _seed();
    _loadPersisted();
  }

  List<String> categories = ['Grill', 'Starters', 'Mains', 'Pizza', 'Burgers', 'Desserts', 'Beverages'];
  static const floors = ['Main hall', 'Patio', 'Rooftop'];

  final List<MenuItem> menu = List.of(seedMenu);
  final Set<String> itemOff = {'m2'};
  final Set<String> catOff = {};
  final Map<String, int> stock = {'g1': 11, 'g3': 4, 'd1': 6, 'v3': 24};
  final List<TableModel> tables = seedTables();
  final List<Order> orders = [];
  final List<Kot> kots = [];
  final List<PosPrinter> printers = seedPrinters();
  int _orderSeq = 1016, _kotSeq = 1016, _billSeq = 2416, _taSeq = 16, _printerSeq = 100;

  void touch() => notifyListeners();

  // ---------- local persistence ----------
  // Keeps a synced menu/printer setup across app restarts, so re-opening the APK
  // doesn't fall back to the bundled demo data and force a re-sync every time.
  static const _kMenu = 'menu', _kCategories = 'categories', _kLastSync = 'lastMenuSync';
  static const _kPrinters = 'printers';
  static const _kUrl = 'backofficeUrl', _kKey = 'backofficeKey', _kOutlet = 'backofficeOutletCode';

  Future<void> _loadPersisted() async {
    final sp = await SharedPreferences.getInstance();

    backofficeUrl = sp.getString(_kUrl) ?? backofficeUrl;
    backofficeKey = sp.getString(_kKey) ?? backofficeKey;
    backofficeOutletCode = sp.getString(_kOutlet) ?? backofficeOutletCode;

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
    notifyListeners();
  }

  Future<void> _saveMenu() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kMenu, jsonEncode(menu.map((m) => m.toJson()).toList()));
    await sp.setStringList(_kCategories, categories);
    if (lastMenuSync != null) await sp.setString(_kLastSync, lastMenuSync!.toIso8601String());
  }

  Future<void> _savePrinters() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPrinters, jsonEncode(printers.map((p) => p.toJson()).toList()));
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
  }

  void updatePrinter(PosPrinter p) {
    final i = printers.indexWhere((x) => x.id == p.id);
    if (i != -1) printers[i] = p;
    notifyListeners();
  }

  void removePrinter(String id) {
    printers.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  /// Sends a short test ticket to [p]. Stands in for real ESC/POS I/O over
  /// USB / Bluetooth SPP / a raw LAN socket — the transport [p.conn] picks between.
  Future<bool> testPrint(PosPrinter p) async {
    await Future.delayed(const Duration(milliseconds: 900));
    p.lastTestAt = DateTime.now();
    p.lastTestOk = true;
    notifyListeners();
    return true;
  }

  // ---------- backoffice sync ----------
  String backofficeUrl = 'https://v2database.bollgattea.com';
  String backofficeKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3ODQ0NTc0ODQsImV4cCI6MTg5MzQ1NjAwMCwicm9sZSI6ImFub24iLCJpc3MiOiJzdXBhYmFzZSJ9.WXyhtM_v3dP2_P1BwNmVdEXHwhfQ2fHanofZ3Prn_BQ';
  String backofficeOutletCode = 'BOLGATTY';
  DateTime? lastMenuSync;
  bool syncingMenu = false;
  MenuSyncResult? lastSyncResult;
  String? lastSyncError;

  void setBackofficeConfig({String? url, String? key, String? outletCode}) {
    if (url != null) backofficeUrl = url;
    if (key != null) backofficeKey = key;
    if (outletCode != null) backofficeOutletCode = outletCode;
    notifyListeners();
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
      final r = MenuSyncResult(added: added, updated: updated, removed: removed, at: DateTime.now());
      lastMenuSync = r.at;
      lastSyncResult = r;
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

  Order ensurePartyOrder(TableModel t, Party p, {String server = 'Sarah K.'}) {
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
  Order draft(OrderType type, {String server = 'Sarah K.'}) => Order(id: 0, type: type, server: server);
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
    o.rider ??= 'Vishnu · KL07 CK 4410';
    for (final l in o.lines) {
      l.state = LineState.served;
    }
    notifyListeners();
  }

  void settle(Order o) {
    assignBillNo(o);
    orders.remove(o);
    kots.removeWhere((k) => k.orderId == o.id);
    if (o.type == OrderType.dineIn) table(o.tableId!).parties.removeWhere((p) => p.orderId == o.id);
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

  // ---------- seed ----------
  void _seed() {
    final now = DateTime.now();
    OrderLine ln(String id, int q, LineState s, {String? v, List<String> a = const [], String n = ''}) =>
        OrderLine(item: item(id), qty: q, variant: v, addons: [...a], state: s, note: n);

    Order add(Order o, int mins, List<OrderLine> ls) {
      final k = Kot(++_kotSeq, o.id, now.subtract(Duration(minutes: mins)), []);
      for (final l in ls) {
        l.kotNo = k.no;
        k.lines.add(l);
        o.lines.add(l);
      }
      kots.add(k);
      if (!orders.contains(o)) orders.add(o);
      return o;
    }

    Order dine(String tid, String key, int pax, int mins, List<OrderLine> ls) {
      final t = table(tid);
      final p = Party(key, pax, seatedAt: now.subtract(Duration(minutes: mins)));
      t.parties.add(p);
      final o = Order(id: ++_orderSeq, type: OrderType.dineIn, tableId: tid, partyKey: key, pax: pax, at: p.seatedAt);
      p.orderId = o.id;
      return add(o, mins, ls);
    }

    const sv = LineState.served, pr = LineState.preparing, q = LineState.queued, rd = LineState.ready;
    dine('T2', 'A', 4, 22, [ln('p1', 2, sv, v: 'Regular 8"'), ln('v4', 4, sv)]);
    final t3 = dine('T3', 'A', 4, 71, [ln('m2', 1, sv), ln('g1', 2, sv, v: 'Half'), ln('v4', 4, sv), ln('d2', 2, sv)]);
    t3
      ..billed = true
      ..billNo = 'B${++_billSeq}';
    dine('T4', 'A', 2, 34, [ln('m1', 2, sv), ln('s2', 1, pr), ln('b1', 2, pr), ln('d1', 1, q, n: 'Serve after mains')]);
    dine('T5', 'A', 1, 14, [ln('v3', 1, sv, v: 'Regular'), ln('b1', 1, pr)]);
    dine('T5', 'B', 2, 6, [ln('s4', 1, sv), ln('m1', 1, q, n: 'Medium spicy')]);
    dine('T8', 'A', 12, 35, [ln('p2', 4, sv, v: 'Large 12"'), ln('s3', 3, pr), ln('v3', 6, q, v: 'Regular')]);
    dine('P1', 'A', 1, 12, [ln('b1', 1, pr, a: ['Cheese Slice'])]);

    add(
        Order(id: ++_orderSeq, type: OrderType.takeaway, token: 'TA-${++_taSeq}', customer: 'Priya', phone: '90480 55210',
            at: now.subtract(const Duration(minutes: 8))),
        8,
        [ln('m3', 1, pr, n: 'Less oil'), ln('v2', 2, rd)]);
    add(
        Order(id: ++_orderSeq, type: OrderType.takeaway, token: 'TA-${++_taSeq}', customer: 'Tom', phone: '81290 44120',
            at: now.subtract(const Duration(minutes: 19)), payNote: 'Paid · Cash'),
        19,
        [ln('b1', 1, rd, a: ['Cheese Slice']), ln('v3', 1, rd, v: 'Regular')]);
    final d1 = Order(id: ++_orderSeq, type: OrderType.delivery, customer: 'Rahul Menon', phone: '98470 11223',
        address: 'Flat 4B, Palm Grove, Kakkanad', at: now.subtract(const Duration(minutes: 26)), payNote: 'Paid · UPI');
    d1.token = '#${d1.id}';
    add(d1, 26, [ln('g1', 1, sv, v: 'Full', a: ['Mayonnaise']), ln('v4', 2, sv)]);
    d1
      ..dispatched = true
      ..rider = 'Anil · KL07 BX 2231';
    final d2 = Order(id: ++_orderSeq, type: OrderType.delivery, customer: 'Sneha K.', phone: '99610 33498',
        address: '12, Rose Villa, Edappally', at: now.subtract(const Duration(minutes: 5)), payNote: 'Cash on delivery');
    d2.token = '#${d2.id}';
    add(d2, 5, [ln('p1', 2, q, v: 'Medium 10"', a: ['Cheese Burst'])]);
  }
}
