import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Today's prices: every item marked "Daily price" on one screen, so a manager can
/// set the day's rates in the morning without opening each item. Saves go to Supabase
/// like any menu edit and reach captains with the next menu push. Orders already
/// taken keep the price they were taken at.
class TodaysPricesScreen extends StatefulWidget {
  const TodaysPricesScreen({super.key});
  @override
  State<TodaysPricesScreen> createState() => _TodaysPricesScreenState();
}

class _TodaysPricesScreenState extends State<TodaysPricesScreen> {
  /// One box per item price (key = item id) or size price (key = item id + size id/name).
  final _boxes = <String, TextEditingController>{};
  var _busy = false;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
  static String _key(MenuItem m, [Variant? v]) => v == null ? m.id : '${m.id}/${v.id ?? v.name}';

  TextEditingController _box(String key, double v) => _boxes.putIfAbsent(key, () => TextEditingController(text: _fmt(v)));

  @override
  void dispose() {
    for (final c in _boxes.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// [m] with the typed prices, or null if nothing changed. Throws on an empty/invalid box.
  MenuItem? _edited(MenuItem m) {
    double read(String key, double was) {
      final c = _boxes[key];
      if (c == null) return was;
      final v = double.tryParse(c.text.trim());
      if (v == null || v < 0) throw FormatException('Check the price for ${m.name}');
      return v;
    }

    if (m.variants.isEmpty) {
      final p = read(_key(m), m.price);
      return p == m.price ? null : _with(m, p, m.variants);
    }
    final vs = [for (final v in m.variants) Variant(v.name, read(_key(m, v), v.price), kotGroup: v.kotGroup, id: v.id)];
    return listEquals(vs, m.variants) ? null : _with(m, vs.first.price, vs);
  }

  MenuItem _with(MenuItem m, double price, List<Variant> vs) => MenuItem(
        id: m.id,
        code: m.code,
        cat: m.cat,
        subCat: m.subCat,
        name: m.name,
        desc: m.desc,
        price: price,
        veg: m.veg,
        bestseller: m.bestseller,
        variants: vs,
        addons: m.addons,
        kitchenNotes: m.kitchenNotes,
        kotGroup: m.kotGroup,
        foodType: m.foodType,
        isMrp: m.isMrp,
        openPrice: m.openPrice,
        dailyPrice: m.dailyPrice,
      );

  Future<void> _save(Store s, List<MenuItem> items) async {
    final List<MenuItem> changed;
    try {
      changed = items.map(_edited).whereType<MenuItem>().toList();
    } on FormatException catch (e) {
      toast(context, e.message, error: true);
      return;
    }
    if (changed.isEmpty) {
      toast(context, 'No prices changed');
      return;
    }
    setState(() => _busy = true);
    final failed = <String>[];
    for (final m in changed) {
      try {
        await s.saveMenuItem(m);
      } catch (e) {
        failed.add('${m.name}: $e');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (failed.isEmpty) {
      toast(context, '${changed.length} ${changed.length == 1 ? 'price' : 'prices'} updated for today');
    } else {
      toast(context, 'Not saved · ${failed.join(' · ')}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final items = [for (final m in s.menu) if (m.dailyPrice) m];
    final canEdit = s.canEditMenu && !_busy;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              RoundIcon(Icons.arrow_back, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Back'),
              const SizedBox(width: 14),
              Expanded(child: Text('Today\'s prices · ${items.length} items', style: ts(22, w: w5))),
              if (items.isNotEmpty && s.canEditMenu)
                Btn(_busy ? 'Saving…' : 'Save prices', icon: _busy ? null : Icons.check, height: 44, onTap: canEdit ? () => _save(s, items) : null),
            ]),
            const SizedBox(height: 8),
            Text(
                s.canEditMenu
                    ? 'New orders use these prices straight away. Orders already taken keep their old price.'
                    : (s.isSignedIn ? 'Your role cannot change prices (needs menu.manage). View only.' : 'Sign in to change prices. View only.'),
                style: ts(13, c: s.canEditMenu ? C.muted : C.amberInk)),
            const SizedBox(height: 10),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('No daily-price items. Turn on "Daily price" for an item in Settings › Menu items.',
                          textAlign: TextAlign.center, style: ts(14, c: C.muted)))
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      Panel(
                        child: Column(children: [
                          for (final (i, m) in items.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _row(m, canEdit),
                          ],
                        ]),
                      ),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(MenuItem m, bool canEdit) {
    Widget box(String key, double v) => SizedBox(
          width: 120,
          child: TextField(
            controller: _box(key, v),
            enabled: canEdit,
            style: ts(17, w: w6),
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(prefixText: '₹ ', isDense: true),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Dot(color: m.type == 'veg' ? C.green : (m.type == 'egg' ? C.amber : C.red), square: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: ts(16, w: w5)),
              Text([m.cat, if (m.code.isNotEmpty) m.code, if (m.openPrice) 'open price · minimum'].join(' · '), style: ts(12, c: C.muted)),
            ]),
          ),
          if (m.variants.isEmpty) box(_key(m), m.price),
        ]),
        for (final v in m.variants)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 8),
            child: Row(children: [
              Expanded(child: Text(v.name, style: ts(14, c: C.ink2))),
              box(_key(m, v), v.price),
            ]),
          ),
      ]),
    );
  }
}
