import 'dart:convert';
import 'package:http/http.dart' as http;
import '../plain_error.dart';

/// One Main POS of an outlet, as listed in `bpos.pos_devices`.
class PosDeviceInfo {
  final String id, code, name;
  final bool isPrimary, isActive;
  final DateTime? lastSeen, lastSync;
  final String? appVersion, platform;
  const PosDeviceInfo(
      {required this.id,
      required this.code,
      required this.name,
      required this.isPrimary,
      required this.isActive,
      this.lastSeen,
      this.lastSync,
      this.appVersion,
      this.platform});

  /// A POS sends a heartbeat every minute; three missed ones means it is not running.
  bool get online => isActive && lastSeen != null && DateTime.now().difference(lastSeen!) < const Duration(minutes: 3);

  factory PosDeviceInfo.fromJson(Map<String, dynamic> j) => PosDeviceInfo(
        id: j['id'] as String,
        code: j['device_code'] as String,
        name: j['device_name'] as String? ?? 'Main POS',
        isPrimary: j['is_primary'] == true,
        isActive: j['is_active'] != false,
        lastSeen: DateTime.tryParse(j['last_seen_at'] as String? ?? '')?.toLocal(),
        lastSync: DateTime.tryParse(j['last_sync_at'] as String? ?? '')?.toLocal(),
        appVersion: j['app_version'] as String?,
        platform: j['platform'] as String?,
      );
}

/// Main POS device registry (`bpos.pos_devices`, see supabase_devices_and_config.sql). Registering
/// and heartbeats go through functions that check the caller's outlet access; listing is a plain
/// read the RLS policy limits to the caller's own outlet.
class DeviceApi {
  final String baseUrl, anonKey, accessToken;
  DeviceApi({required this.baseUrl, required this.anonKey, required this.accessToken});

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');
  Map<String, String> get _h => {
        'apikey': anonKey,
        'Authorization': 'Bearer $accessToken',
        'Accept-Profile': 'bpos',
        'Content-Profile': 'bpos',
        'Content-Type': 'application/json',
      };

  Future<dynamic> _rpc(String fn, Map<String, dynamic> body) async {
    final res = await http
        .post(Uri.parse('$_root/rest/v1/rpc/$fn'), headers: _h, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) {
      String msg = plainHttpError(res.statusCode);
      try {
        msg = (jsonDecode(res.body) as Map)['message'] as String? ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  /// Registers this POS on first call, then acts as the heartbeat. Returns whether the device is
  /// still active (a manager can remove it).
  Future<bool> register({
    required String outletCode,
    required String deviceCode,
    required String name,
    String? appVersion,
    String? platform,
    bool synced = false,
  }) async {
    final r = await _rpc('register_pos_device', {
      'p_outlet_code': outletCode,
      'p_device_code': deviceCode,
      'p_device_name': name,
      'p_app_version': appVersion,
      'p_platform': platform,
      'p_synced': synced,
    });
    return (r as Map)['active'] != false;
  }

  Future<List<PosDeviceInfo>> list(String outletId) async {
    final uri = Uri.parse('$_root/rest/v1/pos_devices').replace(queryParameters: {
      'select': 'id,device_code,device_name,is_primary,is_active,last_seen_at,last_sync_at,app_version,platform',
      'outlet_id': 'eq.$outletId',
      'is_active': 'eq.true',
      'order': 'registered_at.asc',
    });
    final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw Exception(plainHttpError(res.statusCode));
    return [for (final r in jsonDecode(res.body) as List) PosDeviceInfo.fromJson(r as Map<String, dynamic>)];
  }

  Future<void> remove(String id) => _rpc('remove_pos_device', {'p_device_id': id});
  Future<void> setPrimary(String id) => _rpc('set_primary_pos_device', {'p_device_id': id});
}
