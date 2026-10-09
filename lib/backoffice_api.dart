import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class BackofficeException implements Exception {
  final String message;
  BackofficeException(this.message);
  @override
  String toString() => message;
}

class OutletInfo {
  final String name, address, phone;
  const OutletInfo({this.name = '', this.address = '', this.phone = ''});
}

class BackofficeMenu {
  final List<String> categories;
  final List<MenuItem> items;
  final OutletInfo outlet;
  final List<TableModel> tables;
  final List<KotGroup> kotGroups;
  BackofficeMenu(this.categories, this.items, this.outlet, this.tables, this.kotGroups);
}

/// Talks to the `bpos` schema of a self-hosted Supabase/PostgREST backend.
class BackofficeApi {
  final String baseUrl;
  final String apiKey;
  BackofficeApi({required this.baseUrl, required this.apiKey});

  Uri _u(String path, Map<String, String> qp) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/rest/v1/$path').replace(queryParameters: qp);

  Map<String, String> get _headers => {
        'apikey': apiKey,
        'Authorization': 'Bearer $apiKey',
        'Accept-Profile': 'bpos',
      };

  Future<List<dynamic>> _get(String path, Map<String, String> qp) async {
    final res = await http.get(_u(path, qp), headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw BackofficeException('$path failed (${res.statusCode}): ${res.body}');
    return jsonDecode(res.body) as List<dynamic>;
  }

  /// Pulls the active menu for one outlet: categories, products, their variants and modifiers
  /// (product- and variant-level modifier groups are flattened into a single add-on list per item).
  Future<BackofficeMenu> fetchMenu({required String outletCode}) async {
    final outlets = await _get('outlets', {'select': 'id,name,address,phone', 'code': 'eq.$outletCode', 'limit': '1'});
    if (outlets.isEmpty) throw BackofficeException('No outlet found with code "$outletCode"');
    final outletRow = outlets.first as Map<String, dynamic>;
    final outletId = outletRow['id'] as String;
    final outlet = OutletInfo(
      name: outletRow['name'] as String? ?? '',
      address: outletRow['address'] as String? ?? '',
      phone: outletRow['phone'] as String? ?? '',
    );

    final cats = await _get('categories', {
      'select': 'id,name,display_order,parent_id',
      'outlet_id': 'eq.$outletId',
      'is_active': 'eq.true',
      'order': 'display_order.asc',
    });
    final catNameById = {for (final c in cats) c['id'] as String: c['name'] as String};
    // A category with a `parent_id` is a sub-category (e.g. "Alfaham" under "Grill") — it
    // shows up as a chip inside its parent on the POS, not as its own top-level tile.
    final parentIdByCat = {for (final c in cats) c['id'] as String: c['parent_id'] as String?};
    final categoryNames = [for (final c in cats) if (c['parent_id'] == null) c['name'] as String];

    // No floor/section or shape column exists yet, so every synced table lands in one flat
    // group and its tile shape is inferred from seat count: small tables render as a square,
    // bigger ones as a wider rectangle.
    final tableRows = await _get('tables', {
      'select': 'id,table_number,maximum_occupancy,display_order',
      'outlet_id': 'eq.$outletId',
      'is_active': 'eq.true',
      'order': 'display_order.asc',
    });
    final tables = [
      for (final t in tableRows)
        () {
          final seats = t['maximum_occupancy'] as int;
          final (w, h) = switch (seats) { <= 4 => (1, 1), <= 8 => (2, 1), _ => (2, 2) };
          return TableModel(t['table_number'] as String, 'Tables', seats, w: w, h: h, remoteId: t['id'] as String?);
        }()
    ];

    final groupRows = await _get('kot_groups', {
      'select': 'id,code,name,display_order',
      'outlet_id': 'eq.$outletId',
      'is_active': 'eq.true',
      'order': 'display_order.asc',
    });
    final kotGroups = [
      for (final g in groupRows)
        KotGroup(g['id'] as String, g['code'] as String? ?? '', g['name'] as String, g['display_order'] as int? ?? 0),
    ];
    final activeGroups = {for (final g in kotGroups) g.id};

    final products = await _get('products', {
      'select': '*',
      'outlet_id': 'eq.$outletId',
      'is_active': 'eq.true',
      'order': 'display_order.asc',
    });
    if (products.isEmpty) return BackofficeMenu(categoryNames, [], outlet, tables, kotGroups);
    final productIds = [for (final p in products) p['id'] as String];
    final idsIn = 'in.(${productIds.join(',')})';

    final variants = await _get('product_variants', {
      'select': '*',
      'product_id': idsIn,
      'is_active': 'eq.true',
      'order': 'display_order.asc',
    });
    final variantsByProduct = <String, List<dynamic>>{};
    for (final v in variants) {
      variantsByProduct.putIfAbsent(v['product_id'] as String, () => []).add(v);
    }

    // One group per product; a product mapped to several keeps the first by group order.
    final pkg = await _get('product_kot_groups', {'select': 'product_id,kot_group_id', 'product_id': idsIn});
    final groupOrder = {for (final g in kotGroups) g.id: g.order};
    final groupByProduct = <String, String>{};
    for (final r in pkg) {
      final pid = r['product_id'] as String, gid = r['kot_group_id'] as String;
      if (!activeGroups.contains(gid)) continue;
      final cur = groupByProduct[pid];
      if (cur == null || (groupOrder[gid] ?? 0) < (groupOrder[cur] ?? 0)) groupByProduct[pid] = gid;
    }

    final pmg = await _get('product_modifier_groups', {'select': '*', 'product_id': idsIn});
    final variantIds = [for (final v in variants) v['id'] as String];
    final vmg = variantIds.isEmpty
        ? const <dynamic>[]
        : await _get('variant_modifier_groups', {'select': '*', 'variant_id': 'in.(${variantIds.join(',')})'});

    final groupIds = {
      for (final r in pmg) r['modifier_group_id'] as String,
      for (final r in vmg) r['modifier_group_id'] as String,
    };
    final modsByGroup = <String, List<dynamic>>{};
    if (groupIds.isNotEmpty) {
      final mods = await _get('modifiers', {
        'select': '*',
        'modifier_group_id': 'in.(${groupIds.join(',')})',
        'is_active': 'eq.true',
        'order': 'display_order.asc',
      });
      for (final m in mods) {
        modsByGroup.putIfAbsent(m['modifier_group_id'] as String, () => []).add(m);
      }
    }

    final variantToProduct = {for (final v in variants) v['id'] as String: v['product_id'] as String};
    final groupsByProduct = <String, Set<String>>{};
    for (final r in pmg) {
      groupsByProduct.putIfAbsent(r['product_id'] as String, () => {}).add(r['modifier_group_id'] as String);
    }
    for (final r in vmg) {
      final pid = variantToProduct[r['variant_id']];
      if (pid != null) groupsByProduct.putIfAbsent(pid, () => {}).add(r['modifier_group_id'] as String);
    }

    final items = <MenuItem>[];
    for (final p in products) {
      final pid = p['id'] as String;
      final itemVariants = [
        for (final v in variantsByProduct[pid] ?? const []) Variant(v['name'] as String, (v['price'] as num).toDouble(),
              kotGroup: activeGroups.contains(v['kot_group_id']) ? v['kot_group_id'] as String : null,
              id: v['id'] as String)
      ];
      final itemAddons = <Addon>[];
      for (final gid in groupsByProduct[pid] ?? const <String>{}) {
        for (final m in modsByGroup[gid] ?? const []) {
          itemAddons.add(Addon(m['name'] as String, (m['price'] as num).toDouble()));
        }
      }
      final basePrice = (p['base_price'] as num?)?.toDouble();
      final kitchenNotes = ((p['kitchen_notes'] as String?) ?? '')
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      // A product's category_id may point straight at a sub-category (e.g. "Alfaham");
      // resolve up to its parent for the top-level tile, keeping the leaf as subCat.
      final rawCatId = p['category_id'] as String?;
      final parentId = parentIdByCat[rawCatId];
      items.add(MenuItem(
        id: pid,
        code: p['item_code'] as String? ?? '',
        cat: catNameById[parentId ?? rawCatId] ?? 'Uncategorised',
        subCat: parentId == null ? '' : (catNameById[rawCatId] ?? ''),
        name: p['name'] as String,
        desc: p['description'] as String? ?? '',
        price: basePrice ?? (itemVariants.isNotEmpty ? itemVariants.first.price : 0),
        veg: (p['type'] as String?) == 'veg',
        variants: itemVariants,
        addons: itemAddons,
        kitchenNotes: kitchenNotes,
        kotGroup: groupByProduct[pid],
        foodType: (p['type'] as String?) ?? '',
      ));
    }

    return BackofficeMenu(categoryNames, items, outlet, tables, kotGroups);
  }
}
