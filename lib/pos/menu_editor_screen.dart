import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings › Menu items: browse this outlet's menu and edit it. Every save goes
/// to Supabase first (for this outlet only) and then updates the POS, so the
/// backoffice, web menu and other devices all see the same change.
class MenuEditorScreen extends StatefulWidget {
  const MenuEditorScreen({super.key});
  @override
  State<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

class _MenuEditorScreenState extends State<MenuEditorScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final q = _q.trim().toLowerCase();
    final cats = [
      for (final c in s.categories)
        (c, [for (final m in s.itemsIn(c)) if (q.isEmpty || m.name.toLowerCase().contains(q) || m.code.toLowerCase().contains(q)) m]),
    ].where((e) => e.$2.isNotEmpty).toList();
    final canEdit = s.canEditMenu;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              RoundIcon(Icons.arrow_back, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Back'),
              const SizedBox(width: 14),
              Expanded(child: Text('Menu · ${s.menu.length} items', style: ts(22, w: w5))),
              if (canEdit) Btn('Add item', icon: Icons.add, height: 44, onTap: () => showMenuItemSheet(context, null)),
            ]),
            const SizedBox(height: 12),
            if (!canEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                    s.isSignedIn ? 'Your role cannot edit the menu (needs menu.manage). View only.' : 'Sign in to edit the menu. View only.',
                    style: ts(13, c: C.amberInk)),
              ),
            TextField(
              controller: _search,
              style: ts(15),
              decoration: InputDecoration(
                  hintText: 'Search item name or code',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                                _search.clear();
                                _q = '';
                              }))),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: cats.isEmpty
                  ? Center(child: Text(s.menu.isEmpty ? 'No menu yet. Sync it from Settings › Menu & sync.' : 'Nothing matches', style: ts(14, c: C.muted)))
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      for (final (c, items) in cats) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                          child: Text('$c · ${items.length}', style: ts(15, w: w5, c: C.muted)),
                        ),
                        Panel(
                          child: Column(children: [
                            for (final (i, m) in items.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              _row(s, m, canEdit),
                            ],
                          ]),
                        ),
                      ],
                    ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(Store s, MenuItem m, bool canEdit) {
    final off = s.offReason(m);
    final g = s.kotGroup(m.kotGroup)?.name;
    return InkWell(
      onTap: () => showMenuItemSheet(context, m),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Dot(color: m.type == 'veg' ? C.green : (m.type == 'egg' ? C.amber : C.red), square: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: ts(15, w: w5, c: off != null ? C.muted : C.ink)),
              Text([if (m.code.isNotEmpty) m.code, if (m.variants.isNotEmpty) '${m.variants.length} sizes', if (g != null) g].join(' · '),
                  style: ts(12, c: C.muted)),
            ]),
          ),
          if (off != null) ...[Pill(off, bg: C.soft, size: 11), const SizedBox(width: 8)],
          Text('${m.variants.isNotEmpty ? 'from ' : ''}${inr(m.fromPrice)}', style: ts(15, w: w5)),
          const SizedBox(width: 6),
          Icon(canEdit ? Icons.edit_outlined : Icons.chevron_right, size: 18, color: C.muted),
        ]),
      ),
    );
  }
}

class _SizeRow {
  final String? id;
  final String? kotGroup;
  final TextEditingController name, price;
  _SizeRow(Variant v)
      : id = v.id,
        kotGroup = v.kotGroup,
        name = TextEditingController(text: v.name),
        price = TextEditingController(text: v.price == v.price.roundToDouble() ? v.price.toStringAsFixed(0) : '${v.price}');
  _SizeRow.blank()
      : id = null,
        kotGroup = null,
        name = TextEditingController(),
        price = TextEditingController();
  void dispose() {
    name.dispose();
    price.dispose();
  }
}

