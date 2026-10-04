import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models.dart';

enum BillSyncState { pending, synced, failed }

/// Where a settled order's push to Supabase currently stands — shown on the
/// Settings → Settled bills screen (see lib/pos/settled_bills_screen.dart).
class BillSyncStatus {
  final BillSyncState state;
  final int attempts;
  final String? lastError;
  const BillSyncStatus(this.state, {this.attempts = 0, this.lastError});
}

class BillSyncException implements Exception {
  final String message;
  final int? statusCode;
  BillSyncException(this.message, {this.statusCode});

  /// Worth retrying later (network trouble, server hiccup, rate limit) vs one
  /// that will fail the same way every time (permission denied, bad data) —
  /// the latter should stop being retried instead of looping forever.
  bool get retryable => statusCode == null || statusCode! >= 500 || statusCode == 408 || statusCode == 429;

  @override
  String toString() => message;
}

/// A stable, UUID-shaped id derived from [seed] — not random, so pushing the
/// same order twice (a retry after a dropped connection, say) always mints the
/// same remote row ids. That makes every insert below naturally idempotent via
/// `Prefer: resolution=merge-duplicates`, with no need to persist which rows a
/// partially-completed push already created.
String _deterministicUuid(String seed) {
  final b = md5.convert(utf8.encode(seed)).bytes.toList();
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int s, int e) => b.sublist(s, e).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Pushes one settled dine-in order (table session → party → order → order
/// items → bill → bill items → payments) to the `bpos` schema. Sibling to
/// [BackofficeApi] (same host, same schema) but — like [SupabaseAuthApi] —
/// every request carries the signed-in user's own access token rather than
/// the anon key, so the RLS policies in supabase_orders_bills_payments_rls.sql
/// apply per-user as designed.
class BillSyncApi {
  final String baseUrl;
  final String anonKey;
  final String accessToken;
  BillSyncApi({required this.baseUrl, required this.anonKey, required this.accessToken});

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _writeHeaders => {
        'apikey': anonKey,
        'Authorization': 'Bearer $accessToken',
        'Accept-Profile': 'bpos',
        'Content-Profile': 'bpos',
        'Content-Type': 'application/json',
        // Every row's id is client-supplied (see [_deterministicUuid]), so a
        // retried insert for a row already created is a safe no-op.
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      };

  Map<String, String> get _readHeaders =>
      {'apikey': anonKey, 'Authorization': 'Bearer $accessToken', 'Accept-Profile': 'bpos'};

  Future<void> _post(String path, Map<String, dynamic> row) async {
    final res = await http
        .post(Uri.parse('$_root/rest/v1/$path'), headers: _writeHeaders, body: jsonEncode(row))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) {
      throw BillSyncException('$path failed (${res.statusCode}): ${res.body}', statusCode: res.statusCode);
    }
  }

  Future<List<dynamic>> _get(String path, Map<String, String> qp) async {
    final uri = Uri.parse('$_root/rest/v1/$path').replace(queryParameters: qp);
    final res = await http.get(uri, headers: _readHeaders).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) {
      throw BillSyncException('$path failed (${res.statusCode}): ${res.body}', statusCode: res.statusCode);
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  /// Outlet's configured payment methods, name (lowercased) → id.
  /// [Payment.method] on a local order ("Cash", "UPI", …) is matched against
  /// this to satisfy `payments.payment_method_id`, a required FK.
  Future<Map<String, String>> fetchPaymentMethodIds(String outletId) async {
    final rows = await _get('payment_methods', {'select': 'id,name', 'outlet_id': 'eq.$outletId', 'is_active': 'eq.true'});
    return {for (final r in rows) (r['name'] as String).toLowerCase(): r['id'] as String};
  }

  /// Pushes [o] (already settled locally) to Supabase. [o.id] seeds every
  /// remote id minted here (see [_deterministicUuid]) and [paymentMethodIds]
  /// must already have an entry for every distinct [Payment.method] on [o] —
  /// the caller resolves that (and fails the order clearly if one's missing)
  /// before calling this, since a bad payment-method match should stop the
  /// push rather than silently drop a payment.
  Future<void> pushSettledOrder(
    Order o, {
    required String outletId,
    required String tableRemoteId,
    required Map<String, String> paymentMethodIds,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final seed = 'bpos-order-${o.id}';
    final tableSessionId = _deterministicUuid('$seed:table_session');
    final partyId = _deterministicUuid('$seed:party');
    final orderId = _deterministicUuid('$seed:order');
    final billId = _deterministicUuid('$seed:bill');

    await _post('table_sessions', {
      'id': tableSessionId,
      'outlet_id': outletId,
      'table_id': tableRemoteId,
      'status': 'closed',
      'opened_at': o.at.toUtc().toIso8601String(),
      'closed_at': now,
    });

    await _post('parties', {
      'id': partyId,
      'outlet_id': outletId,
      'table_session_id': tableSessionId,
      'party_number': o.id,
      'guest_count': o.pax,
      'status': 'closed',
      'closed_at': now,
    });

    await _post('orders', {
      'id': orderId,
      'outlet_id': outletId,
      'table_session_id': tableSessionId,
      'party_id': partyId,
      'order_number': o.id,
      'status': 'settled',
      'created_at': o.at.toUtc().toIso8601String(),
    });

    final liveLines = o.liveLines;
    for (var i = 0; i < liveLines.length; i++) {
      final l = liveLines[i];
      await _post('order_items', {
        'id': _deterministicUuid('$seed:order_item:$i'),
        'order_id': orderId,
        // product_id/variant_id are deliberately left unset: a renamed/deleted
        // product since this order was placed must not FK-fail a historical
        // sync. The snapshot fields below are the source of truth, same as
        // the local OrderLine model already treats them (CLAUDE.md §16/§26).
        'product_code_snapshot': l.item.code,
        'product_name_snapshot': l.item.name,
        'variant_name_snapshot': l.variant,
        'unit_price': l.unitPrice,
        'quantity': l.activeQty,
        'line_total': l.total,
        'status': 'active',
      });
    }

    await _post('bills', {
      'id': billId,
      'outlet_id': outletId,
      'table_session_id': tableSessionId,
      'party_id': partyId,
      'bill_number': o.id,
      'status': 'paid',
      'subtotal': o.subtotal,
      'tax_amount': o.tax,
      'grand_total': o.total,
      'paid_amount': o.paid,
      'balance_amount': o.total - o.paid,
      'paid_at': now,
    });

    for (var i = 0; i < liveLines.length; i++) {
      final l = liveLines[i];
      await _post('bill_items', {
        'id': _deterministicUuid('$seed:bill_item:$i'),
        'bill_id': billId,
        'order_item_id': _deterministicUuid('$seed:order_item:$i'),
        'product_name_snapshot': l.item.name,
        'variant_name_snapshot': l.variant,
        'unit_price': l.unitPrice,
        'quantity': l.activeQty,
        'line_total': l.total,
      });
    }

    for (var i = 0; i < o.payments.length; i++) {
      final p = o.payments[i];
      final methodId = paymentMethodIds[p.method.toLowerCase()];
      if (methodId == null) {
        throw BillSyncException('No outlet payment method configured matching "${p.method}"', statusCode: 422);
      }
      await _post('payments', {
        'id': _deterministicUuid('$seed:payment:$i'),
        'outlet_id': outletId,
        'bill_id': billId,
        'payment_method_id': methodId,
        'amount': p.amount,
      });
    }
  }
}
