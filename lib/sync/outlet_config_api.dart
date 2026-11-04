import 'dart:convert';
import 'package:http/http.dart' as http;
import '../plain_error.dart';

/// Outlet-wide POS configuration kept in `bpos.outlet_settings` (see
/// supabase_outlet_config.sql): print layout (with the payment-QR UPI IDs) and meal
/// periods, so every till of an outlet, and a reinstalled one, gets the same setup.
/// Calls carry the signed-in user's token: reading needs outlet access, saving needs
/// settings.manage.
class OutletConfigApi {
  final String baseUrl, anonKey, accessToken;
  OutletConfigApi({required this.baseUrl, required this.anonKey, required this.accessToken});

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Authorization': 'Bearer $accessToken',
        'Accept-Profile': 'bpos',
        'Content-Profile': 'bpos',
        'Content-Type': 'application/json',
      };

  /// The outlet's saved config: `print_layout` (object) and `meal_periods` (list), either
  /// null when never saved. Null overall when the outlet has no settings row yet.
  Future<Map<String, dynamic>?> fetch(String outletId) async {
    final uri = Uri.parse('$_root/rest/v1/outlet_settings')
        .replace(queryParameters: {'select': 'print_layout,meal_periods', 'outlet_id': 'eq.$outletId', 'limit': '1'});
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw Exception(plainHttpError(res.statusCode));
    final rows = jsonDecode(res.body) as List<dynamic>;
    return rows.isEmpty ? null : rows.first as Map<String, dynamic>;
  }

  /// Creates or updates the outlet's row with [fields]; other columns are left alone.
  Future<void> save(String outletId, Map<String, dynamic> fields) async {
    final res = await http
        .post(Uri.parse('$_root/rest/v1/outlet_settings?on_conflict=outlet_id'),
            headers: {..._headers, 'Prefer': 'resolution=merge-duplicates,return=minimal'},
            body: jsonEncode({'outlet_id': outletId, ...fields}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw Exception(plainHttpError(res.statusCode));
  }
}
