import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import '../store.dart';
import '../widgets/receipt.dart';
import 'link_models.dart';

/// The main POS side of the captain link: a small HTTP + WebSocket server on the
/// restaurant Wi-Fi. Captains pair once, then keep one WebSocket open; the POS
/// pushes a snapshot of menu/tables/orders on connect and after every change,
/// and runs captain commands (seat, send KOT, request bill…) against its own
/// Store, the single source of truth. Works with the internet down.
///
/// Messages are JSON objects with a `t` (type) field:
///   captain → POS: pair {secret, name, device} · hello {session} · cmd {id, name, args}
///   POS → captain: paired {session, deviceId, name} · welcome {deviceId, name}
///                  snapshot {data} · res {id, ok, data | error} · bye {reason}
class PosHost {
  final Store s;
  final int port;
  PosHost(this.s, {this.port = linkPort});

  HttpServer? _server;
  RawDatagramSocket? _udp;
  final _clients = <_Client>{};
  Timer? _debounce;
  StreamSubscription<String>? _revokedSub;
  bool get running => _server != null;

  /// The port actually bound (differs from [port] when started with 0 in tests).
  int get boundPort => _server?.port ?? port;

  /// Replies to recent sendKot requests by request id, so a captain retrying
  /// after a dropped reply can't print the same KOT twice.
  final _done = <String, Map<String, dynamic>>{};

