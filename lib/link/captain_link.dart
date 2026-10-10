import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../store.dart';
import 'discovery.dart';
import 'link_models.dart';

enum LinkState { unpaired, connecting, online, offline }

enum _Hello { ok, otherPos, unpaired }

/// A request the POS turned down or couldn't be reached for; [message] is
/// written for the captain.
class LinkError implements Exception {
  final String message;
  LinkError(this.message);
  @override
  String toString() => message;
}

/// Where the pairing (host, session token) is kept on the captain device.
abstract class LinkCreds {
  Future<Map<String, String>?> load();
  Future<void> save(Map<String, String> v);
  Future<void> clear();
}

/// Keychain/Keystore-backed storage: the session token is a credential.
///
/// A browser only offers secure storage on https:// or localhost pages. A
/// captain opened in a phone's browser at `http://<pos-ip>` isn't one, so there
/// the pairing falls back to the browser's ordinary local storage: fine for
/// trying the captain on a phone, but the installed Android app is the one to
/// use in service (its token stays in the Android Keystore).
class SecureLinkCreds implements LinkCreds {
  static const _key = 'bpos_captain_link';
  final _s = const FlutterSecureStorage();

  Future<T> _secureOr<T>(Future<T> Function() secure, Future<T> Function(SharedPreferences p) plain) async {
    try {
      return await secure();
    } catch (e) {
      if (!kIsWeb) rethrow;
      return plain(await SharedPreferences.getInstance());
    }
  }

  @override
  Future<Map<String, String>?> load() => _secureOr(() async => _s.read(key: _key), (p) async => p.getString(_key)).then(
      (v) => v == null ? null : (jsonDecode(v) as Map).cast<String, String>());

  @override
  Future<void> save(Map<String, String> v) =>
      _secureOr(() => _s.write(key: _key, value: jsonEncode(v)), (p) => p.setString(_key, jsonEncode(v)).then((_) {}));

  @override
  Future<void> clear() => _secureOr(() => _s.delete(key: _key), (p) => p.remove(_key).then((_) {}));
}

class MemoryLinkCreds implements LinkCreds {
  Map<String, String>? v;
  @override
  Future<Map<String, String>?> load() async => v;
  @override
  Future<void> save(Map<String, String> x) async => v = x;
  @override
  Future<void> clear() async => v = null;
}

/// What a pairing QR from the POS carries: every address the POS listens on
/// (it may have more than one network), the port, the one-time token.
class PairTarget {
  final List<String> hosts;
  final int port;
  final String secret;
  const PairTarget(this.hosts, this.port, this.secret);

  static String encode(List<String> hosts, int port, String token, String outlet) =>
      Uri(scheme: 'bpos', host: 'pair', queryParameters: {'h': hosts.join(','), 'p': '$port', 't': token, 'o': outlet}).toString();

  /// A scanned QR, or null if it isn't one of ours.
  static PairTarget? parse(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || u.scheme != 'bpos' || u.host != 'pair') return null;
    final hosts = (u.queryParameters['h'] ?? '').split(',').where((h) => h.isNotEmpty).toList();
    final t = u.queryParameters['t'] ?? '';
    if (hosts.isEmpty || t.isEmpty) return null;
    return PairTarget(hosts, int.tryParse(u.queryParameters['p'] ?? '') ?? linkPort, t);
  }
}

/// The captain side of the link to the main POS. Keeps one WebSocket open,
/// applies the POS's snapshots to the local mirror [store], and sends every
/// captain action to the POS as a request. Reconnects on its own when the
/// Wi-Fi drops; while offline the captain sees the last known state but can't
/// send anything, so nothing is ever "sent" that the kitchen didn't get.
class CaptainLink extends ChangeNotifier {
  final Store store;
  final LinkCreds creds;

  /// [deviceCaptain] or [deviceKitchen]: told to the POS when pairing.
  final String kind;
  CaptainLink(this.store, {LinkCreds? creds, this.kind = deviceCaptain}) : creds = creds ?? SecureLinkCreds();

  LinkState state = LinkState.connecting;
  String captainName = '';
  String outletName = '';
  String? host;
  int port = linkPort;
  String? lastError;
  DateTime? lastSnapshotAt;

  String? _session;
  String? _posId; // the paired POS's stable id, to recognise it at a new address
  bool _connecting = false, _again = false;
  StreamSubscription? _net;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retry;
  int _attempt = 0;
  int _seq = 0;
  bool _disposed = false;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Completer<Map<String, dynamic>>? _handshake;

  bool get online => state == LinkState.online;

