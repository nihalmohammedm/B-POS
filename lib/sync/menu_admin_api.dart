import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

class MenuAdminException implements Exception {
  final String message;
  final int? statusCode;
  MenuAdminException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Writes menu edits (products, sizes, KOT group) to the `bpos` schema for one
/// outlet. Like [BillSyncApi] every call carries the signed-in user's own token,
/// so the RLS policies in supabase_menu_manage_rls.sql (menu.manage on that
/// outlet) decide whether it is allowed. Sizes are never deleted: a removed size
/// is switched off, so old orders and bills that point at it stay valid.
class MenuAdminApi {
  final String baseUrl;
  final String anonKey;
  final String accessToken;
  final String outletId;
  MenuAdminApi({required this.baseUrl, required this.anonKey, required this.accessToken, required this.outletId});

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> _headers({bool write = false, String prefer = 'return=minimal'}) => {
        'apikey': anonKey,
        'Authorization': 'Bearer $accessToken',
        'Accept-Profile': 'bpos',
        if (write) ...{'Content-Profile': 'bpos', 'Content-Type': 'application/json', 'Prefer': prefer},
      };

  Uri _u(String path, [Map<String, String>? qp]) => Uri.parse('$_root/rest/v1/$path').replace(queryParameters: qp);

  Never _fail(String path, http.Response r) =>
      throw MenuAdminException('$path failed (${r.statusCode}): ${r.body}', statusCode: r.statusCode);

  Future<List<dynamic>> _get(String path, Map<String, String> qp) async {
    final r = await http.get(_u(path, qp), headers: _headers()).timeout(const Duration(seconds: 15));
    if (r.statusCode >= 300) _fail(path, r);
    return jsonDecode(r.body) as List<dynamic>;
  }