/// Edit sheet for one item; [existing] null adds a new one.
Future<void> showMenuItemSheet(BuildContext context, MenuItem? existing) {
  final s = StoreScope.read(context);
  final canEdit = s.canEditMenu;
  final nameC = TextEditingController(text: existing?.name ?? '');
  final codeC = TextEditingController(text: existing?.code ?? '');
  final descC = TextEditingController(text: existing?.desc ?? '');
  final priceC = TextEditingController(
      text: existing == null || existing.price == 0
          ? ''
          : (existing.price == existing.price.roundToDouble() ? existing.price.toStringAsFixed(0) : '${existing.price}'));
  final sizes = [for (final v in existing?.variants ?? const <Variant>[]) _SizeRow(v)];
  var cat = existing?.cat ?? (s.categories.isNotEmpty ? s.categories.first : '');
  var type = existing?.type ?? 'veg';
  String? group = existing?.kotGroup;
  var busy = false;

  return showSheet<void>(context, (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      double? parse(TextEditingController c) => double.tryParse(c.text.trim());
      String? problem() {
        if (nameC.text.trim().isEmpty) return 'Give the item a name';
        if (cat.isEmpty) return 'Pick a category';
        if (sizes.isEmpty && (parse(priceC) ?? -1) < 0) return 'Enter a price';
        for (final r in sizes) {
          if (r.name.text.trim().isEmpty || (parse(r.price) ?? -1) < 0) return 'Every size needs a name and a price';
        }
        return null;
      }

      Future<void> save() async {
        final p = problem();
        if (p != null) {
          toast(ctx, p, error: true);
          return;
        }
        final vs = [for (final r in sizes) Variant(r.name.text.trim(), parse(r.price)!, kotGroup: r.kotGroup, id: r.id)];
        final item = MenuItem(
          id: existing?.id ?? '',
          code: codeC.text.trim(),
          cat: cat,
          subCat: existing?.subCat ?? '',
          name: nameC.text.trim(),
          desc: descC.text.trim(),
          price: vs.isNotEmpty ? vs.first.price : parse(priceC)!,
          veg: type == 'veg',
          bestseller: existing?.bestseller ?? false,
          variants: vs,
          addons: existing?.addons ?? const [],
          kitchenNotes: existing?.kitchenNotes ?? const [],
          kotGroup: group,
          foodType: type,
        );
        set(() => busy = true);
        try {
          await s.saveMenuItem(item);
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) toast(context, '${item.name} saved to the menu');
        } catch (e) {
          set(() => busy = false);
          if (ctx.mounted) toast(ctx, 'Not saved · $e', error: true);
        }
      }

      Future<void> remove() async {
        final ok = await confirmDialog(ctx,
            title: 'Remove ${existing!.name}?',
            body: 'Takes it off the menu for this outlet. Past orders and bills keep it.',
            ok: 'Remove',
            okColor: C.red);
        if (!ok) return;
        set(() => busy = true);
        try {
          await s.removeMenuItem(existing);
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) toast(context, '${existing.name} removed');
        } catch (e) {
          set(() => busy = false);
          if (ctx.mounted) toast(ctx, 'Not removed · $e', error: true);
        }
      }

      final ro = !canEdit || busy;
      const money = TextInputType.numberWithOptions(decimal: true);
      Widget field(String label, TextEditingController c, {String hint = '', TextInputType? kb, int lines = 1}) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Label(label),
              const SizedBox(height: 6),
              TextField(
                  controller: c,
                  enabled: !ro,
                  style: ts(14),
                  keyboardType: kb,
                  minLines: lines,
                  maxLines: lines,
                  inputFormatters: kb == money ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
                  decoration: InputDecoration(hintText: hint),
                  onChanged: (_) => set(() {})),
            ]),
          );

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(existing == null ? 'Add item' : (canEdit ? 'Edit item' : existing.name), style: ts(20, w: w5)),
          const SizedBox(height: 4),
          Text(canEdit ? 'Saved to this outlet\'s menu in Supabase. Past orders keep their old name and price.' : 'View only',
              style: ts(12, c: C.muted)),
          const SizedBox(height: 16),
          field('Name', nameC, hint: 'e.g. Alfaham'),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: field('Item code', codeC, hint: '001')),
            const SizedBox(width: 12),
            Expanded(child: sizes.isEmpty ? field('Price (₹)', priceC, hint: '0', kb: money) : const SizedBox()),
          ]),
          const Label('Category'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: s.categories.contains(cat) ? cat : null,
            items: [for (final c in s.categories) DropdownMenuItem(value: c, child: Text(c, style: ts(14)))],
            onChanged: ro ? null : (v) => set(() => cat = v ?? cat),
          ),
          const SizedBox(height: 14),
          const Label('Type'),
          const SizedBox(height: 6),
          Seg<String>(
              expand: true,
              items: const [('veg', 'Veg'), ('non-veg', 'Non-veg'), ('egg', 'Egg')],
              value: type,
              onChanged: (v) {
                if (!ro) set(() => type = v);
              }),
          const SizedBox(height: 14),
          const Label('KOT group'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: s.kotGroup(group) == null ? null : group,
            items: [
              DropdownMenuItem<String?>(value: null, child: Text('None', style: ts(14, c: C.muted))),
              for (final g in s.kotGroups) DropdownMenuItem<String?>(value: g.id, child: Text(g.name, style: ts(14))),
            ],
            onChanged: ro ? null : (v) => set(() => group = v),
          ),
          const SizedBox(height: 14),
          field('Description', descC, hint: 'Optional', lines: 2),
          Row(children: [
            const Expanded(child: Label('Sizes')),
            if (!ro) Btn.outline('Add size', icon: Icons.add, height: 34, fontSize: 13, onTap: () => set(() => sizes.add(_SizeRow.blank()))),
          ]),
          if (sizes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No sizes: sold at the single price above.', style: ts(12, c: C.muted)),
            ),
          for (final (i, r) in sizes.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: TextField(controller: r.name, enabled: !ro, style: ts(14), decoration: const InputDecoration(hintText: '1 Half'))),
                const SizedBox(width: 10),
                Expanded(
                    flex: 2,
                    child: TextField(
                        controller: r.price,
                        enabled: !ro,
                        style: ts(14),
                        keyboardType: money,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        decoration: const InputDecoration(prefixText: '₹ ', hintText: '0'))),
                IconButton(
                    tooltip: 'Remove size',
                    icon: const Icon(Icons.close),
                    onPressed: ro ? null : () => set(() => sizes.removeAt(i).dispose())),
              ]),
            ),
          const SizedBox(height: 22),
          if (canEdit)
            Row(children: [
              if (existing != null) ...[
                RoundIcon(Icons.delete_outline, size: 52, onTap: busy ? null : remove, tooltip: 'Remove from menu'),
                const SizedBox(width: 10),
              ],
              Expanded(child: Btn(busy ? 'Saving…' : 'Save', icon: busy ? null : Icons.check, expand: true, height: 52, onTap: busy ? null : save)),
            ]),
        ]),
      );
    });
  });
}
