import 'dart:convert';
import 'package:http/http.dart' as http;

class WebOrderLine {
  final String? productId;
  final String name;
  final String? variant;
  final List<String> addons;
  final int qty;
  final double unitPrice;
  const WebOrderLine(
      {required this.productId, required this.name, this.variant, this.addons = const [], required this.qty, required this.unitPrice});
}

/// A customer's order from the public web menu, waiting for the counter to accept it
/// (bpos.web_orders). It only becomes a real [Order] + KOT when accepted.
class WebOrder {
  final String id;
  final int number;
  final bool dineIn;
  final String customer, phone, table, notes;
  final DateTime at;
  final List<WebOrderLine> lines;
  const WebOrder(
      {required this.id,
      required this.number,
      required this.dineIn,
      required this.customer,
      required this.phone,
      required this.table,
      required this.notes,
      required this.at,
      required this.lines});

  double get total => lines.fold(0, (a, l) => a + l.unitPrice * l.qty);

  factory WebOrder.fromJson(Map<String, dynamic> j) => WebOrder(
        id: j['id'] as String,
        number: (j['order_number'] as num).toInt(),
        dineIn: j['order_type'] == 'dine_in',
        customer: j['customer_name'] as String? ?? '',
        phone: j['customer_phone'] as String? ?? '',
        table: j['table_label'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        at: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        lines: [
          for (final i in (j['web_order_items'] as List? ?? const []))
            WebOrderLine(
              productId: i['product_id'] as String?,
              name: i['item_name'] as String,
              variant: i['variant_name'] as String?,
              addons: [for (final m in (i['modifiers'] as List? ?? const [])) m['name'] as String],
              qty: (i['quantity'] as num).toInt(),
              unitPrice: (i['unit_price'] as num).toDouble(),
            ),
        ],
      );
}

class WebOrderException implements Exception {
  final String message;
  WebOrderException(this.message);
  @override
  String toString() => message;
}

/// Staff side of web ordering: reads the pending inbox and accepts/rejects, using the signed-in
/// user's own access token so the web_orders RLS policies (supabase_web_menu.sql) apply.
class WebOrderApi {
  final String baseUrl, anonKey, accessToken;
  WebOrderApi({required this.baseUrl, required this.anonKey, required this.accessToken});

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');
  Map<String, String> get _h => {
        'apikey': anonKey,
        'Authorization': 'Bearer $accessToken',
        'Accept-Profile': 'bpos',
        'Content-Profile': 'bpos',
        'Content-Type': 'application/json',
      };

  Future<List<WebOrder>> fetchPending(String outletId) async {
    final uri = Uri.parse('$_root/rest/v1/web_orders').replace(queryParameters: {
      'select': '*,web_order_items(*)',
      'outlet_id': 'eq.$outletId',
      'status': 'eq.pending',
      'order': 'created_at.asc',
    });
    final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw WebOrderException('web_orders failed (${res.statusCode}): ${res.body}');
    return [for (final r in jsonDecode(res.body) as List) WebOrder.fromJson(r as Map<String, dynamic>)];
  }

  /// Marks a still-pending order accepted/rejected. The `status=eq.pending` filter makes a double
  /// decision (two counters tapping at once) a no-op; returns false if someone else got there first.
  /// decided_by/decided_at are stamped server-side by a trigger, so they can't be forged from here.
  Future<bool> decide(String id, {required bool accept, String? reason}) async {
    final uri = Uri.parse('$_root/rest/v1/web_orders').replace(queryParameters: {'id': 'eq.$id', 'status': 'eq.pending'});
    final res = await http
        .patch(uri,
            headers: {..._h, 'Prefer': 'return=representation'},
            body: jsonEncode({
              'status': accept ? 'accepted' : 'rejected',
              'reject_reason': accept ? null : reason,
            }))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw WebOrderException('Could not update web order (${res.statusCode}): ${res.body}');
    return (jsonDecode(res.body) as List).isNotEmpty;
  }

  /// Whether the public menu is switched on for [outletCode]. Outlets are readable with the anon key
  /// (the same way menu sync reads them), so this works before a staff session exists.
  Future<bool> fetchEnabled(String outletCode) async {
    final uri = Uri.parse('$_root/rest/v1/outlets')
        .replace(queryParameters: {'select': 'web_menu_enabled', 'code': 'eq.$outletCode', 'limit': '1'});
    final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw WebOrderException('Could not read web menu status (${res.statusCode})');
    final rows = jsonDecode(res.body) as List;
    return rows.isNotEmpty && rows.first['web_menu_enabled'] == true;
  }

  Future<void> setEnabled(String outletCode, bool enabled) async {
    final res = await http
        .post(Uri.parse('$_root/rest/v1/rpc/set_web_menu_enabled'),
            headers: _h, body: jsonEncode({'p_outlet_code': outletCode, 'p_enabled': enabled}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) {
      String msg = 'Could not update web menu (${res.statusCode})';
      try {
        msg = (jsonDecode(res.body) as Map)['message'] as String? ?? msg;
      } catch (_) {}
      throw WebOrderException(msg);
    }
  }
}
