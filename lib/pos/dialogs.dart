import 'dart:math' as math;
import 'package:flutter/material.dart' hide Thumb;
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

const quickNotes = ['No onions', 'Extra spicy', 'Less oil', 'Pack separately'];

// ---------------- Customise (variants / add-ons) ----------------
Future<OrderLine?> showCustomizeDialog(BuildContext context, MenuItem m, {OrderLine? initial}) {
  String? variant = initial?.variant ?? (m.variants.isNotEmpty ? m.variants.first.name : null);
  final addons = <String>{...?initial?.addons};
  int qty = initial?.qty ?? 1;
  final noteC = TextEditingController(text: initial?.note ?? '');
  OrderLine build() =>
      OrderLine(item: m, variant: variant, addons: addons.toList(), qty: qty, note: noteC.text.trim());

  return showPanelDialog<OrderLine>(context,
      maxWidth: 580,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
            final line = build();
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                child: Row(children: [
                  Thumb(m, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Dot(color: m.veg ? C.green : C.red, square: true),
                      const SizedBox(width: 8),
                      Flexible(child: Text(m.name, style: ts(20, w: w5))),
                    ]),
                    Text(m.cat, style: ts(14, c: C.muted)),
                  ])),
                  RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(ctx)),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (m.variants.isNotEmpty) ...[
                      Row(children: [Text('Choose size', style: ts(15, w: w5)), const Spacer(), const Label('Required')]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final v in m.variants)
                          _variantTile(v, v.name == variant, () => set(() => variant = v.name)),
                      ]),
                      const SizedBox(height: 22),
                    ],
                    if (m.addons.isNotEmpty) ...[
                      Row(children: [Text('Add-ons', style: ts(15, w: w5)), const Spacer(), Label('Optional · ${addons.length} selected')]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final a in m.addons)
                          _addonTile(a, addons.contains(a.name),
                              () => set(() => addons.contains(a.name) ? addons.remove(a.name) : addons.add(a.name))),
                      ]),
                      const SizedBox(height: 22),
                    ],
                    Text('Kitchen note', style: ts(15, w: w5)),
                    const SizedBox(height: 8),
                    TextField(controller: noteC, decoration: const InputDecoration(hintText: 'e.g. Extra spicy, sauce on side')),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final q in quickNotes)
                        ActionChip(
                            label: Text(q),
                            onPressed: () => set(() => noteC.text = noteC.text.isEmpty ? q : '${noteC.text}, $q')),
                    ]),
                  ]),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (line.optText.isNotEmpty) ...[Text(line.optText, style: ts(13, c: C.ink2)), const SizedBox(height: 10)],
                  Row(children: [
                    QtyStepper(value: qty, size: 44, onDec: qty > 1 ? () => set(() => qty--) : null, onInc: () => set(() => qty++)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Btn('${initial != null ? 'Update' : 'Add to order'} · ${inr(line.total)}',
                            expand: true, height: 54, onTap: () => Navigator.pop(ctx, build()))),
                  ]),
                ]),
              ),
            ]);
          }));
}

Widget _variantTile(Variant v, bool on, VoidCallback onTap) => Material(
      color: on ? Colors.white : C.soft2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 150,
          height: 76,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? C.ink : C.line, width: on ? 2 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: on ? C.ink : C.faint),
              const SizedBox(width: 8),
              Flexible(child: Text(v.name, overflow: TextOverflow.ellipsis, style: ts(15, w: w5))),
            ]),
            Padding(padding: const EdgeInsets.only(left: 26), child: Text(inr(v.price), style: ts(15, w: w6))),
          ]),
        ),
      ),
    );

Widget _addonTile(Addon a, bool on, VoidCallback onTap) => Material(
      color: on ? const Color(0xFFEEF6FE) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 240,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? C.sky : C.line)),
          child: Row(children: [
            Icon(on ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: on ? C.sky : C.faint),
            const SizedBox(width: 10),
            Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis, style: ts(15, w: w5))),
            Text('+ ${inr(a.price)}', style: ts(14, c: const Color(0xFF6B6B6B))),
          ]),
        ),
      ),
    );

