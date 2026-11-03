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
    var r = await http
        .patch(_u(path, qp), headers: _headers(write: true, prefer: 'return=representation'), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode >= 300 && _dropMissing(r, body)) {
      // A column's migration (supabase_mrp_items.sql, supabase_variable_pricing.sql) hasn't been run yet: save everything else.
      r = await http
          .patch(_u(path, qp), headers: _headers(write: true, prefer: 'return=representation'), body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    }
    if (r.statusCode >= 300) _fail(path, r);
    if ((jsonDecode(r.body) as List).isEmpty) {
      throw MenuAdminException('$path: nothing was changed. You may not have permission to manage this outlet\'s menu.', statusCode: 403);
    }
  }

  /// Columns added by optional migrations. If the backoffice rejects one as unknown,
  /// it's removed from [body] and true is returned so the write can be retried without it.
  static const _optionalColumns = ['is_mrp', 'is_open_price', 'is_daily_price'];
  bool _dropMissing(http.Response r, Map<String, dynamic> body) {
    final missing = [for (final c in _optionalColumns) if (body.containsKey(c) && r.body.contains(c)) c];
    missing.forEach(body.remove);
    return missing.isNotEmpty;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    var r = await http
        .post(_u(path), headers: _headers(write: true, prefer: 'return=representation'), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode >= 300 && _dropMissing(r, body)) {
      r = await http
          .post(_u(path), headers: _headers(write: true, prefer: 'return=representation'), body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    }
    if (r.statusCode >= 300) _fail(path, r);
    return (jsonDecode(r.body) as List).first as Map<String, dynamic>;
  }

  /// Category id for [name]: a top-level one unless [sub] (a child of something).
  Future<String> _categoryId(String name, {String? parent}) async {
    final rows = await _get('categories', {
      'select': 'id,parent_id',
      'outlet_id': 'eq.$outletId',
      'name': 'eq.$name',
      'is_active': 'eq.true',
    });
    final parentId = parent == null ? null : await _categoryId(parent);
    for (final c in rows) {
      if (c['parent_id'] == parentId) return c['id'] as String;
    }
    throw MenuAdminException('Category "$name" was not found for this outlet');
  }

  /// The category row an item is filed under: its sub-category when it has one.
  Future<String> _filingId(MenuItem m) => m.subCat.isEmpty ? _categoryId(m.cat) : _categoryId(m.subCat, parent: m.cat);

  Map<String, dynamic> _productRow(MenuItem m, String categoryId) => {
        // Codes are unique per menu version (products_menu_version_id_item_code_key); a blank
        // one is sent as null so items without a code don't clash on ''.
        'item_code': m.code.isEmpty ? null : m.code,
        'name': m.name,
        'description': m.desc,
        'category_id': categoryId,
        'base_price': m.price,
        'has_variants': m.variants.isNotEmpty,
        // The database spells it non_veg; the app uses non-veg.
        'type': m.type.replaceAll('-', '_'),
        'is_mrp': m.isMrp,
        'is_open_price': m.openPrice,
        'is_daily_price': m.dailyPrice,
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

  /// Next free numeric code after [codes], zero-padded like the existing ones (001, 002…).
  static String nextCode(Iterable<String> codes) {
    var max = 0, width = 3;
    for (final c in codes) {
      final t = c.trim();
      final n = int.tryParse(t);
      if (n == null || n < 0) continue;
      if (n > max) max = n;
      if (t.length > width) width = t.length;
    }
    return '${max + 1}'.padLeft(width, '0');
  }

  /// Suggested code for a new item: the next number after every code in the active menu
  /// version, removed items included, so it can never clash.
  Future<String> nextItemCode() async {
    final ver = await _get('menu_versions', {'select': 'id', 'outlet_id': 'eq.$outletId', 'status': 'eq.active', 'limit': '1'});
    if (ver.isEmpty) throw MenuAdminException('This outlet has no active menu version');
    final rows = await _get('products', {'select': 'item_code', 'menu_version_id': 'eq.${ver.first['id']}'});
    return nextCode([for (final r in rows) (r['item_code'] as String?) ?? '']);
  }

  /// The other product in [versionId] that already has [code], if any (active or removed).
  Future<Map<String, dynamic>?> _codeOwner(String versionId, String code, {String? except}) async {
    if (code.isEmpty) return null;
    final rows = await _get('products', {
      'select': 'id,name,is_active',
      'menu_version_id': 'eq.$versionId',
      'item_code': 'eq.$code',
      if (except != null) 'id': 'neq.$except',
      'limit': '1',
    });
    return rows.isEmpty ? null : rows.first as Map<String, dynamic>;
  }

  Never _codeTaken(String code, Map<String, dynamic> owner) => throw MenuAdminException(owner['is_active'] == true
      ? 'Item code $code is already used by ${owner['name']}. Use a different code.'
      : 'Item code $code belongs to ${owner['name']}, which was removed from the menu. Use a different code, or add ${owner['name']} again with this code.');

  /// Saves an existing item. [before] is what the POS had, used to know which
  /// sizes were removed and whether the KOT group changed. Returns the item as saved.
  Future<MenuItem> updateItem(MenuItem m, MenuItem before) async {
    if (m.code != before.code && m.code.isNotEmpty) {
      final prod = await _get('products', {'select': 'menu_version_id', 'id': 'eq.${m.id}', 'limit': '1'});
      final ver = prod.isEmpty ? null : prod.first['menu_version_id'] as String?;
      final owner = ver == null ? null : await _codeOwner(ver, m.code, except: m.id);
      if (owner != null) _codeTaken(m.code, owner);
    }
    final catId = await _filingId(m);
    await _patch('products', {'id': 'eq.${m.id}', 'outlet_id': 'eq.$outletId'}, _productRow(m, catId));
    final variants = await _syncVariants(m.id, m.variants, before.variants);
    if (m.kotGroup != before.kotGroup) await _setKotGroup(m.id, m.kotGroup);
    return _copy(m, m.id, variants, m.subCat);
  }

  /// Adds a new item to the outlet's active menu version.
  Future<MenuItem> createItem(MenuItem m) async {
    final ver = await _get('menu_versions', {'select': 'id', 'outlet_id': 'eq.$outletId', 'status': 'eq.active', 'limit': '1'});
    if (ver.isEmpty) throw MenuAdminException('This outlet has no active menu version to add the item to');
    final versionId = ver.first['id'] as String;
    final owner = await _codeOwner(versionId, m.code);
    if (owner != null && owner['is_active'] == true) _codeTaken(m.code, owner);
    final catId = await _filingId(m);
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
      ..['menu_version_id'] = versionId
      ..['display_order'] = next
      ..['is_active'] = true;
    if (owner != null) return _revive(owner['id'] as String, m, row);
    final r = await _post('products', row);
    final id = r['id'] as String;
    final variants = await _syncVariants(id, m.variants, const []);
    if (m.kotGroup != null) await _setKotGroup(id, m.kotGroup);
    return _copy(m, id, variants, m.subCat);
  }

  /// Adding an item whose code belongs to a removed product brings that product back with the
  /// new details instead of inserting a duplicate code. Its old sizes are reused by name, so
  /// past orders that point at them stay valid.
  Future<MenuItem> _revive(String id, MenuItem m, Map<String, dynamic> row) async {
    await _patch('products', {'id': 'eq.$id', 'outlet_id': 'eq.$outletId'}, row);
    final old = await _get('product_variants', {'select': 'id,name,price,kot_group_id', 'product_id': 'eq.$id'});
    final byName = {for (final v in old) (v['name'] as String).trim().toLowerCase(): v['id'] as String};
    final before = [
      for (final v in old) Variant(v['name'] as String, (v['price'] as num).toDouble(), kotGroup: v['kot_group_id'] as String?, id: v['id'] as String)
    ];
    final want = [
      for (final v in m.variants) Variant(v.name, v.price, kotGroup: v.kotGroup, id: v.id ?? byName[v.name.trim().toLowerCase()])
    ];
    final variants = await _syncVariants(id, want, before);
    await _setKotGroup(id, m.kotGroup);
    return _copy(m, id, variants, m.subCat);
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
        isMrp: m.isMrp,
        openPrice: m.openPrice,
        dailyPrice: m.dailyPrice,
      );
}