  /// Loads the saved pairing and logs straight back in to the POS: at the saved
  /// address, or wherever the POS now is on this Wi-Fi.
  Future<void> init() async {
    // Back on Wi-Fi (or on a different network): try right away instead of
    // waiting for the next retry.
    try {
      _net = Connectivity().onConnectivityChanged.listen((r) {
        if (_session != null && !online && !r.contains(ConnectivityResult.none)) reconnect();
      }, onError: (_) {});
    } catch (_) {}
    Map<String, String>? c;
    try {
      c = await creds.load();
    } catch (_) {}
    if (c == null || c['session'] == null) {
      _set(LinkState.unpaired);
      return;
    }
    host = c['host'];
    port = int.tryParse(c['port'] ?? '') ?? linkPort;
    _session = c['session'];
    _posId = c['pos'];
    captainName = c['name'] ?? '';
    outletName = c['outlet'] ?? '';
    await _connect();
  }

  Future<void> _saveCreds() => creds.save({
        'host': host!,
        'port': '$port',
        'session': _session!,
        'name': captainName,
        'outlet': outletName,
        if (_posId != null) 'pos': _posId!,
      });

  /// Pairs with the POS using a scanned QR or a typed host + code. Returns an
  /// error message, or null once paired and online.
  Future<String?> pair({required List<String> hosts, int port = linkPort, required String secret, required String name}) async {
    _stop();
    String? err;
    for (final h in hosts) {
      try {
        final first = await _open(h, port, {'t': 'pair', 'secret': secret, 'name': name, 'device': _deviceLabel(), 'kind': kind});
        if (first['t'] == 'paired') {
          host = h;
          this.port = port;
          _session = first['session'] as String;
          captainName = first['name'] as String? ?? name;
          outletName = first['outlet'] as String? ?? '';
          _posId = first['pos'] as String?;
          await _saveCreds();
          _attempt = 0;
          lastError = null;
          _set(LinkState.online);
          return null;
        }
        err = first['reason'] as String? ?? 'The POS refused to pair';
        _stop();
        return err; // reached the POS and it said no: no point trying other addresses
      } catch (e) {
        err = "Can't reach the POS. Is the POS app open and on the same Wi-Fi?";
        _stop();
      }
    }
    _set(LinkState.unpaired);
    return err;
  }

  /// Forget this POS (e.g. moving the phone to another outlet).
  Future<void> unpair() async {
    _stop();
    _session = null;
    _posId = null;
    await creds.clear();
    _set(LinkState.unpaired);
  }