// ---------------- Edit qty / note for simple items ----------------
Future<OrderLine?> showNoteDialog(BuildContext context, OrderLine l) {
  int qty = l.qty;
  final c = TextEditingController(text: l.note);
  return showPanelDialog<OrderLine>(context,
      maxWidth: 440,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Edit item', style: ts(20, w: w5)),
                  const SizedBox(height: 4),
                  Text('${l.item.name} · ${inr(l.unit)} each', style: ts(14, c: C.muted)),
                  const SizedBox(height: 18),
                  Text('Quantity', style: ts(14, w: w5)),
                  const SizedBox(height: 8),
                  QtyStepper(value: qty, onDec: qty > 1 ? () => set(() => qty--) : null, onInc: () => set(() => qty++)),
                  const SizedBox(height: 18),
                  Text('Kitchen note', style: ts(14, w: w5)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final q in quickNotes)
                      ActionChip(label: Text(q), onPressed: () => set(() => c.text = c.text.isEmpty ? q : '${c.text}, $q')),
                  ]),
                  const SizedBox(height: 8),
                  TextField(controller: c, maxLines: 3, decoration: const InputDecoration(hintText: 'e.g. No onions, extra spicy')),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Btn.outline('Cancel', height: 44, onTap: () => Navigator.pop(ctx)),
                    const SizedBox(width: 10),
                    Btn('Save changes',
                        height: 44,
                        onTap: () => Navigator.pop(
                            ctx,
                            l.copy()
                              ..qty = qty
                              ..note = c.text.trim())),
                  ]),
                ]),
              )));
}

// ---------------- Long-press: item availability & stock ----------------
Future<void> showItemManage(BuildContext context, MenuItem m, {VoidCallback? onAdd}) => showPanelDialog(context,
    maxWidth: 440,
    builder: (ctx) {
      final s = StoreScope.of(ctx);
      final reason = s.offReason(m);
      final catOff = s.catOff.contains(m.cat);
      final on = !s.itemOff.contains(m.id);
      final st = s.stock[m.id];
      final stockSub = st == null
          ? 'Not tracked · unlimited'
          : st == 0
              ? 'Sold out · hidden from orders'
              : '$st ${st == 1 ? 'portion' : 'portions'} remaining';
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 200,
            decoration: BoxDecoration(color: const Color(0xFFECECEC), borderRadius: BorderRadius.circular(20)),
            child: Stack(children: [
              Center(child: Opacity(opacity: reason != null ? .45 : 1, child: Thumb(m, size: 104, radius: 30))),
              Positioned(
                  top: 14,
                  left: 14,
                  child: Wrap(spacing: 8, children: [
                    Pill(m.cat,
                        bg: Colors.white,
                        size: 13,
                        pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        leading: Dot(color: m.veg ? C.green : C.red, square: true)),
                    if (m.bestseller)
                      const Pill('★ Bestseller',
                          bg: C.amber, fg: Colors.white, size: 13, pad: EdgeInsets.symmetric(horizontal: 12, vertical: 7)),
                  ])),
              if (reason != null)
                Positioned(
                    top: 14,
                    right: 14,
                    child: Pill(reason,
                        bg: C.ink, fg: Colors.white, size: 13, pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 7))),
            ]),
          ),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: ts(22, w: w5, h: 1.25)),
              const SizedBox(height: 4),
              Text(m.desc.isEmpty ? m.cat : m.desc, style: ts(15, c: C.muted, h: 1.45)),
            ])),
            const SizedBox(width: 12),
            Pill('${m.variants.isNotEmpty ? 'from ' : ''}${inr(m.fromPrice)}',
                bg: Colors.white, border: C.line, size: 18, weight: w6, pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Current stock', style: ts(17, w: w5)),
              const SizedBox(height: 3),
              Text(stockSub,
                  style: ts(14, c: st == 0 ? C.redInk : (st != null && st <= 5 ? C.amberInk : C.muted))),
              if (st != null)
                GestureDetector(
                    onTap: () => s.setStock(m.id, null),
                    child: Padding(
                        padding: const EdgeInsets.only(top: 4), child: Text('Set unlimited', style: ts(13, c: C.blueDeep)))),
            ])),
            RoundIcon(Icons.remove, onTap: st != null && st > 0 ? () => s.setStock(m.id, st - 1) : null),
            SizedBox(width: 44, child: Text(st?.toString() ?? '∞', textAlign: TextAlign.center, style: ts(19, w: w5))),
            RoundIcon(Icons.add, onTap: () => s.setStock(m.id, (st ?? 9) + 1)),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(catOff ? 'Category is off' : (on ? 'Show on menu' : 'Turned off'), style: ts(17, w: w5)),
              const SizedBox(height: 3),
              Text(
                  catOff
                      ? 'Turn on ${m.cat} to enable this item'
                      : (on ? 'Available for new orders' : 'Hidden from new orders'),
                  style: ts(14, c: C.muted)),
            ])),
            Toggle(
                value: on && !catOff,
                onChanged: catOff
                    ? null
                    : (v) {
                        s.setItemOn(m.id, v);
                        toast(ctx, '${m.name} ${v ? 'is back on' : 'turned off'}');
                      }),
          ]),
          const SizedBox(height: 24),
          Row(children: [
            RoundIcon(Icons.edit_outlined,
                size: 56, onTap: () => toast(ctx, 'Menu editing opens in the back office'), tooltip: 'Edit item'),
            const SizedBox(width: 10),
            Expanded(
                child: Btn(reason != null ? 'Unavailable' : 'Add to order  →',
                    bg: C.sky,
                    height: 56,
                    fontSize: 17,
                    expand: true,
                    onTap: reason != null
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            onAdd?.call();
                          })),
          ]),
        ]),
      );
    });