  /// PATCH that must hit a row: with RLS a blocked update matches zero rows and
  /// still answers 200, so ask for the rows back and treat none as "not allowed".
  Future<void> _patch(String path, Map<String, String> qp, Map<String, dynamic> body) async {
    final r = await http
        .patch(_u(path, qp), headers: _headers(write: true, prefer: 'return=representation'), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode >= 300) _fail(path, r);
    if ((jsonDecode(r.body) as List).isEmpty) {
      throw MenuAdminException('$path: nothing was changed. You may not have permission to manage this outlet\'s menu.', statusCode: 403);
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(_u(path), headers: _headers(write: true, prefer: 'return=representation'), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode >= 300) _fail(path, r);
    return (jsonDecode(r.body) as List).first as Map<String, dynamic>;
  }

  /// Category id for [name]: a top-level one unless [sub] (a child of something).
  Future<String> _categoryId(String name, {bool sub = false}) async {
    final rows = await _get('categories', {
      'select': 'id,parent_id',
      'outlet_id': 'eq.$outletId',
      'name': 'eq.$name',
      'is_active': 'eq.true',
    });
    for (final c in rows) {
      if ((c['parent_id'] == null) != sub) return c['id'] as String;
    }
    throw MenuAdminException('Category "$name" was not found for this outlet');
  }

  Map<String, dynamic> _productRow(MenuItem m, String categoryId) => {
        'item_code': m.code,
        'name': m.name,
        'description': m.desc,
        'category_id': categoryId,
        'base_price': m.price,
        'has_variants': m.variants.isNotEmpty,
        'type': m.type,
      };

  Future<void> _setKotGroup(String productId, String? groupId) async {
    final d = await http
        .delete(_u('product_kot_groups', {'product_id': 'eq.$productId'}), headers: _headers(write: true))
        .timeout(const Duration(seconds: 15));
    if (d.statusCode >= 300) _fail('product_kot_groups', d);
    if (groupId != null) await _post('product_kot_groups', {'product_id': productId, 'kot_group_id': groupId});
  }

  /// Syncs the sizes of [productId] with [want]: update the ones that have an
  /// id, add new ones, switch off any [before] size that was dropped. Returns
  /// the list with ids filled in.
  Future<List<Variant>> _syncVariants(String productId, List<Variant> want, List<Variant> before) async {
    final keep = {for (final v in want) if (v.id != null) v.id!};
    for (final v in before) {
      if (v.id != null && !keep.contains(v.id)) {
        await _patch('product_variants', {'id': 'eq.${v.id}'}, {'is_active': false});
      }
    }
    final out = <Variant>[];
    for (final (i, v) in want.indexed) {
      final row = {'name': v.name, 'price': v.price, 'display_order': i, 'is_default': i == 0, 'kot_group_id': v.kotGroup};
      if (v.id != null) {
        await _patch('product_variants', {'id': 'eq.${v.id}'}, row..['is_active'] = true);
        out.add(v);
      } else {
        final r = await _post('product_variants', row..['product_id'] = productId..['is_active'] = true);
        out.add(Variant(v.name, v.price, kotGroup: v.kotGroup, id: r['id'] as String));
      }
    }
    return out;
  }

  /// Saves an existing item. [before] is what the POS had, used to know which
  /// sizes were removed and whether the KOT group changed. Returns the item as saved.
  Future<MenuItem> updateItem(MenuItem m, MenuItem before) async {
    final keepsSub = m.subCat.isNotEmpty && m.cat == before.cat && m.subCat == before.subCat;
    final catId = keepsSub ? await _categoryId(m.subCat, sub: true) : await _categoryId(m.cat);
    await _patch('products', {'id': 'eq.${m.id}', 'outlet_id': 'eq.$outletId'}, _productRow(m, catId));
    final variants = await _syncVariants(m.id, m.variants, before.variants);
    if (m.kotGroup != before.kotGroup) await _setKotGroup(m.id, m.kotGroup);
    return _copy(m, m.id, variants, keepsSub ? m.subCat : '');
  }

  /// Adds a new item to the outlet's active menu version.
  Future<MenuItem> createItem(MenuItem m) async {
    final ver = await _get('menu_versions', {'select': 'id', 'outlet_id': 'eq.$outletId', 'status': 'eq.active', 'limit': '1'});
    if (ver.isEmpty) throw MenuAdminException('This outlet has no active menu version to add the item to');
    final catId = await _categoryId(m.cat);
    final last = await _get('products', {
      'select': 'display_order',
      'outlet_id': 'eq.$outletId',
      'menu_version_id': 'eq.${ver.first['id']}',
      'order': 'display_order.desc',
      'limit': '1',
    });
    final next = last.isEmpty ? 0 : ((last.first['display_order'] as num?)?.toInt() ?? 0) + 1;
    final row = _productRow(m, catId)
      ..['outlet_id'] = outletId
      ..['menu_version_id'] = ver.first['id']
      ..['display_order'] = next
      ..['is_active'] = true;
    final r = await _post('products', row);
    final id = r['id'] as String;
    final variants = await _syncVariants(id, m.variants, const []);
    if (m.kotGroup != null) await _setKotGroup(id, m.kotGroup);
    return _copy(m, id, variants, '');
  }

  /// Takes an item off the menu. Kept in the database (inactive) so past
  /// orders, bills and reports still resolve it.
  Future<void> deactivateItem(String productId) =>
      _patch('products', {'id': 'eq.$productId', 'outlet_id': 'eq.$outletId'}, {'is_active': false});

  MenuItem _copy(MenuItem m, String id, List<Variant> variants, String subCat) => MenuItem(
        id: id,
        code: m.code,
        cat: m.cat,
        subCat: subCat,
        name: m.name,
        desc: m.desc,
        price: m.price,
        veg: m.type == 'veg',
        bestseller: m.bestseller,
        variants: variants,
        addons: m.addons,
        kitchenNotes: m.kitchenNotes,
        kotGroup: m.kotGroup,
        foodType: m.type,
      );
}
