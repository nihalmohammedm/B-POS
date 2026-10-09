import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart' as esc;
import 'auth/supabase_auth_api.dart';
import 'backoffice_api.dart';
import 'db/app_database.dart';
import 'models.dart';
import 'link/link_models.dart';
import 'print_layout.dart';
import 'sync/bill_sync_api.dart';
import 'sync/menu_admin_api.dart';
import 'sync/web_order_api.dart';

class Store extends ChangeNotifier {
  /// [mirror]: a captain device's copy of the main POS. Its data comes from the
  /// POS over the restaurant Wi-Fi (see lib/link), so it never syncs the menu
  /// from the backoffice or talks to printers itself, and it keeps its own
  /// database file ([dbName], e.g. the kitchen display's own).
  Store({this.mirror = false, String? dbName}) : _db = AppDatabase(name: dbName ?? (mirror ? 'bpos_captain' : 'bistro_pos')) {
    _loadPersisted().catchError((Object e) => debugPrint('Loading saved data failed: $e')).whenComplete(_markReady);
  }

  final bool mirror;

  final _ready = Completer<void>();
  void _markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  /// Completes once saved data (menu, tables, paired captains…) is loaded from
  /// this device, without waiting on the network. The captain link waits on it,
  /// so a captain reconnecting while the POS is still starting up isn't told
  /// it's unknown and sent back to pairing.
  Future<void> get ready => _ready.future;

  // ---------- signed-in session (BPOS only; Captain stays unauthenticated) ----------
  String? authUserId;
  String? sessionEmail;
  String? sessionFullName;
  String? sessionAccessToken;
  String? roleCode;
  String? roleName;
  Set<String> permissions = {};

  bool get isSignedIn => authUserId != null;
  bool can(String permission) => permissions.contains(permission);

  void applySession({
    required String authUserId,
    required String email,
    required String fullName,
    required String accessToken,
    required String roleCode,
    required String roleName,
    required Set<String> permissions,
  }) {
    this.authUserId = authUserId;
    sessionEmail = email;
    sessionFullName = fullName;
    sessionAccessToken = accessToken;
    this.roleCode = roleCode;
    this.roleName = roleName;
    this.permissions = permissions;
    notifyListeners();
  }

  void clearSession() {
    authUserId = null;
    sessionEmail = null;
    sessionFullName = null;
    sessionAccessToken = null;
    roleCode = null;
    roleName = null;
    permissions = {};
    notifyListeners();
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
    // Async work (loading, connectivity, a captain dropping off) can finish
    // after the store is gone; there's nobody left to tell or anything to save.
    if (_disposed) return;
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
  final AppDatabase _db;

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
    webMenuBaseUrl = await _getSetting('webMenuBaseUrl') ?? webMenuBaseUrl;
    outletName = await _getSetting('outletName') ?? outletName;
    outletAddress = await _getSetting('outletAddress') ?? outletAddress;
    outletPhone = await _getSetting('outletPhone') ?? outletPhone;
    await _loadKotConfig();
    await _loadCaptains();
    final layoutStr = await _getSetting('printLayout');
    if (layoutStr != null) {
      try {
        printLayout = PrintLayout.fromJson(jsonDecode(layoutStr) as Map<String, dynamic>);
      } catch (_) {
        // Corrupt value: keep the defaults rather than failing startup.
      }
    }

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
    _relinkKotLines();

    final historyRows = await _db.select(_db.historyRows).get();
    history.addAll(historyRows.map((r) => Order.fromJson(jsonDecode(r.json) as Map<String, dynamic>)));
    await _loadBillSyncStatus();

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
    _markReady();

    // First-ever launch (nothing cached yet): pull the real menu straight away instead
    // of sitting empty until someone finds Settings.
    if (mirror) return;
    if (!hasMenuCache) {
      try {
        await syncMenu();
      } catch (_) {
        // Stays empty with lastSyncError set; Settings surfaces it for a manual retry.
      }
    }

    _wireBackgroundSync();
    checkPrinters();
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
    // Only the Main POS watches the web-order inbox; captain mirrors never talk to the backoffice.
    if (!mirror) _webOrderTimer = Timer.periodic(const Duration(seconds: 20), (_) => pollWebOrders());
  }

  void _applyConnectivity(List<ConnectivityResult> result, {bool triggerSync = true}) {
    final wasOnline = isOnline;
    isOnline = result.any((r) => r != ConnectivityResult.none);
    notifyListeners();
    if (triggerSync && isOnline && !wasOnline) _backgroundSync();
    // LAN printers sit on the same network: re-check them when it comes back.
    if (triggerSync && isOnline && !wasOnline) checkPrinters();
  }

  Future<void> _backgroundSync() async {
    if (!autoSyncEnabled || !isOnline || syncingMenu) return;
    try {
      await syncMenu();
    } catch (_) {
      // lastSyncError is already set by syncMenu; Settings surfaces it.
    }
    await _syncPendingBills();
  }

  // ---------- settled-bill sync (Supabase) ----------
  // Pushes every settled bill (table session + party + order + items + bill +
  // payments) to the bpos schema in the background — see settle() for where
  // an order is queued, and lib/sync/bill_sync_api.dart for the actual push.
  // The push itself is entirely silent (no dialog/toast); [billSyncStatus]
  // below is read by Settings → Settled bills so the state is visible without
  // interrupting anyone.

  bool _syncingBills = false;
  String? _cachedOutletId;
  String? _cachedOutletIdForCode;

  /// Local order id → where its push to Supabase stands. In memory only
  /// (reloaded from [_db] at startup); kept live so the settled-bills screen
  /// just rebuilds on [notifyListeners] like everything else in this Store.
  final Map<int, BillSyncStatus> billSyncStatus = {};

  /// Settled, non-voided orders — what Settings → Settled bills lists,
  /// newest first.
  List<Order> get settledBills => history.where((o) => !o.voided).toList()
    ..sort((a, b) => (b.billedAt ?? b.at).compareTo(a.billedAt ?? a.at));