// ---------------- Long-press: category on/off ----------------
Future<void> showCategoryManage(BuildContext context, String c, {void Function(MenuItem)? onAdd}) => showPanelDialog(context,
    maxWidth: 440,
    builder: (ctx) {
      final s = StoreScope.of(ctx);
      final on = !s.catOff.contains(c);
      final items = s.itemsIn(c);
      final offN = items.where((m) => s.offReason(m) != null).length;
      final color = on ? colorForCategory(c).$1 : const Color(0xFFA8A8A8);
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 128,
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0x38FFFFFF),
                    child: Text(c[0], style: ts(19, w: w6, c: Colors.white))),
                const Spacer(),
                RoundIcon(Icons.close,
                    size: 38, bg: const Color(0x38FFFFFF), fg: Colors.white, border: null, onTap: () => Navigator.pop(ctx)),
              ]),
              Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
                Text(c, style: ts(24, w: w5, c: Colors.white)),
                Text('${items.length} items · ${on ? (offN > 0 ? '$offN unavailable' : 'all available') : 'category off'}',
                    style: ts(14, c: Colors.white)),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(on ? 'Show category' : 'Category turned off', style: ts(17, w: w5)),
              const SizedBox(height: 3),
              Text(on ? 'Items in $c can be ordered' : 'All ${items.length} items hidden from new orders',
                  style: ts(14, c: C.muted)),
            ])),
            Toggle(value: on, onChanged: (v) => s.setCatOn(c, v)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Label('Items'),
            const Spacer(),
            TextButton(onPressed: () => s.allItemsOn(c), child: const Text('Turn all on')),
          ]),
          Flexible(
            child: Opacity(
              opacity: on ? 1 : .5,
              child: ListView(shrinkWrap: true, children: [
                for (final m in items)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.soft))),
                    child: Row(children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            showItemManage(context, m, onAdd: onAdd == null ? null : () => onAdd(m));
                          },
                          child: Row(children: [
                            Thumb(m, size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Dot(color: m.veg ? C.green : C.red, square: true, size: 7),
                                const SizedBox(width: 6),
                                Flexible(child: Text(m.name, overflow: TextOverflow.ellipsis, style: ts(15, w: w5))),
                              ]),
                              Text(
                                  '${inr(m.fromPrice)}${s.stock[m.id] == 0 ? ' · Sold out' : s.stock[m.id] != null ? ' · ${s.stock[m.id]} left' : ''}',
                                  style: ts(13, c: s.stock[m.id] == 0 ? C.redInk : C.muted)),
                            ])),
                          ]),
                        ),
                      ),
                      Toggle(scale: .8, value: !s.itemOff.contains(m.id), onChanged: on ? (v) => s.setItemOn(m.id, v) : null),
                    ]),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Btn('Done', bg: C.sky, height: 56, fontSize: 17, expand: true, onTap: () => Navigator.pop(ctx)),
        ]),
      );
    });