  Future<void> start() async {
    if (_server != null) return;
    // Saved captains must be loaded before one can say hello, or it would be
    // told it's unknown and sent back to pairing.
    await s.ready;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen(_onRequest, onError: (_) {});
      await _startDiscovery();
      s.addListener(_onStoreChange);
      _revokedSub = s.revokedCaptains.listen(_kick);
      s.setLinkState(running: true, addresses: await localAddresses());
    } catch (e) {
      _server = null;
      s.setLinkState(running: false, error: 'Could not open port $port: $e');
    }
  }

  Future<void> stop() async {
    _debounce?.cancel();
    s.removeListener(_onStoreChange);
    await _revokedSub?.cancel();
    for (final c in [..._clients]) {
      c.close('stopped');
    }
    await _server?.close(force: true);
    _server = null;
    _udp?.close();
    _udp = null;
    s.setLinkState(running: false);
  }

  /// Answers captains broadcasting [discoveryQuery] on the Wi-Fi, so a paired
  /// captain finds this POS again after its IP address changes. Skipped for an
  /// ephemeral port (tests); a failure here only costs auto-discovery.
  Future<void> _startDiscovery() async {
    if (port == 0) return;
    try {
      final u = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPortFor(port), reuseAddress: true);
      _udp = u;
      u.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = u.receive();
        if (d == null || utf8.decode(d.data, allowMalformed: true) != discoveryQuery) return;
        final reply = {'app': 'bpos', 'pos': s.posId, 'outlet': s.outletName, 'port': boundPort};
        u.send(utf8.encode(jsonEncode(reply)), d.address, d.port);
      });
    } catch (_) {}
  }

  /// This machine's Wi-Fi/LAN addresses, for the pairing screen.
  static Future<List<String>> localAddresses() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      return [
        for (final i in ifs)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.address.startsWith('169.254.')) a.address
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _onRequest(HttpRequest r) async {
    if (r.uri.path == '/ping') {
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode({'app': 'bpos', 'pos': s.posId, 'outlet': s.outletName}));
      await r.response.close();
      return;
    }
    if (r.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(r)) {
      final ws = await WebSocketTransformer.upgrade(r);
      ws.pingInterval = const Duration(seconds: 15); // notices a phone that walked out of range
      final c = _Client(ws, r.connectionInfo?.remoteAddress.address ?? '?', s.posId);
      _clients.add(c);
      ws.listen((m) => _onMessage(c, m), onDone: () => _drop(c), onError: (_) => _drop(c), cancelOnError: true);
      return;
    }
    r.response.statusCode = HttpStatus.notFound;
    await r.response.close();
  }

  void _drop(_Client c) {
    _clients.remove(c);
    final d = c.device;
    if (d != null && !_clients.any((x) => x.device?.id == d.id)) s.captainSeen(d, connected: false);
  }

  void _kick(String deviceId) {
    for (final c in [..._clients]) {
      if (c.device?.id == deviceId) c.close('revoked');
    }
  }

  // Coalesce bursts of changes into one snapshot per client.
  void _onStoreChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (_clients.every((c) => c.device == null)) return;
      final snap = jsonEncode({'t': 'snapshot', 'data': s.linkSnapshot()});
      for (final c in _clients) {
        if (c.device != null && c.lastSnapshot != snap) c.sendRaw(snap);
      }
    });
  }

  void _sendSnapshot(_Client c) => c.sendRaw(jsonEncode({'t': 'snapshot', 'data': s.linkSnapshot()}));

  Future<void> _onMessage(_Client c, dynamic raw) async {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return c.close('bad message');
    }
    switch (m['t']) {
      case 'pair':
        final secret = (m['secret'] as String? ?? '').trim();
        final name = (m['name'] as String? ?? '').trim();
        if (name.isEmpty) return c.close('Enter a captain name');
        if (!s.consumePairing(secret)) return c.close('Pairing code is wrong or has expired · make a new one on the POS');
        final kind = m['kind'] == deviceKitchen ? deviceKitchen : deviceCaptain;
        final (d, session) = s.registerCaptain(name, '${m['device'] ?? ''} · ${c.address}', kind: kind);
        c.device = d;
        s.captainSeen(d, connected: true);
        c.send({'t': 'paired', 'session': session, 'deviceId': d.id, 'name': d.name, 'outlet': s.outletName, 'pos': s.posId});
        _sendSnapshot(c);
      case 'hello':
        final d = s.captainBySession(m['session'] as String? ?? '');
        if (d == null) return c.close('unknown'); // removed on the POS, or a different POS
        c.device = d;
        s.captainSeen(d, connected: true);
        c.send({'t': 'welcome', 'deviceId': d.id, 'name': d.name, 'outlet': s.outletName, 'pos': s.posId});
        _sendSnapshot(c);
      case 'cmd':
        final d = c.device;
        final id = m['id'];
        if (d == null) return c.close('not paired');
        try {
          final data = await _run(d, m['name'] as String, (m['args'] as Map?)?.cast<String, dynamic>() ?? const {});
          c.send({'t': 'res', 'id': id, 'ok': true, 'data': data});
        } on LinkRefused catch (e) {
          c.send({'t': 'res', 'id': id, 'ok': false, 'error': e.message});
        } catch (e) {
          c.send({'t': 'res', 'id': id, 'ok': false, 'error': 'POS error: $e'});
        }
    }
  }

  // ---------- commands ----------

  Future<Map<String, dynamic>> _run(CaptainDevice d, String name, Map<String, dynamic> a) async {
    // A kitchen display only moves tickets; a captain never bumps them.
    final kitchenCmd = name.startsWith('kds');
    if (kitchenCmd != d.isKitchen) {
      throw LinkRefused(d.isKitchen ? 'A kitchen display can\'t do that' : 'Only a kitchen display can do that');
    }
    if (kitchenCmd) return _runKitchen(d, name, a);

    TableModel table() {
      final id = a['table'] as String?;
      for (final t in s.tables) {
        if (t.id == id) return t;
      }
      throw LinkRefused('Table $id is not on the POS');
    }

    Party party(TableModel t) =>
        s.party(t.id, a['party'] as String? ?? '') ?? (throw LinkRefused('That party is no longer seated at ${t.id}'));
    Order order() => s.orderById((a['orderId'] as num?)?.toInt() ?? -1) ?? (throw LinkRefused('That order is closed on the POS'));

    switch (name) {
      case 'seat':
        final t = table(), pax = (a['pax'] as num).toInt();
        if (pax < 1 || pax > t.free) throw LinkRefused('Only ${t.free} free seats on ${t.id}');
        return {'party': s.seatParty(t, pax).key};
      case 'setPax':
        final t = table();
        if (!s.setPax(t, party(t), (a['pax'] as num).toInt())) throw LinkRefused('No free seats on ${t.id}');
        return {};
      case 'freeParty':
        final t = table();
        if (!s.freeParty(t, party(t))) throw LinkRefused('This party has items · cancel them on the POS first');
        return {};
      case 'sendKot':
        return _sendKot(d, a);
      case 'updateCustomer':
        final o = order();
        o
          ..customer = a['customer'] as String? ?? o.customer
          ..phone = a['phone'] as String? ?? o.phone;
        s.touch();
        return {};
      case 'requestBill':
        final o = order();
        if (o.billed) throw LinkRefused('The bill is already printed');
        if (o.liveLines.isEmpty) throw LinkRefused('Nothing to bill yet');
        s.requestBill(o, d.name);
        s.notice('${d.name} is asking for the bill · ${s.titleOf(o)}');
        return {};
      case 'reopen':
        final o = order();
        if (!o.billed) return {};
        if (o.isPaid) throw LinkRefused('Already paid · can\'t reopen');
        return {'voided': s.reopen(o)};
    }
    throw LinkRefused('Unknown request "$name" · update the captain app');
  }

  /// Kitchen display actions on one KOT, the same ones the POS Kitchen screen has.
  Map<String, dynamic> _runKitchen(CaptainDevice d, String name, Map<String, dynamic> a) {
    final no = (a['kot'] as num?)?.toInt() ?? -1;
    final k = s.kotByNo(no);
    if (k == null || s.orderById(k.orderId) == null) throw LinkRefused('KOT #$no is closed on the POS');
    switch (name) {
      case 'kdsStart':
        s.startKot(k);
      case 'kdsReady':
        s.readyKot(k);
      case 'kdsBump':
        s.bumpKot(k);
        s.kitchenServed(k, d.name);
      case 'kdsRecall':
        s.recallKot(k);
      case 'kdsToggle':
        final i = (a['line'] as num?)?.toInt() ?? -1;
        if (i < 0 || i >= k.lines.length) throw LinkRefused('That item is no longer on KOT #$no');
        s.toggleLine(k.lines[i]);
      default:
        throw LinkRefused('Unknown request "$name" · update the kitchen app');
    }
    return {};
  }

  Future<Map<String, dynamic>> _sendKot(CaptainDevice d, Map<String, dynamic> a) async {
    final req = a['req'] as String?;
    if (req != null && _done.containsKey(req)) return _done[req]!;

    // Resolve the order: a seated party, an existing order, or a new takeaway.
    Order o;
    if (a['table'] != null) {
      final t = s.tables.where((x) => x.id == a['table']).firstOrNull ?? (throw LinkRefused('Table ${a['table']} is not on the POS'));
      final p = s.party(t.id, a['party'] as String? ?? '') ?? (throw LinkRefused('That party is no longer seated at ${t.id}'));
      o = s.ensurePartyOrder(t, p, server: d.name);
    } else if (a['orderId'] != null) {
      o = s.orderById((a['orderId'] as num).toInt()) ?? (throw LinkRefused('That order is closed on the POS'));
    } else {
      o = s.draft(OrderType.takeaway, server: d.name);
    }
    if (o.billed) throw LinkRefused(o.isPaid ? 'Already paid · start a new order' : 'Bill printed · reopen it first');

    // Rebuild lines from the POS's own menu: its prices and KOT routing win.
    final lines = <OrderLine>[];
    for (final e in (a['lines'] as List? ?? const [])) {
      final l = e as Map<String, dynamic>;
      final m = s.menu.where((x) => x.id == l['itemId']).firstOrNull ??
          (throw LinkRefused('${l['itemName'] ?? 'An item'} is no longer on the menu'));
      final off = s.offReason(m);
      if (off != null) throw LinkRefused('${m.name}: $off');
      lines.add(OrderLine(
        item: m,
        variant: l['variant'] as String?,
        addons: (l['addons'] as List? ?? const []).cast<String>(),
        qty: (l['qty'] as num).toInt(),
        note: l['note'] as String? ?? '',
      ));
    }
    if (lines.isEmpty) throw LinkRefused('No items to send');
    if (o.type != OrderType.dineIn) {
      o
        ..customer = a['customer'] as String? ?? o.customer
        ..phone = a['phone'] as String? ?? o.phone;
    }

    final ks = s.sendKot(o, lines);
    final res = {'orderId': o.id, 'kots': [for (final k in ks) k.no], 'label': s.labelOf(o)};
    if (req != null) {
      _done[req] = res;
      if (_done.length > 300) _done.remove(_done.keys.first);
    }

    // Print at the POS after replying, so the captain isn't kept waiting on paper.
    final data = [for (final k in ks) ReceiptData.kot(s, o, k)];
    unawaited(() async {
      for (final kd in data) {
        try {
          await printReceipt(s, kd);
        } catch (e) {
          s.notice('${d.name}\'s KOT #${kd.no} for ${s.titleOf(o)} did not print · $e', error: true);
        }
      }
    }());
    return res;
  }
}

/// A command the POS turned down, with a message for the captain.
class LinkRefused implements Exception {
  final String message;
  LinkRefused(this.message);
  @override
  String toString() => message;
}

class _Client {
  final WebSocket ws;
  final String address;
  final String posId;
  CaptainDevice? device;
  String? lastSnapshot;
  _Client(this.ws, this.address, this.posId);

  void send(Map<String, dynamic> m) => sendRaw(jsonEncode(m));

  void sendRaw(String s) {
    if (s.startsWith('{"t":"snapshot"')) lastSnapshot = s;
    try {
      ws.add(s);
    } catch (_) {}
  }

  void close(String reason) {
    send({'t': 'bye', 'reason': reason, 'pos': posId});
    ws.close(WebSocketStatus.normalClosure, reason.length > 100 ? reason.substring(0, 100) : reason);
  }
}
