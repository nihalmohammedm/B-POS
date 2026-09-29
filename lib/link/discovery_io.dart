import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'link_models.dart';

/// Finds the main POS on the current Wi-Fi when it isn't at the address the
/// captain paired with (the router handed it a new IP, or the phone came back
/// from another network). Broadcasts [discoveryQuery] to the POS's UDP
/// discovery port and collects the addresses that answer; with [sweep], falls
/// back to probing the link port on every host of the phone's /24 subnet, for
/// routers that drop broadcasts.
///
/// [posId] (when known) skips any other BPOS POS on the same network. The
/// caller still proves the match by logging in with its session.
Future<List<String>> discoverPos({String? posId, required int port, bool sweep = false}) async {
  final found = <String>{};
  final own = await _ownAddresses();
  try {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;
    sock.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = sock.receive();
      if (d == null) return;
      try {
        final m = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
        if (m['app'] != 'bpos') return;
        if (posId != null && m['pos'] != null && m['pos'] != posId) return;
        found.add(d.address.address);
      } catch (_) {}
    });
    final q = utf8.encode(discoveryQuery);
    final targets = {'255.255.255.255', for (final a in own) '${_prefix(a)}.255'};
    for (var round = 0; round < 2 && found.isEmpty; round++) {
      for (final t in targets) {
        try {
          sock.send(q, InternetAddress(t), discoveryPortFor(port));
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    sock.close();
  } catch (_) {}
  if (found.isEmpty && sweep) found.addAll(await _sweep(own, port));
  return found.toList();
}

/// Every host on the phone's /24 subnets that accepts a connection on [port].
Future<List<String>> _sweep(List<String> own, int port) async {
  final hits = <String>[];
  await Future.wait([
    for (final a in own.where(_isPrivate))
      for (var i = 1; i < 255; i++)
        if ('${_prefix(a)}.$i' != a)
          Socket.connect('${_prefix(a)}.$i', port, timeout: const Duration(milliseconds: 700)).then((s) {
            hits.add(s.remoteAddress.address);
            s.destroy();
          }, onError: (_) {}),
  ]);
  return hits;
}

Future<List<String>> _ownAddresses() async {
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

String _prefix(String ip) => ip.substring(0, ip.lastIndexOf('.'));

bool _isPrivate(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.contains(null)) return false;
  return p[0] == 10 || (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) || (p[0] == 192 && p[1] == 168);
}
