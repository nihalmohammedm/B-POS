import 'dart:convert';
import 'package:http/http.dart' as http;
import '../plain_error.dart';

/// Saves the outlet's tables (setup + floor-plan layout) to `bpos.tables`, see
/// supabase_tables_config.sql. Uses the signed-in user's token: saving needs settings.manage.
/// Rows are keyed by (outlet_id, table_number), so re-adding a removed table revives it.
class TablesApi {
  final String baseUrl, anonKey, accessToken;
  TablesApi({required this.baseUrl, required this.anonKey, required this.accessToken});

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<void> upsert(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final res = await http
        .post(Uri.parse('$_root/rest/v1/tables?on_conflict=outlet_id,table_number'),
            headers: {
              'apikey': anonKey,
              'Authorization': 'Bearer $accessToken',
              'Accept-Profile': 'bpos',
              'Content-Profile': 'bpos',
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: jsonEncode(rows))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) {
      String msg = plainHttpError(res.statusCode);
      try {
        final m = (jsonDecode(res.body) as Map)['message'] as String?;
        if (m != null) msg = '$msg ($m)';
      } catch (_) {}
      throw Exception(msg);
    }
  }
}