  /// Sends one captain action to the POS and waits for its answer.
  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> args = const {}]) async {
    final ch = _ch;
    if (!online || ch == null) throw LinkError('Not connected to the POS · check the Wi-Fi');
    final id = '${++_seq}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    ch.sink.add(jsonEncode({'t': 'cmd', 'id': id, 'name': name, 'args': args}));
    try {
      return await c.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw LinkError('The POS did not answer · check the Wi-Fi and try again');
    } finally {
      _pending.remove(id);
    }
  }

  // ---------- connection ----------

  /// One connection attempt at a time; a [reconnect] asked for mid-attempt
  /// runs straight after it rather than being lost.
  Future<void> _connect({bool manual = false}) async {
    if (_connecting) {
      if (manual) _again = true;
      return;
    }
    _connecting = true;
    try {
      do {
        _again = false;
        await _connectOnce();
      } while (_again && !_disposed && _session != null && !online);
    } finally {
      _connecting = false;
    }
  }

  Future<void> _connectOnce() async {
    final h = host;
    if (h == null || _session == null) return _set(LinkState.unpaired);
    _set(online ? LinkState.online : LinkState.connecting);
    String why;
    try {
      final r = await _hello(h);
      if (r != _Hello.otherPos) return;
      why = 'a different POS answers there';
    } catch (e) {
      _stop();
      why = _why(e);
    }

    // Not at the saved address: look for this POS on the current Wi-Fi (its IP
    // may have changed). The subnet sweep is heavier, so only every third try.
    lastError = "Can't reach the POS ($why). Looking for it on this Wi-Fi…";
    _set(LinkState.offline);
    final found = await discoverPos(posId: _posId, port: port, sweep: _attempt % 3 == 0);
    for (final other in found) {
      if (other == h || _session == null || _disposed) continue;
      try {
        if (await _hello(other, moved: true) == _Hello.ok) return;
      } catch (_) {
        _stop();
      }
    }
    if (_session == null || _disposed) return;
    lastError = "Can't reach the POS ($why).";
    _set(LinkState.offline);
    _scheduleRetry();
  }

  /// Logs in to the POS at [h] with the saved session. On success [h] becomes
  /// the saved address. [moved]: [h] is a discovered address, so a refusal
  /// there means another POS, not that this phone was removed.
  Future<_Hello> _hello(String h, {bool moved = false}) async {
    final first = await _open(h, port, {'t': 'hello', 'session': _session});
    if (first['t'] == 'welcome') {
      final addressChanged = host != h || _posId == null;
      host = h;
      captainName = first['name'] as String? ?? captainName;
      outletName = first['outlet'] as String? ?? outletName;
      _posId = first['pos'] as String? ?? _posId;
      _retry?.cancel();
      _attempt = 0;
      lastError = null;
      _set(LinkState.online);
      if (addressChanged) await _saveCreds();
      return _Hello.ok;
    }
    _stop();
    final reason = first['reason'] as String? ?? '';
    final pos = first['pos'] as String?;
    final otherPos = moved || (pos != null && _posId != null && pos != _posId);
    if (reason == 'unknown' || reason == 'revoked') {
      if (otherPos) return _Hello.otherPos;
      // Our POS no longer knows this phone: pair again.
      await unpair();
      lastError = 'This phone was removed on the POS · pair again';
      notifyListeners();
      return _Hello.unpaired;
    }
    throw LinkError(reason);
  }

  /// Opens the socket, sends [hello], and returns the POS's first reply.
  Future<Map<String, dynamic>> _open(String h, int p, Map<String, dynamic> hello) async {
    final ch = WebSocketChannel.connect(Uri.parse('ws://$h:$p/ws'));
    await ch.ready.timeout(const Duration(seconds: 4));
    _ch = ch;
    _handshake = Completer();
    _sub = ch.stream.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
    ch.sink.add(jsonEncode(hello));
    return _handshake!.future.timeout(const Duration(seconds: 5));
  }

  void _onMessage(dynamic raw) {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    final hs = _handshake;
    switch (m['t']) {
      case 'paired' || 'welcome':
        if (hs != null && !hs.isCompleted) hs.complete(m);
      case 'bye':
        if (hs != null && !hs.isCompleted) {
          hs.complete(m);
        } else if (m['reason'] == 'revoked') {
          unpair().then((_) {
            lastError = 'This phone was removed on the POS · pair again';
            notifyListeners();
          });
        }
      case 'snapshot':
        store.applyLinkSnapshot(m['data'] as Map<String, dynamic>);
        lastSnapshotAt = DateTime.now();
        notifyListeners();
      case 'res':
        final c = _pending[m['id']];
        if (c == null || c.isCompleted) return;
        m['ok'] == true
            ? c.complete((m['data'] as Map?)?.cast<String, dynamic>() ?? {})
            : c.completeError(LinkError(m['error'] as String? ?? 'The POS refused'));
    }
  }

  void _onClosed() {
    _ch = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(LinkError('Lost the connection to the POS'));
    }
    _pending.clear();
    final hs = _handshake;
    if (hs != null && !hs.isCompleted) hs.completeError(LinkError('closed'));
    if (_disposed || state == LinkState.unpaired || _session == null) return;
    lastError = 'Lost the connection to the POS';
    _set(LinkState.offline);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || _session == null) return;
    _retry?.cancel();
    const steps = [1, 2, 3, 5, 8, 10];
    final wait = steps[_attempt.clamp(0, steps.length - 1)];
    _attempt++;
    _retry = Timer(Duration(seconds: wait), _connect);
  }

  /// Try now instead of waiting for the next retry.
  void reconnect() {
    _retry?.cancel();
    _attempt = 0;
    _connect(manual: true);
  }

  void _stop() {
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    _ch?.sink.close();
    _ch = null;
  }

  void _set(LinkState s) {
    state = s;
    if (!_disposed) notifyListeners();
  }

  String _deviceLabel() => kIsWeb ? 'Web browser' : defaultTargetPlatform.name;

  @override
  void dispose() {
    _disposed = true;
    _net?.cancel();
    _stop();
    super.dispose();
  }
}

class CaptainLinkScope extends InheritedNotifier<CaptainLink> {
  const CaptainLinkScope({super.key, required CaptainLink link, required super.child}) : super(notifier: link);
  static CaptainLink? maybeOf(BuildContext c) => c.dependOnInheritedWidgetOfExactType<CaptainLinkScope>()?.notifier;
  static CaptainLink? read(BuildContext c) => c.getInheritedWidgetOfExactType<CaptainLinkScope>()?.notifier;
}

/// The low-level reason behind a failed connection, short enough to show:
/// tells "connection refused" (POS app closed / firewall) from "timed out"
/// (different network, router isolation) from Android's cleartext block.
String _why(Object e) {
  final s = '$e'.replaceAll(RegExp(r'\s+'), ' ');
  if (s.contains('Cleartext') || s.contains('CLEARTEXT')) return 'phone is blocking the local connection';
  if (s.contains('refused')) return 'POS app is not open';
  if (s.contains('TimeoutException') || s.contains('timed out')) return 'no answer, check both are on the same Wi-Fi';
  if (s.contains('No route') || s.contains('unreachable')) return 'not on the same Wi-Fi';
  return 'no answer';
}
