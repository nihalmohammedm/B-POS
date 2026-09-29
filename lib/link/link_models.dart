import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// TCP port the main POS listens on for captain devices (restaurant Wi-Fi).
const linkPort = 8787;

/// UDP port the POS answers "where are you?" broadcasts on: the one after its link port.
int discoveryPortFor(int linkPort) => linkPort + 1;

/// What a captain broadcasts to find the POS on the Wi-Fi.
const discoveryQuery = 'BPOS?';

/// Short-lived pairing window: long enough to walk over and scan.
const pairingTtl = Duration(minutes: 5);

final _rng = Random.secure();

/// Random token for pairing or sessions (URL-safe, 32 bytes by default).
String newToken([int bytes = 32]) =>
    base64UrlEncode(List<int>.generate(bytes, (_) => _rng.nextInt(256))).replaceAll('=', '');

/// Only hashes are ever stored; the raw token lives on the captain device.
String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

/// Human-typable pairing code for when the camera can't scan: 8 characters,
/// no look-alikes (0/O, 1/I), shown as ABCD-EFGH.
String newPairCode() {
  const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(8, (_) => a[_rng.nextInt(a.length)]).join();
}

String normalizeCode(String c) => c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// What a paired device is for: a captain taking orders, or a kitchen display
/// (KDS) showing and bumping KOTs. Each kind may only run its own commands.
const deviceCaptain = 'captain', deviceKitchen = 'kitchen';

/// A captain phone/tablet or kitchen display paired with this POS.
class CaptainDevice {
  final String id;
  String name; // shown as the server on orders ("Arun"), or the station ("Grill")
  final String deviceInfo;
  final String kind; // [deviceCaptain] or [deviceKitchen]
  String sessionHash;
  final DateTime pairedAt;
  DateTime? lastSeenAt;

  CaptainDevice(
      {required this.id,
      required this.name,
      required this.deviceInfo,
      required this.sessionHash,
      required this.pairedAt,
      this.kind = deviceCaptain,
      this.lastSeenAt});

  bool get isKitchen => kind == deviceKitchen;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'deviceInfo': deviceInfo,
        'sessionHash': sessionHash,
        'kind': kind,
        'pairedAt': pairedAt.toIso8601String(),
        'lastSeenAt': lastSeenAt?.toIso8601String(),
      };

  factory CaptainDevice.fromJson(Map<String, dynamic> j) => CaptainDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        deviceInfo: j['deviceInfo'] as String? ?? '',
        sessionHash: j['sessionHash'] as String,
        pairedAt: DateTime.parse(j['pairedAt'] as String),
        kind: j['kind'] as String? ?? deviceCaptain,
        lastSeenAt: DateTime.tryParse(j['lastSeenAt'] as String? ?? ''),
      );
}

/// One open pairing offer on the POS: the QR token and the typed code both
/// work once, until [expiresAt]. Kept in memory only, so a restart voids it.
class PairingOffer {
  final String token, code;
  final DateTime expiresAt;
  final String tokenHash, codeHash;
  int failures = 0;
  PairingOffer(this.token, this.code, this.expiresAt)
      : tokenHash = hashToken(token),
        codeHash = hashToken(code);
  bool get expired => DateTime.now().isAfter(expiresAt) || failures >= 5;
}

/// "Grill marked served · Table 12 · 1× Alfaham": a kitchen display bumped a
/// KOT, so the counter knows the food has gone out.
class ServedNotice {
  final String id;
  final int orderId, kotNo;
  final String label, station, items;
  final bool handedOver; // takeaway/delivery: handed over rather than served
  final DateTime at;
  ServedNotice(
      {required this.id,
      required this.orderId,
      required this.kotNo,
      required this.label,
      required this.station,
      required this.items,
      required this.handedOver,
      required this.at});
}

/// "Captain Arun is asking for the bill · Table 12".
class BillRequest {
  final String id;
  final int orderId;
  final String label, captain;
  final DateTime at;
  BillRequest({required this.id, required this.orderId, required this.label, required this.captain, required this.at});
}