// ---------------- Table picker (seat or pick party) ----------------
Future<(String, String)?> showTablePicker(BuildContext context) {
  String? focus;
  int pax = 2;
  return showPanelDialog<(String, String)>(context,
      maxWidth: 680,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
            final s = StoreScope.of(ctx);
            if (focus != null) {
              final t = s.table(focus!);
              pax = math.max(1, math.min(pax, t.free));
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(children: [
                    RoundIcon(Icons.arrow_back, size: 40, onTap: () => set(() => focus = null)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Table ${t.id}', style: ts(20, w: w5)),
                      Text('${t.floor} · ${t.seats} seats · ${t.free} free', style: ts(13, c: C.muted)),
                    ])),
                    RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(ctx)),
                  ]),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (t.parties.isNotEmpty) ...[
                        const Label('Seated parties'),
                        const SizedBox(height: 8),
                        for (var i = 0; i < t.parties.length; i++)
                          Builder(builder: (_) {
                            final p = t.parties[i];
                            final o = s.orderOfParty(t, p);
                            final billed = o?.billed == true;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                              decoration:
                                  BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
                              child: Row(children: [
                                Dot(color: billed ? C.amber : partyColors[i % partyColors.length], size: 10),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.partyLabel(t, p.key), style: ts(16, w: w5)),
                                  Text(
                                      '${p.pax} pax · ${elapsed(p.seatedAt)}${o != null && o.lines.isNotEmpty ? ' · ${inr(o.total)}' : ''}',
                                      style: ts(13, c: C.muted)),
                                ])),
                                billed
                                    ? const Pill('Billing', bg: C.amberTint, fg: C.amberInk)
                                    : Btn('Select', height: 40, bg: C.ink, onTap: () => Navigator.pop(ctx, (t.id, p.key))),
                              ]),
                            );
                          }),
                        const SizedBox(height: 10),
                      ],
                      if (t.free > 0) ...[
                        Label(t.parties.isEmpty ? 'How many people?' : 'Seat another party'),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (var n = 1; n <= t.free; n++) Choice('$n', on: n == pax, onTap: () => set(() => pax = n)),
                        ]),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: C.skyTint, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                              t.free - pax == 0
                                  ? (t.parties.isEmpty ? 'Whole table for this party' : 'Table will be full')
                                  : '${t.free - pax} seat${t.free - pax == 1 ? '' : 's'} stay open to share',
                              style: ts(13, c: C.skyInk)),
                        ),
                        const SizedBox(height: 12),
                        Btn('Seat $pax & select', expand: true, onTap: () {
                          final p = s.seatParty(t, pax);
                          Navigator.pop(ctx, (t.id, p.key));
                        }),
                      ] else
                        Text('All seats taken', textAlign: TextAlign.center, style: ts(14, c: C.muted)),
                    ]),
                  ),
                ),
              ]);
            }
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
                child: Row(children: [
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Select table', style: ts(20, w: w5)),
                    Text('Pick a running party or seat new guests on free seats', style: ts(13, c: C.muted)),
                  ])),
                  RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(ctx)),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final f in Store.floors) ...[
                      Label(f),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final t in s.tablesOn(f)) _pickTile(s, t, () => set(() => focus = t.id)),
                      ]),
                      const SizedBox(height: 18),
                    ],
                  ]),
                ),
              ),
            ]);
          }));
}

Widget _pickTile(Store s, TableModel t, VoidCallback onTap) {
  final billed = t.parties.isNotEmpty && t.parties.every((p) => s.orderOfParty(t, p)?.billed == true);
  final shared = t.parties.length > 1 || (t.parties.isNotEmpty && t.free > 0);
  final (bg, fg, dot, info) = t.parties.isEmpty
      ? (t.reservedFor != null
          ? (C.greenTint, C.greenInk, C.green, 'Reserved ${t.reservedFor}')
          : (Colors.white, C.ink, const Color(0xFFD6D6D6), '${t.seats} seats'))
      : billed
          ? (const Color(0xFFFCF3E2), const Color(0xFF8A5A08), C.amber, 'Billing')
          : shared
              ? (C.skyTint, C.skyInk, C.sky, '${t.parties.length} parties · ${t.free} free')
              : (C.sky, Colors.white, Colors.white, 'Occupied');
  return Material(
    color: bg,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 118,
        height: 74,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [Text(t.id, style: ts(18, w: w6, c: fg)), const Spacer(), Dot(color: dot)]),
          Text(info, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: fg)),
        ]),
      ),
    ),
  );
}