  Future<void> _loadBillSyncStatus() async {
    final rows = await _db.select(_db.pendingBillSyncRows).get();
    billSyncStatus
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.orderId, _statusOf(r))));
  }

  BillSyncStatus _statusOf(PendingBillSyncRow r) => BillSyncStatus(
      switch (r.status) { 'synced' => BillSyncState.synced, 'failed' => BillSyncState.failed, _ => BillSyncState.pending },
      attempts: r.attempts,
      lastError: r.lastError);

  Future<void> _setBillSyncStatus(int orderId, String status, int attempts, String? error) async {
    await _db.into(_db.pendingBillSyncRows).insertOnConflictUpdate(PendingBillSyncRowsCompanion.insert(
        orderId: Value(orderId), status: Value(status), attempts: Value(attempts), lastError: Value(error)));
    billSyncStatus[orderId] = _statusOf(PendingBillSyncRow(orderId: orderId, status: status, attempts: attempts, lastError: error));
    notifyListeners();
  }

  Future<String> _resolveOutletId() async {
    if (_cachedOutletId != null && _cachedOutletIdForCode == backofficeOutletCode) return _cachedOutletId!;
    final id = await SupabaseAuthApi(baseUrl: backofficeUrl, anonKey: backofficeKey).resolveOutletId(backofficeOutletCode);
    _cachedOutletId = id;
    _cachedOutletIdForCode = backofficeOutletCode;
    return id;
  }

  Order? _historyById(int id) {
    for (final o in history) {
      if (o.id == id) return o;
    }
    return null;
  }

  Future<void> _enqueueBillSync(Order o) async {
    // Only the Main POS pushes to Supabase; a captain mirror's own copy of
    // this Store never talks to the backoffice directly (CLAUDE.md §21).
    if (mirror) return;
    await _setBillSyncStatus(o.id, 'pending', 0, null);
  }

  /// A bad order (wrong role, no configured payment method, no synced table)
  /// fails the same way every retry — stop trying it instead of looping.
  static const _maxBillSyncAttempts = 20;

  /// Resets a failed (or stuck) push back to pending — the retry button on
  /// the settled-bills screen.
  void retryBillSync(Order o) {
    _setBillSyncStatus(o.id, 'pending', 0, null).then((_) {
      if (isOnline) _syncPendingBills();
    });
  }

  Future<void> _syncPendingBills() async {
    if (_syncingBills || !isOnline) return;
    final token = sessionAccessToken;
    if (token == null || token.isEmpty) return; // nobody signed in on this device right now
    _syncingBills = true;
    try {
      final pending = await (_db.select(_db.pendingBillSyncRows)..where((t) => t.status.equals('pending'))).get();
      if (pending.isEmpty) return;

      String? outletId;
      Map<String, String>? paymentMethodIds;
      try {
        outletId = await _resolveOutletId();
      } catch (_) {
        return; // can't reach the backoffice right now; try again next cycle
      }
      final api = BillSyncApi(baseUrl: backofficeUrl, anonKey: backofficeKey, accessToken: token);

      for (final row in pending) {
        final o = _historyById(row.orderId);
        if (o == null) {
          // Order no longer exists locally (e.g. cleared data) — nothing left to push.
          await (_db.delete(_db.pendingBillSyncRows)..where((t) => t.orderId.equals(row.orderId))).go();
          billSyncStatus.remove(row.orderId);
          continue;
        }
        String? tableRemoteId;
        if (o.type == OrderType.dineIn) {
          if (o.tableId == null) {
            await _setBillSyncStatus(o.id, 'failed', row.attempts, 'Dine-in order has no table');
            continue;
          }
          final tIdx = tables.indexWhere((t) => t.id == o.tableId);
          tableRemoteId = tIdx == -1 ? null : tables[tIdx].remoteId;
        }
        if (o.type == OrderType.dineIn && tableRemoteId == null) {
          // Table hasn't been through a menu sync since this feature shipped
          // (or isn't in the backoffice) — retryable, a menu sync may fix it.
          await _setBillSyncStatus(o.id, 'pending', row.attempts + 1, 'Table not yet synced from backoffice');
          continue;
        }
        try {
          paymentMethodIds ??= await api.fetchPaymentMethodIds(outletId);
          await api.pushSettledOrder(o, outletId: outletId, tableRemoteId: tableRemoteId, paymentMethodIds: paymentMethodIds);
          await _setBillSyncStatus(o.id, 'synced', row.attempts + 1, null);
        } catch (e) {
          final retryable = e is! BillSyncException || e.retryable;
          final attempts = row.attempts + 1;
          final message = '$e';
          await _setBillSyncStatus(o.id, !retryable || attempts >= _maxBillSyncAttempts ? 'failed' : 'pending', attempts, message);
        }
      }
    } finally {
      _syncingBills = false;
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    _periodicSyncTimer?.cancel();
    _webOrderTimer?.cancel();
    _saveDebounce?.cancel();
    _notices.close();
    _revoked.close();
    super.dispose();
  }

  // ---------- print layout ----------
  PrintLayout printLayout = PrintLayout();

  void setPrintLayout(PrintLayout l) {
    printLayout = l.copy();
    notifyListeners();
    _setSetting('printLayout', jsonEncode(printLayout.toJson()));
  }

  /// Edits the UPI IDs / pay-QR switch on its own, straight from Settings, and
  /// saves at once. They live in the print layout so bills and previews read
  /// them from one place.
  void editPaymentQr(void Function(PrintLayout l) f) {
    final l = printLayout.copy();
    f(l);
    setPrintLayout(l);
  }

  // ---------- captain link (main POS side) ----------
  // Captain devices pair with this POS and talk to it over the restaurant Wi-Fi
  // (lib/link/pos_host.dart). Only hashes of pairing and session tokens are kept.

  final List<CaptainDevice> captainDevices = [];
  PairingOffer? pairing;

  /// Stable id of this POS, created on first run. Captains remember it so they
  /// can find this POS again on the Wi-Fi after its IP address changes.
  String posId = '';

  /// Captain device ids with a live connection right now.
  final Set<String> connectedCaptains = {};

  /// Whether this POS is accepting captains, and why not if it isn't.
  bool linkRunning = false;
  String? linkError;
  List<String> linkAddresses = const [];

  void setLinkState({required bool running, String? error, List<String>? addresses}) {
    linkRunning = running;
    linkError = error;
    if (addresses != null) linkAddresses = addresses;
    notifyListeners();
  }

  PairingOffer startPairing() {
    pairing = PairingOffer(newToken(), newPairCode(), DateTime.now().add(pairingTtl));
    notifyListeners();
    return pairing!;
  }

  void cancelPairing() {
    pairing = null;
    notifyListeners();
  }

  /// Checks a QR token or typed code against the open offer. One use only;
  /// five wrong tries void the offer.
  bool consumePairing(String secret) {
    final p = pairing;
    if (p == null || p.expired) return false;
    final h = hashToken(secret), hc = hashToken(normalizeCode(secret));
    if (h == p.tokenHash || hc == p.codeHash) {
      pairing = null;
      notifyListeners();
      return true;
    }
    p.failures++;
    return false;
  }

  /// Registers a newly paired device; returns it with the raw session token,
  /// which is handed to the device once and never stored here.
  (CaptainDevice, String) registerCaptain(String name, String deviceInfo, {String kind = deviceCaptain}) {
    final session = newToken();
    final d = CaptainDevice(
        id: newToken(9),
        name: name,
        deviceInfo: deviceInfo,
        kind: kind,
        sessionHash: hashToken(session),
        pairedAt: DateTime.now());
    captainDevices.add(d);
    notifyListeners();
    _saveCaptains();
    return (d, session);
  }

  CaptainDevice? captainBySession(String session) {
    final h = hashToken(session);
    for (final d in captainDevices) {
      if (d.sessionHash == h) return d;
    }
    return null;
  }

  void captainSeen(CaptainDevice d, {required bool connected}) {
    d.lastSeenAt = DateTime.now();
    connected ? connectedCaptains.add(d.id) : connectedCaptains.remove(d.id);
    notifyListeners();
    _saveCaptains();
  }

  final _revoked = StreamController<String>.broadcast();

  /// Device ids removed from this POS; the link host disconnects them.
  Stream<String> get revokedCaptains => _revoked.stream;

  void removeCaptain(String id) {
    captainDevices.removeWhere((d) => d.id == id);
    connectedCaptains.remove(id);
    _revoked.add(id);
    notifyListeners();
    _saveCaptains();
  }

  Future<void> _saveCaptains() =>
      _setSetting('captainDevices', jsonEncode(captainDevices.map((d) => d.toJson()).toList()));

  Future<void> _loadCaptains() async {
    posId = await _getSetting('posId') ?? '';
    if (posId.isEmpty) {
      posId = newToken(9);
      await _setSetting('posId', posId);
    }
    try {
      final v = await _getSetting('captainDevices');
      if (v != null) {
        captainDevices
          ..clear()
          ..addAll((jsonDecode(v) as List).map((e) => CaptainDevice.fromJson(e as Map<String, dynamic>)));
      }
    } catch (_) {
      // Corrupt value: captains re-pair.
    }
  }

  // ---------- web orders (public menu) ----------
  // Customers order from the public web menu (web_menu/index.html). Those land in
  // bpos.web_orders as "pending"; the counter accepts one here, which turns it into a
  // normal takeaway order + KOT, or rejects it. Polled, not pushed: offline just means
  // the inbox doesn't refresh until the connection returns.

  final List<WebOrder> webOrders = [];

  /// Where web_menu/index.html is hosted, e.g. https://menu.example.com — set in Settings → Web ordering.
  String webMenuBaseUrl = '';

  /// Public menu switched on for this outlet; null until read from the backoffice.
  bool? webMenuEnabled;

  /// The customer link for [tableLabel] (adds `&table=` so a table QR pre-fills it), or '' until a host is set.
  String webMenuLink({String tableLabel = ''}) {
    final base = webMenuBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return '';
    final t = tableLabel.trim();
    return '$base/?o=${Uri.encodeQueryComponent(backofficeOutletCode)}${t.isEmpty ? '' : '&table=${Uri.encodeQueryComponent(t)}'}';
  }

  void setWebMenuBaseUrl(String v) {
    webMenuBaseUrl = v.trim();
    notifyListeners();
    _setSetting('webMenuBaseUrl', webMenuBaseUrl);
  }

  Future<void> refreshWebMenuEnabled() async {
    try {
      webMenuEnabled = await WebOrderApi(baseUrl: backofficeUrl, anonKey: backofficeKey, accessToken: sessionAccessToken ?? backofficeKey)
          .fetchEnabled(backofficeOutletCode);
      notifyListeners();
    } catch (_) {
      // Offline: leave the last known value.
    }
  }

  Future<void> setWebMenuEnabled(bool on) async {
    final api = _webApi();
    if (api == null || !isOnline) throw WebOrderException('Go online to change this');
    await api.setEnabled(backofficeOutletCode, on);
    webMenuEnabled = on;
    notifyListeners();
  }
  Timer? _webOrderTimer;
  bool _pollingWebOrders = false;

  WebOrderApi? _webApi() {
    final token = sessionAccessToken;
    if (token == null || token.isEmpty) return null;
    return WebOrderApi(baseUrl: backofficeUrl, anonKey: backofficeKey, accessToken: token);
  }

  Future<void> pollWebOrders() async {
    if (mirror || _pollingWebOrders || !isOnline || !can('order.view')) return;
    final api = _webApi();
    if (api == null) return;
    _pollingWebOrders = true;
    try {
      final fresh = await api.fetchPending(await _resolveOutletId());
      final changed = fresh.length != webOrders.length || fresh.any((w) => !webOrders.any((x) => x.id == w.id));
      if (changed) {
        webOrders
          ..clear()
          ..addAll(fresh);
        notifyListeners();
      }
    } catch (_) {
      // Offline or backend unreachable: keep what we have, retry next tick.
    } finally {
      _pollingWebOrders = false;
    }
  }

  /// Accepts [w]: claims it on the backoffice first (so two counters can't both take it), then
  /// creates a takeaway order and its KOTs. Returns the order and KOTs to print, or null when
  /// someone else already decided it. Throws if it can't be accepted (item missing from this
  /// POS's menu, offline, no permission) before anything is changed.
  Future<(Order, List<Kot>)?> acceptWebOrder(WebOrder w) async {
    final api = _webApi();
    if (api == null || !isOnline) throw WebOrderException('Go online to accept web orders');
    if (!can('order.create')) throw WebOrderException('Your role cannot accept orders');

    // Build and validate everything locally first, so a menu mismatch can't strand a claimed order.
    final lines = <OrderLine>[];
    for (final l in w.lines) {
      final item = menu.where((m) => m.id == l.productId).firstOrNull;
      if (item == null) throw WebOrderException('"${l.name}" is not on this POS menu · sync the menu first');
      if (l.variant != null && !item.variants.any((v) => v.name == l.variant)) {
        throw WebOrderException('"${l.name} · ${l.variant}" changed on the menu · sync the menu first');
      }
      lines.add(OrderLine(item: item, variant: l.variant, addons: [...l.addons], qty: l.qty));
    }
    final note = w.notes.trim();
    if (note.isNotEmpty && lines.isNotEmpty) lines.first.note = note;

    final claimed = await api.decide(w.id, accept: true);
    webOrders.removeWhere((x) => x.id == w.id);
    if (!claimed) {
      notifyListeners();
      return null;
    }
    final o = draft(OrderType.takeaway, server: 'Web')
      ..customer = w.customer
      ..phone = w.phone
      ..address = [if (w.dineIn) 'Dine in${w.table.isEmpty ? '' : ' · Table ${w.table}'}' else 'Takeaway', if (note.isNotEmpty) note]
          .join(' · ');
    final ks = sendKot(o, lines);
    return (o, ks);
  }

  Future<void> rejectWebOrder(WebOrder w, {String? reason}) async {
    final api = _webApi();
    if (api == null || !isOnline) throw WebOrderException('Go online to reject web orders');
    await api.decide(w.id, accept: false, reason: reason);
    webOrders.removeWhere((x) => x.id == w.id);
    notifyListeners();
  }

  // ---------- bill requests & notices ----------

  final List<BillRequest> billRequests = [];

  /// A captain asks the counter for a bill. One open request per order.
  BillRequest requestBill(Order o, String captain) {
    for (final r in billRequests) {
      if (r.orderId == o.id) return r;
    }
    final r = BillRequest(id: newToken(6), orderId: o.id, label: titleOf(o), captain: captain, at: DateTime.now());
    billRequests.add(r);
    notifyListeners();
    return r;
  }

  void dismissBillRequest(String id) {
    billRequests.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// KOTs a kitchen display marked ready, for the counter; newest last.
  final List<ServedNotice> servedNotices = [];

  /// A kitchen display marked [k] ready: tell the counter. One notice per KOT,
  /// so a recall and re-ready doesn't stack a second one.
  void kitchenReady(Kot k, String station) {
    final o = orderById(k.orderId);
    if (o == null) return;
    servedNotices.removeWhere((n) => n.kotNo == k.no);
    final items = [
      for (final l in k.lines)
        if (l.activeQty > 0) '${l.activeQty}× ${l.item.name}'
    ].join(', ');
    servedNotices.add(ServedNotice(
        id: newToken(6),
        orderId: o.id,
        kotNo: k.no,
        label: titleOf(o),
        station: station,
        items: items,
        handedOver: o.type != OrderType.dineIn,
        at: DateTime.now()));
    notifyListeners();
  }

  /// [k] left the ready state (served or recalled): its notice is stale.
  void clearReadyNotice(Kot k) {
    if (servedNotices.any((n) => n.kotNo == k.no)) {
      servedNotices.removeWhere((n) => n.kotNo == k.no);
      notifyListeners();
    }
  }

  void dismissServed(String id) {
    servedNotices.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void dismissAllServed() {
    servedNotices.clear();
    notifyListeners();
  }

  final _notices = StreamController<(String, bool)>.broadcast();

  /// Messages for the POS screen from work done in the background (a captain's
  /// KOT printed or failed): (text, isError). The POS shell shows them as toasts.
  Stream<(String, bool)> get notices => _notices.stream;
  void notice(String msg, {bool error = false}) => _notices.add((msg, error));

  // ---------- snapshot: what captains see ----------

  /// Everything a captain needs, sent by the POS on connect and after changes.
  /// All active orders go to every captain: assignment isn't a visibility filter.
  Map<String, dynamic> linkSnapshot() => {
        'outlet': {'name': outletName, 'address': outletAddress, 'phone': outletPhone},
        'categories': categories,
        'menu': menu.map((m) => m.toJson()).toList(),
        'itemOff': itemOff.toList(),
        'catOff': catOff.toList(),
        'stock': stock,
        'tables': tables.map((t) => t.toJson()).toList(),
        'orders': orders.map((o) => o.toJson()).toList(),
        'kotGroups': kotGroups.map((g) => g.toJson()).toList(),
        'printLayout': printLayout.toJson(),
        'nextKot': _kotSeq + 1,
        'nextTa': _taSeq + 1,
        'billRequests': billRequests.map((r) => r.orderId).toList(),
        'kots': kitchenKots.map((k) => k.toJson()).toList(),
      };

  /// How long a cancellation KOT stays on kitchen displays: it has nothing
  /// left to cook, so it never goes "active", but the cook has to see it.
  static const cancelShowFor = Duration(minutes: 20);

  /// KOTs a kitchen display needs: every ticket still being worked on, plus
  /// recent cancellations/changes. Finished tickets stay off the wire.
  List<Kot> get kitchenKots {
    final now = DateTime.now();
    return kots
        .where((k) =>
            orderById(k.orderId) != null &&
            (k.stage != KotStage.done || (k.kind != KotKind.order && now.difference(k.at) < cancelShowFor)))
        .toList();
  }

  /// Order ids a captain has asked the bill for (mirror side).
  Set<int> requestedBills = {};

  /// Captain side: replace the local copy with the POS's.
  void applyLinkSnapshot(Map<String, dynamic> j) {
    final o = j['outlet'] as Map<String, dynamic>? ?? const {};
    outletName = o['name'] as String? ?? '';
    outletAddress = o['address'] as String? ?? '';
    outletPhone = o['phone'] as String? ?? '';
    categories = (j['categories'] as List? ?? []).cast<String>();
    menu
      ..clear()
      ..addAll((j['menu'] as List? ?? []).map((e) => MenuItem.fromJson(e as Map<String, dynamic>)));
    itemOff
      ..clear()
      ..addAll((j['itemOff'] as List? ?? []).cast<String>());
    catOff
      ..clear()
      ..addAll((j['catOff'] as List? ?? []).cast<String>());
    stock
      ..clear()
      ..addAll((j['stock'] as Map? ?? {}).map((k, v) => MapEntry(k as String, (v as num).toInt())));
    tables
      ..clear()
      ..addAll((j['tables'] as List? ?? []).map((e) => TableModel.fromJson(e as Map<String, dynamic>)));
    orders
      ..clear()
      ..addAll((j['orders'] as List? ?? []).map((e) => Order.fromJson(e as Map<String, dynamic>)));
    kotGroups = (j['kotGroups'] as List? ?? []).map((e) => KotGroup.fromJson(e as Map<String, dynamic>)).toList();
    if (j['printLayout'] is Map<String, dynamic>) printLayout = PrintLayout.fromJson(j['printLayout'] as Map<String, dynamic>);
    _kotSeq = ((j['nextKot'] as num?) ?? 1).toInt() - 1;
    _taSeq = ((j['nextTa'] as num?) ?? 1).toInt() - 1;
    requestedBills = {...(j['billRequests'] as List? ?? []).map((e) => (e as num).toInt())};
    kots
      ..clear()
      ..addAll((j['kots'] as List? ?? []).map((e) => Kot.fromJson(e as Map<String, dynamic>)));
    lastMenuSync = DateTime.now();
    notifyListeners();
    _saveMenu();
    _saveKotConfig();
  }

  // ---------- KOT groups & routing ----------
  // Groups and which item goes to which group come from the backoffice menu.
  // Which printer each group prints on is set on this device (printers are
  // local hardware). One printer per group; one printer can take several groups.

  List<KotGroup> kotGroups = [];

  /// Group id → printer ids. Key [noGroupKey] routes items with no group.
  final Map<String, Set<String>> kotRoutes = {};
  static const noGroupKey = '';

  KotGroup? kotGroup(String? id) {
    for (final g in kotGroups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Printers that get a KOT for [groupId]. A group with nothing picked falls
  /// back to the counter (bill) printer, or to every "Print KOTs" printer when
  /// there is none, so a ticket is never silently dropped.
  List<PosPrinter> kotPrintersFor(String? groupId) {
    final picked = kotRoutes[groupId ?? noGroupKey] ?? const {};
    final routed = printers.where((p) => picked.contains(p.id)).toList();
    return routed.isNotEmpty ? routed : kotFallbackPrinters;
  }

  /// Where KOTs for a group with no printer picked go: the counter printer
  /// (first "Print bills" printer, same one bills use), else every KOT printer.
  List<PosPrinter> get kotFallbackPrinters {
    final counter = billPrinters.take(1).toList();
    return counter.isNotEmpty ? counter : kotPrinters;
  }

  bool isRouted(String? groupId) => printers.any((p) => (kotRoutes[groupId ?? noGroupKey] ?? const {}).contains(p.id));

  /// Each group prints on one printer: picking a printer replaces the group's
  /// current one, and un-picking it leaves the group unassigned.
  void setKotRoute(String? groupId, String printerId, bool on) {
    final s = kotRoutes.putIfAbsent(groupId ?? noGroupKey, () => {});
    if (on) {
      s
        ..clear()
        ..add(printerId);
    } else {
      s.remove(printerId);
    }
    notifyListeners();
    _saveKotConfig();
  }

  int itemsInGroup(String? groupId) => menu.where((m) {
        if (m.variants.any((v) => v.kotGroup != null)) {
          return m.variants.any((v) => (v.kotGroup ?? m.kotGroup) == groupId);
        }
        return m.kotGroup == groupId;
      }).length;

  Future<void> _saveKotConfig() async {
    await _setSetting('kotGroups', jsonEncode(kotGroups.map((g) => g.toJson()).toList()));
    await _setSetting('kotRoutes', jsonEncode({for (final e in kotRoutes.entries) e.key: e.value.toList()}));
  }

  Future<void> _loadKotConfig() async {
    try {
      final g = await _getSetting('kotGroups');
      if (g != null) kotGroups = (jsonDecode(g) as List).map((e) => KotGroup.fromJson(e as Map<String, dynamic>)).toList();
      final r = await _getSetting('kotRoutes');
      if (r != null) {
        kotRoutes
          ..clear()
          // Routes saved when a group could take several printers keep only the first.
          ..addAll((jsonDecode(r) as Map<String, dynamic>).map((k, v) => MapEntry(k, {...(v as List).cast<String>().take(1)})));
      }
    } catch (_) {
      // Corrupt value: start unrouted (everything falls back to the counter printer).
    }
  }

  // ---------- printers ----------
  List<PosPrinter> get billPrinters => printers.where((p) => p.forBill).toList();
  List<PosPrinter> get kotPrinters => printers.where((p) => p.forKot).toList();

  /// A printer id not used by any saved printer. The counter isn't persisted, so
  /// it's bumped past the loaded ids — reusing one would make [_savePrinters]
  /// fail on the duplicate key and silently drop the new printer.
  String nextPrinterId() {
    for (final p in printers) {
      final n = p.id.startsWith('pr') ? int.tryParse(p.id.substring(2)) : null;
      if (n != null && n > _printerSeq) _printerSeq = n;
    }
    return 'pr${++_printerSeq}';
  }

  void addPrinter(PosPrinter p) {
    printers.add(p);
    notifyListeners();
    _savePrinters();
    checkPrinters(only: p);
  }

  void updatePrinter(PosPrinter p) {
    final i = printers.indexWhere((x) => x.id == p.id);
    if (i != -1) printers[i] = p;
    notifyListeners();
    _savePrinters();
    checkPrinters(only: p);
  }

  void removePrinter(String id) {
    _printerStatus.remove(id);
    printers.removeWhere((p) => p.id == id);
    for (final s in kotRoutes.values) {
      s.remove(id);
    }
    _saveKotConfig();
    notifyListeners();
    _savePrinters();
  }

  /// Candidate devices for [p], in the order to try them. A saved Bluetooth address
  /// doesn't record whether it came from a Classic or BLE scan, so both are tried.
  List<esc.PrinterDevice> _devicesFor(PosPrinter p) {
    switch (p.conn) {
      case PrinterConn.lan:
        final ip = p.ip?.trim() ?? '';
        if (ip.isEmpty) throw 'No IP address set';
        return [esc.NetworkPrinterDevice(name: p.name, host: ip, port: p.port)];
      case PrinterConn.bluetooth:
        final addr = p.btAddress?.trim() ?? '';
        if (addr.isEmpty) throw 'No Bluetooth device selected';
        return [
          esc.BluetoothPrinterDevice(name: p.name, address: addr),
          esc.BlePrinterDevice(name: p.name, deviceId: addr),
        ];
      case PrinterConn.usb:
        final id = p.usbIdentifier?.trim() ?? '';
        if (id.isEmpty) throw 'No USB device selected';
        return [
          esc.UsbPrinterDevice(
            name: p.name,
            identifier: id,
            usbPlatform: defaultTargetPlatform == TargetPlatform.android ? esc.UsbPlatform.android : esc.UsbPlatform.desktop,
          ),
        ];
    }
  }

  /// Sends raw ESC/POS [bytes] to [p] over its configured transport.
  /// Returns null on success, otherwise a human-readable error. The outcome
  /// also updates [statusOf], so a real print keeps the status indicator honest.
  Future<String?> sendToPrinter(PosPrinter p, List<int> bytes) async {
    final err = await _withPrinter(p, bytes, timeout: const Duration(seconds: 8));
    if (err != null) debugPrint('Print to ${p.name} failed: $err');
    _setStatus(p, err);
    return err;
  }

  /// Connects to [p], sends [bytes] if given (a check just connects), and
  /// disconnects. Tries each candidate device in turn; null means it worked.
  Future<String?> _withPrinter(PosPrinter p, List<int>? bytes, {required Duration timeout}) async {
    Object? lastErr;
    try {
      for (final d in _devicesFor(p)) {
        final m = esc.PrinterManager();
        try {
          await m.connect(d, timeout: timeout);
          if (bytes != null) await m.printBytes(bytes);
          await m.disconnect();
          return null;
        } catch (e) {
          lastErr = e;
          try {
            await m.disconnect();
          } catch (_) {}
        } finally {
          await m.dispose();
        }
      }
    } catch (e) {
      lastErr = e;
    }
    return '${lastErr ?? 'Could not connect'}';
  }

  // ---------- printer status ----------
  // Checked at startup, when the network comes back, and after a printer is
  // added or edited; every real print updates it too. Not persisted: a status
  // from before a restart says nothing about now.

  final Map<String, PrinterStatus> _printerStatus = {};
  bool checkingPrinters = false;

  PrinterStatus statusOf(PosPrinter p) => _printerStatus[p.id] ?? const PrinterStatus(PrinterHealth.unknown);
  List<PosPrinter> get offlinePrinters => printers.where((p) => statusOf(p).health == PrinterHealth.offline).toList();

  void _setStatus(PosPrinter p, String? err) {
    _printerStatus[p.id] =
        PrinterStatus(err == null ? PrinterHealth.online : PrinterHealth.offline, error: err, at: DateTime.now());
    notifyListeners();
  }

  /// Connects to each printer (or just [only]) without printing anything.
  Future<void> checkPrinters({PosPrinter? only}) async {
    final targets = only != null ? [only] : [...printers];
    if (targets.isEmpty || (only == null && checkingPrinters)) return;
    if (only == null) checkingPrinters = true;
    for (final p in targets) {
      _printerStatus[p.id] = PrinterStatus(PrinterHealth.checking, error: _printerStatus[p.id]?.error);
    }
    notifyListeners();
    await Future.wait(targets.map((p) async {
      // Scanning doesn't mean reachable, and a check must not stall the POS: keep it short.
      final err = await _withPrinter(p, null, timeout: const Duration(seconds: 5));
      if (printers.any((x) => x.id == p.id)) _setStatus(p, err);
    }));
    if (only == null) checkingPrinters = false;
    notifyListeners();
  }


  /// Sends a short ESC/POS test ticket to [p] over its configured transport.
  /// Returns null on success, otherwise a human-readable error.
  Future<String?> testPrint(PosPrinter p) async {
    String? error;
    try {
      final t = await esc.Ticket.create(esc.PaperSize.mm58);
      t.text('TEST PRINT',
          align: esc.PrintAlign.center,
          style: const esc.PrintTextStyle(bold: true, height: esc.TextSize.size2, width: esc.TextSize.size2));
      t.text(p.name, align: esc.PrintAlign.center);
      t.text('-' * 32);
      t.text('Connection: ${p.conn.label}');
      t.text('Address: ${p.connSummary}');
      t.text('Roles: ${[if (p.forBill) 'Bill', if (p.forKot) 'KOT'].join(', ')}');
      t.text('Time: ${DateTime.now().toString().substring(0, 19)}');
      t.text('-' * 32);
      t.text('Printer OK', align: esc.PrintAlign.center, style: const esc.PrintTextStyle(bold: true));
      t.cut(linesBefore: 3);
      error = await sendToPrinter(p, t.bytes);
    } catch (e) {
      error = '$e';
    }
    p.lastTestAt = DateTime.now();
    p.lastTestOk = error == null;
    notifyListeners();
    _savePrinters();
    return error;
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
      // A fresh menu upload fully replaces the live menu rather than patching it in
      // place, so a reordered/reshuffled upload can't leave stale items or stale
      // positions behind — counts below are just for the sync toast.
      final oldById = {for (final m in menu) m.id: m};
      final newIds = {for (final m in result.items) m.id};
      final added = newIds.difference(oldById.keys.toSet()).length;
      final removed = oldById.keys.toSet().difference(newIds).length;
      final updated = result.items.where((m) => oldById[m.id] != null && oldById[m.id] != m).length;
      menu
        ..clear()
        ..addAll(result.items);
      categories = result.categories;
      kotGroups = result.kotGroups;
      subCatTree = result.subCats;
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
            ..h = t.h
            ..remoteId = t.remoteId;
        }
      }
      tables.removeWhere((t) => !seenTableIds.contains(t.id) && t.parties.isEmpty);

      final r = MenuSyncResult(added: added, updated: updated, removed: removed, at: DateTime.now());
      lastMenuSync = r.at;
      lastSyncResult = r;
      await _saveMenu();
      await _saveKotConfig();
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

  // ---------- menu editing (written to Supabase for this outlet) ----------

  bool get canEditMenu => can('menu.manage') && sessionAccessToken != null;

  Future<MenuAdminApi> _menuAdmin() async {
    final token = sessionAccessToken;
    if (token == null || !can('menu.manage')) throw MenuAdminException('You need the menu.manage permission to edit the menu');
    return MenuAdminApi(baseUrl: backofficeUrl, anonKey: backofficeKey, accessToken: token, outletId: await _resolveOutletId());
  }

  /// Saves [m] to Supabase first and only then updates the local menu, so the
  /// POS never shows an edit the backoffice rejected. A new item has an empty id.
  /// Old orders keep their own copy of name and price, so they don't change.
  Future<MenuItem> saveMenuItem(MenuItem m) async {
    final api = await _menuAdmin();
    final i = menu.indexWhere((x) => x.id == m.id);
    final saved = i == -1 ? await api.createItem(m) : await api.updateItem(m, menu[i]);
    final at = menu.indexWhere((x) => x.id == saved.id);
    at == -1 ? menu.add(saved) : menu[at] = saved;
    if (!categories.contains(saved.cat)) categories = [...categories, saved.cat];
    await _saveMenu();
    notifyListeners();
    return saved;
  }

  Future<void> removeMenuItem(MenuItem m) async {
    await (await _menuAdmin()).deactivateItem(m.id);
    menu.removeWhere((x) => x.id == m.id);
    itemOff.remove(m.id);
    stock.remove(m.id);
    await _saveMenu();
    notifyListeners();
  }

  // ---------- menu ----------
  MenuItem item(String id) => menu.firstWhere((m) => m.id == id);
  List<MenuItem> itemsIn(String cat) => menu.where((m) => m.cat == cat).toList();

  /// Distinct sub-categories inside [cat], in first-appearance (display) order.
  List<String> subCatsIn(String cat) {
    final seen = <String>{};
    return [
      for (final m in itemsIn(cat))
        if (m.subCat.isNotEmpty && seen.add(m.subCat)) m.subCat,
    ];
  }

  /// Sub-categories known for [cat] from the last sync, including empty ones, so a new item can be
  /// filed under one. Falls back to those in use when offline / not yet synced.
  Map<String, List<String>> subCatTree = {};
  List<String> subCatChoices(String cat) {
    final seen = <String>{};
    return [for (final n in [...(subCatTree[cat] ?? const <String>[]), ...subCatsIn(cat)]) if (seen.add(n)) n]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

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

  // ---------- floor layout ----------
  bool _cellFree(TableModel self, int gx, int gy) {
    for (final o in tables) {
      if (identical(o, self) || o.floor != self.floor || o.gx == null || o.gy == null) continue;
      if (gx < o.gx! + o.w && o.gx! < gx + self.w && gy < o.gy! + o.h && o.gy! < gy + self.h) return false;
    }
    return true;
  }

  /// Gives every table on [floor] that has no saved position the first free spot, row by row
  /// across [cols] columns. Pure bookkeeping (no notify): the result is saved with the next save.
  void placeUnplaced(String floor, int cols) {
    for (final t in tables) {
      if (t.floor != floor || (t.gx != null && t.gy != null)) continue;
      final maxX = math.max(0, cols - t.w);
      for (var y = 0;; y++) {
        var done = false;
        for (var x = 0; x <= maxX && !done; x++) {
          if (_cellFree(t, x, y)) {
            t.gx = x;
            t.gy = y;
            done = true;
          }
        }
        if (done) break;
      }
    }
  }

  /// Moves [t] to cell ([gx], [gy]), kept inside the plan ([cols] x [rows] cells when given). If that
  /// overlaps another table the nearest free cell is used; if there is none the table stays put.
  void moveTable(TableModel t, int gx, int gy, {int? cols, int? rows}) {
    final maxX = cols == null ? 1 << 20 : math.max(0, cols - t.w), maxY = rows == null ? 1 << 20 : math.max(0, rows - t.h);
    gx = gx.clamp(0, maxX);
    gy = gy.clamp(0, maxY);
    (int, int)? best = _cellFree(t, gx, gy) ? (gx, gy) : null;
    if (best == null) {
      var bestD = 1 << 30;
      for (var r = -10; r <= 10; r++) {
        for (var c = -10; c <= 10; c++) {
          final x = gx + c, y = gy + r;
          if (x < 0 || y < 0 || x > maxX || y > maxY || !_cellFree(t, x, y)) continue;
          final d = c * c + r * r;
          if (d < bestD) {
            bestD = d;
            best = (x, y);
          }
        }
      }
    }
    if (best == null) return;
    t.gx = best.$1;
    t.gy = best.$2;
    notifyListeners();
  }

  /// Forgets saved positions on [floor]; tables flow back into rows automatically.
  void resetLayout(String floor) {
    for (final t in tables) {
      if (t.floor == floor) t.gx = t.gy = null;
    }
    notifyListeners();
  }

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
    if (o != null && o.liveLines.isNotEmpty) return false;
    if (o != null) {
      orders.remove(o);
      kots.removeWhere((k) => k.orderId == o.id);
      // Every item was cancelled: keep the order and its cancellations for audit.
      if (o.lines.isNotEmpty) history.add(o..voided = true);
    }
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
  String get nextTaToken => 'Counter ${_taSeq + 1}';
  int get nextKotNo => _kotSeq + 1;
  String previewBillNo(Order o) => o.billNo ?? 'B${_billSeq + 1}';

  String labelOf(Order o) {
    if (o.held && o.heldLabel != null) return o.heldLabel!;
    if (o.type == OrderType.dineIn) return partyLabel(table(o.tableId!), o.partyKey!);
    return o.token.isEmpty ? (o.type == OrderType.takeaway ? nextTaToken : 'New') : o.token;
  }

  String titleOf(Order o) =>
      o.type == OrderType.dineIn ? 'Table ${labelOf(o)}' : (o.customer.isEmpty ? 'Walk-in' : o.customer);

  OrderStage stageOf(Order o) {
    // Takeaway/delivery bills print with the order, so they keep following the kitchen.
    if (o.billed && !o.isPaid && o.type == OrderType.dineIn) return OrderStage.billing;
    if (o.dispatched) return OrderStage.outForDelivery;
    final live = o.liveLines;
    if (live.isEmpty) return OrderStage.placed;
    if (live.every((l) => l.state == LineState.served)) {
      return o.type == OrderType.dineIn ? OrderStage.served : OrderStage.ready;
    }
    if (live.every((l) => l.state.index >= LineState.ready.index)) return OrderStage.ready;
    return OrderStage.preparing;
  }

  List<Order> get activeOrders => orders.where((o) => o.lines.isNotEmpty).toList()..sort((a, b) => a.at.compareTo(b.at));

  List<Kot> sendKot(Order o, List<OrderLine> lines) {
    if (!orders.contains(o)) {
      o.id = ++_orderSeq;
      if (o.type == OrderType.takeaway) {
        o.token = 'Counter ${++_taSeq}';
      } else if (o.type == OrderType.delivery) {
        o.token = '#${o.id}';
      }
      orders.add(o);
    }
    // One order can need several kitchen sections: one KOT (and number) per KOT group.
    final at = DateTime.now();
    final out = <Kot>[];
    for (final g in _byGroup(lines, (l) => l.kotGroup)) {
      final k = Kot(++_kotSeq, o.id, at, [], group: g.$1);
      for (final l in g.$2) {
        final c = l.copy()
          ..state = LineState.queued
          ..kotNo = k.no;
        k.lines.add(c);
        o.lines.add(c);
        final s = stock[l.item.id];
        if (s != null) stock[l.item.id] = math.max(0, s - l.qty);
      }
      kots.add(k);
      out.add(k);
    }
    _linkBatch(out);
    notifyListeners();
    return out;
  }

  /// Tells each KOT sent together about the others ("KOT 1 of 3").
  void _linkBatch(List<Kot> out) {
    final nos = [for (final k in out) k.no];
    for (final k in out) {
      k.batch
        ..clear()
        ..addAll(nos);
    }
  }

  /// Splits [xs] by KOT group, in the backoffice's group order; items with no
  /// group (or a group no longer on the menu) come last.
  List<(String?, List<T>)> _byGroup<T>(Iterable<T> xs, String? Function(T) groupOf) {
    final m = <String?, List<T>>{};
    for (final x in xs) {
      m.putIfAbsent(groupOf(x), () => []).add(x);
    }
    int rank(String? g) {
      final i = kotGroups.indexWhere((x) => x.id == g);
      return i == -1 ? kotGroups.length : i;
    }

    final keys = m.keys.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
    return [for (final k in keys) (k, m[k]!)];
  }

  Kot? lastKot(Order o) {
    Kot? r;
    for (final k in kots) {
      if (k.orderId == o.id) r = k;
    }
    return r;
  }

  String assignBillNo(Order o) => o.billNo ??= 'B${++_billSeq}';

  /// Bills printed and waiting for payment, longest-waiting first.
  List<Order> get awaitingPayment => orders.where((o) => o.billed && !o.isPaid).toList()
    ..sort((a, b) => (a.billedAt ?? a.at).compareTo(b.billedAt ?? b.at));

  String printBill(Order o) {
    o.billed = true;
    billRequests.removeWhere((r) => r.orderId == o.id); // asked for, now done
    o.billedAt = DateTime.now();
    final no = assignBillNo(o);
    notifyListeners();
    return no;
  }

  /// Held bills: printed, table cleared, still waiting to be settled.
  List<Order> get heldOrders => orders.where((o) => o.held).toList()
    ..sort((a, b) => (a.heldAt ?? a.at).compareTo(b.heldAt ?? b.at));

  /// Clears the table but keeps the printed bill open for settlement later. The
  /// order stays in [orders] (so it shows under Payments and can be settled as
  /// usual) with its table label frozen. Returns false if it can't be held.
  bool holdBill(Order o) {
    if (o.type != OrderType.dineIn || !o.billed || o.isPaid || o.held || !orders.contains(o)) return false;
    o.heldLabel = labelOf(o);
    o.held = true;
    o.heldAt = DateTime.now();
    table(o.tableId!).parties.removeWhere((p) => p.orderId == o.id);
    notifyListeners();
    return true;
  }

  String? reopen(Order o) {
    final v = o.billNo;
    o.billed = false;
    o.billNo = null;
    o.billedAt = null;
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

  /// Takes payment before the food is ready (takeaway "Pay now"). The paid
  /// invoice counts as the bill, so the order is locked like a billed one; it
  /// stays open until it's handed over ([settle] with no further payments).
  String prepay(Order o, List<Payment> pays) {
    billRequests.removeWhere((r) => r.orderId == o.id);
    o.payments.addAll(pays);
    o.payNote = 'Paid · ${{for (final p in pays) p.method}.join(' + ')}';
    o.billed = true;
    o.billedAt = DateTime.now();
    final no = assignBillNo(o);
    notifyListeners();
    return no;
  }

  /// Applies a discount to [o] before it's settled — reduces the amount due
  /// (and, since tax is computed after discount, the tax too). [amount] is
  /// already resolved to a flat ₹ figure regardless of how staff entered it
  /// (fixed or % of subtotal); clamped so it can never exceed the subtotal.
  /// Gate the call site on `s.can('discount.apply')`.
  void setDiscount(Order o, {required double amount, required String reason}) {
    o.discountAmount = amount.clamp(0, o.subtotal);
    o.discountReason = reason;
    notifyListeners();
  }

  void clearDiscount(Order o) {
    o.discountAmount = 0;
    o.discountReason = null;
    notifyListeners();
  }

  void settle(Order o, {List<Payment> payments = const []}) {
    billRequests.removeWhere((r) => r.orderId == o.id);
    servedNotices.removeWhere((n) => n.orderId == o.id); // order closed: nothing left to act on
    assignBillNo(o);
    o.payments.addAll(payments);
    _archive(o);
  }

  /// Settles [o] with nothing charged — explicitly flagged as complimentary,
  /// never just a normal bill with the amount zeroed (CLAUDE.md §18). Gate
  /// the call site on `s.can('discount.apply')`.
  void settleComplimentary(Order o, {required String reason, String by = ''}) {
    billRequests.removeWhere((r) => r.orderId == o.id);
    servedNotices.removeWhere((n) => n.orderId == o.id);
    assignBillNo(o);
    o.complimentary = true;
    o.complimentaryReason = reason;
    o.payNote = 'Complimentary · $reason';
    _archive(o);
  }

  /// Shared tail of [settle]/[settleComplimentary]: close the order out of
  /// the active lists, archive it, and queue the background Supabase push.
  void _archive(Order o) {
    orders.remove(o);
    kots.removeWhere((k) => k.orderId == o.id);
    if (o.type == OrderType.dineIn) table(o.tableId!).parties.removeWhere((p) => p.orderId == o.id);
    history.add(o);
    notifyListeners();
    // Local-only and instant — settlement never waits on network. The actual
    // push happens in the background (see _syncPendingBills).
    _enqueueBillSync(o).then((_) {
      if (isOnline) _syncPendingBills();
    });
  }

  /// Refunds [amount] from payment [paymentIndex] on an already-settled [o].
  /// The original [Payment] is never edited — this is its own auditable
  /// record (CLAUDE.md §19/§29), re-pushed to Supabase as a new
  /// `payment_refunds` row. Gate the call site on `s.can('payment.refund')`.
  /// Returns false (nothing changed) if [amount] isn't valid for that payment.
  bool refundPayment(Order o, int paymentIndex, double amount, String reason, {String by = ''}) {
    if (paymentIndex < 0 || paymentIndex >= o.payments.length) return false;
    final p = o.payments[paymentIndex];
    final alreadyRefunded =
        o.refunds.where((r) => r.paymentIndex == paymentIndex).fold<double>(0, (a, r) => a + r.amount);
    if (amount <= 0 || amount > p.amount - alreadyRefunded + 0.005) return false;
    o.refunds.add(Refund(paymentIndex: paymentIndex, amount: amount, reason: reason, by: by, at: DateTime.now()));
    notifyListeners();
    // pushSettledOrder is idempotent (deterministic ids, upsert) — re-queuing
    // the already-synced order for another pass re-upserts bills with the
    // corrected total and pushes the new payment_refunds row. No separate
    // sync mechanism needed for a refund.
    _setBillSyncStatus(o.id, 'pending', 0, null).then((_) {
      if (isOnline) _syncPendingBills();
    });
    return true;
  }

  // ---------- cancel / edit sent items ----------
  // Every change to an item the kitchen already has produces a KOT to print:
  // a cancellation KOT for removed units, a modified KOT when an item is swapped
  // for a different size/add-ons/note, or a normal KOT for extra units.

  List<String> cancelReasons = [...defaultCancelReasons];
  List<String> complimentaryReasons = [...defaultComplimentaryReasons];
  List<String> discountReasons = [...defaultDiscountReasons];

  /// Items can't change once the bill is printed; reopen it first.
  bool canAmend(Order o) => !o.billed && orders.contains(o);

  bool canCancel(Order o) => !o.billed;

  /// Cancels [qty] units of sent line [l]. Returns the cancellation KOT to print.
  List<Kot> cancelItem(Order o, OrderLine l, int qty, String reason, {String by = ''}) =>
      _amend(o, [(l, qty)], null, reason, by);

  /// Changes sent line [l] to [updated]. Fewer units of the same item is a
  /// cancellation, more units is a normal KOT for the extra, anything else
  /// (size, add-ons, note) cancels the old line and sends the new one: one
  /// modified KOT when both are in the same KOT group, otherwise a cancellation
  /// KOT to the old group and a normal KOT to the new one. Returns the KOTs to
  /// print (empty if nothing changed).
  List<Kot> editItem(Order o, OrderLine l, OrderLine updated, String reason, {String by = ''}) {
    if (updated.qty <= 0) return cancelItem(o, l, l.activeQty, reason, by: by);
    if (l.sameConfig(updated)) {
      final extra = updated.qty - l.activeQty;
      if (extra == 0) return const [];
      if (extra < 0) return cancelItem(o, l, -extra, reason, by: by);
      return sendKot(o, [
        updated.copy()
          ..qty = extra
          ..cancelledQty = 0
      ]);
    }
    return _amend(o, [(l, l.activeQty)], updated, reason, by);
  }

  /// Cancels everything left on [o], one cancellation KOT per KOT group, or
  /// nothing if nothing was left. The order stays open until [closeVoidedOrder],
  /// so the KOTs can still be rendered with the table label.
  List<Kot> cancelAllItems(Order o, String reason, {String by = ''}) =>
      _amend(o, [for (final l in o.liveLines) (l, l.activeQty)], null, reason, by);

  /// Archives an order whose items are all cancelled (history keeps the audit trail).
  void closeVoidedOrder(Order o) {
    orders.remove(o);
    kots.removeWhere((k) => k.orderId == o.id);
    if (o.type == OrderType.dineIn) table(o.tableId!).parties.removeWhere((p) => p.orderId == o.id);
    if (o.lines.isNotEmpty) history.add(o..voided = true);
    notifyListeners();
  }

  List<Kot> _amend(Order o, List<(OrderLine, int)> cancel, OrderLine? replacement, String reason, String by) {
    final at = DateTime.now();
    final cuts = [
      for (final (l, qty) in cancel)
        if (math.min(qty, l.activeQty) > 0) (l, math.min(qty, l.activeQty))
    ];
    // Each kitchen section hears only about its own items.
    final groups = <String?>{
      ...[for (final (l, _) in cuts) l.kotGroup],
      if (replacement != null) replacement.kotGroup,
    };
    final out = <Kot>[];
    for (final g in _byGroup(groups, (x) => x)) {
      final k = Kot(++_kotSeq, o.id, at, [], reason: reason, by: by, group: g.$1);
      for (final (l, n) in cuts.where((c) => c.$1.kotGroup == g.$1)) {
        l.cancelledQty += n;
        k.voided.add(l.copy()
          ..qty = n
          ..cancelledQty = 0);
        o.cancellations.add(ItemCancellation(
            itemName: l.item.name,
            optText: l.optText,
            qty: n,
            unitPrice: l.unit,
            reason: reason,
            by: by,
            kotNo: k.no,
            at: at,
            lineIndex: o.lines.indexOf(l)));
        // Nothing cooked yet, so tracked portions go back into stock.
        final st = stock[l.item.id];
        if (st != null && l.state == LineState.queued) stock[l.item.id] = st + n;
      }
      if (replacement != null && replacement.kotGroup == g.$1) {
        final c = replacement.copy()
          ..state = LineState.queued
          ..kotNo = k.no
          ..cancelledQty = 0;
        k.lines.add(c);
        o.lines.add(c);
        final st = stock[c.item.id];
        if (st != null) stock[c.item.id] = math.max(0, st - c.qty);
      }
      kots.add(k);
      out.add(k);
    }
    _linkBatch(out);
    notifyListeners();
    return out;
  }

  // ---------- kitchen ----------

  /// A KOT's lines are the same objects as its order's lines while the app
  /// runs, so kitchen progress shows on the order. Saved separately, they load
  /// as copies: point each KOT back at its order's lines (same kotNo, same
  /// order they were added in).
  void _relinkKotLines() {
    for (final k in kots) {
      final o = orderById(k.orderId);
      if (o == null || k.lines.isEmpty) continue;
      final own = o.lines.where((l) => l.kotNo == k.no).toList();
      if (own.length == k.lines.length) k.lines.setAll(0, own);
    }
  }

  Kot? kotByNo(int no) {
    for (final k in kots) {
      if (k.no == no) return k;
    }
    return null;
  }

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
