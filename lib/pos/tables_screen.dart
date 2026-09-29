import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/keys.dart';
import 'item_amend.dart';
import 'payment.dart';

class TablesScreen extends StatefulWidget {
  final void Function(Order) onAddItems;
  const TablesScreen({super.key, required this.onAddItems});
  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  String? floor;
  String? sel;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final floors = s.floors;
    if (floor == null || !floors.contains(floor)) floor = floors.isEmpty ? null : floors.first;
    if (sel == null && s.tables.isNotEmpty) sel = s.tables.first.id;
    final onFloor = floor == null ? const <TableModel>[] : s.tablesOn(floor!);
    void move(int d) {
      if (onFloor.isEmpty) return;
      final i = onFloor.indexWhere((t) => t.id == sel);
      setState(() => sel = onFloor[(i + d).clamp(0, onFloor.length - 1)].id);
    }

    void stepFloor(int d) {
      if (floors.isEmpty) return;
      final i = floors.indexOf(floor!);
      final f = floors[(i + d) % floors.length];
      final first = s.tablesOn(f);
      setState(() {
        floor = f;
        if (first.isNotEmpty) sel = first.first.id;
      });
    }

    /// Enter: straight into the running order when the table has one party,
    /// otherwise open the table to seat or pick a party.
    void open() {
      if (sel == null) return;
      final t = s.table(sel!);
      if (t.parties.length == 1) {
        final o = s.orderOfParty(t, t.parties.first);
        if (o != null && !o.billed) return widget.onAddItems(o);
      }
      _openDetails(t.id);
    }

    final keys = [
      Hotkey(const SingleActivator(LogicalKeyboardKey.arrowRight), () => move(1)),
      Hotkey(const SingleActivator(LogicalKeyboardKey.arrowDown), () => move(1)),
      Hotkey(const SingleActivator(LogicalKeyboardKey.arrowLeft), () => move(-1)),
      Hotkey(const SingleActivator(LogicalKeyboardKey.arrowUp), () => move(-1)),
      Hotkey(const SingleActivator(LogicalKeyboardKey.pageDown), () => stepFloor(1)),
      Hotkey(const SingleActivator(LogicalKeyboardKey.pageUp), () => stepFloor(-1)),
      Hotkey(const SingleActivator(LogicalKeyboardKey.enter), open),
    ];
    return KeyScope(autofocus: true, keys: keys, child: LayoutBuilder(builder: (c, cons) {
      final wide = cons.maxWidth >= 1000;
      final area = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 14, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Floor', style: ts(22, w: w5)),
          if (floors.isEmpty)
            Text('No tables set up yet', style: ts(14, c: C.muted))
          else
            Seg<String>(items: [for (final f in floors) (f, f)], value: floor!, onChanged: (v) => setState(() => floor = v)),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final (label, color) in const [
                ('Available', Color(0xFFDCDCDC)),
                ('Occupied', C.sky),
                ('Reserved', C.green),
                ('Billing', C.amber),
              ]) ...[
                Dot(color: color, size: 9),
                const SizedBox(width: 6),
                Text(label, style: ts(13)),
                const SizedBox(width: 14),
              ],
              const Icon(Icons.call_split, size: 14, color: C.muted),
              const SizedBox(width: 4),
              Text('Shared', style: ts(13)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6), borderRadius: BorderRadius.circular(24), border: Border.all(color: C.line)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Wrap(spacing: 24, runSpacing: 24, children: [if (floor != null) for (final t in s.tablesOn(floor!)) _tile(s, t, wide)]),
            ),
          ),
        ),
      ]);
      if (!wide) return area;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: area),
        const SizedBox(width: 20),
        SizedBox(
          width: 400,
          child: sel == null
              ? const SizedBox()
              : TableDetails(key: ValueKey(sel), tableId: sel!, onAddItems: widget.onAddItems),
        ),
      ]);
    }));
  }

  void _openDetails(String id) => showPanelDialog(context,
      maxWidth: 440,
      builder: (ctx) => SizedBox(
            height: MediaQuery.of(ctx).size.height * .85,
            child: TableDetails(
                tableId: id,
                onAddItems: (o) {
                  Navigator.pop(ctx);
                  widget.onAddItems(o);
                }),
          ));

  Widget _tile(Store s, TableModel t, bool wide) {
    const unitW = 150.0, unitH = 128.0, gap = 24.0;
    final w = unitW * t.w + gap * (t.w - 1), h = unitH * t.h + gap * (t.h - 1);
    final selected = t.id == sel;
    final seatColors = <Color>[];
    for (var i = 0; i < t.parties.length; i++) {
      final p = t.parties[i];
      final c = s.orderOfParty(t, p)?.billed == true ? C.amber : partyColors[i % partyColors.length];
      for (var j = 0; j < p.pax; j++) {
        seatColors.add(c);
      }
    }
    while (seatColors.length < t.seats) {
      seatColors.add(t.reservedFor != null && t.parties.isEmpty ? C.green : const Color(0xFFE2E2E2));
    }
    final chairs = math.min(t.seats, 12);
    final top = (chairs / 2).ceil();
    Widget chairRow(List<Color> cs) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < cs.length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                    color: cs[i], shape: BoxShape.circle, border: Border.all(color: const Color(0x14000000)))),
            ],
          ],
        );
    final shared = t.parties.length > 1 || (t.parties.isNotEmpty && t.free > 0);
    return GestureDetector(
      onTap: () {
        setState(() => sel = t.id);
        if (!wide) _openDetails(t.id);
      },
      child: SizedBox(
        width: w,
        height: h,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: EdgeInsets.symmetric(horizontal: w * .14), child: chairRow(seatColors.take(top).toList())),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(shared ? 4 : 0),
              decoration: BoxDecoration(
                color: shared ? const Color(0xFFE4E4E4) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? C.ink : Colors.transparent, width: 3),
              ),
              child: _surface(s, t),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
              padding: EdgeInsets.symmetric(horizontal: w * .14),
              child: chairRow(seatColors.skip(top).take(chairs - top).toList())),
        ]),
      ),
    );
  }

  Widget _surface(Store s, TableModel t) {
    if (t.parties.isEmpty) {
      final res = t.reservedFor != null;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: res ? C.green : Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: res ? null : Border.all(color: const Color(0xFFE2E2E2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Pill(t.id, bg: res ? const Color(0x38FFFFFF) : C.soft, fg: res ? Colors.white : C.ink, size: 13),
          Text(res ? 'Reserved ${t.reservedFor}' : '${t.seats} seats', style: ts(12, c: res ? Colors.white : C.muted)),
        ]),
      );
    }
    final parts = <Widget>[];
    for (var i = 0; i < t.parties.length; i++) {
      final p = t.parties[i];
      final o = s.orderOfParty(t, p);
      final billed = o?.billed == true;
      final c = billed ? C.amber : partyColors[i % partyColors.length];
      parts.add(Expanded(
        flex: p.pax,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Pill(s.partyLabel(t, p.key),
                  bg: const Color(0x40FFFFFF), fg: Colors.white, size: 12, pad: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
              const SizedBox(height: 6),
              if (o != null && o.lines.isNotEmpty) Text(inr(o.total), style: ts(13, w: w5, c: Colors.white)),
              Text(billed ? 'Billing' : elapsed(p.seatedAt), style: ts(11, c: Colors.white)),
            ]),
          ),
        ),
      ));
    }
    if (t.free > 0) {
      parts.add(Expanded(
        flex: t.free,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFD6D6D6))),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text('${t.free} free', style: ts(12, c: C.muted))),
        ),
      ));
    }
    final spaced = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 4, height: 4));
      spaced.add(parts[i]);
    }
    return t.h > t.w
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced)
        : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced);
  }
}

class TableDetails extends StatefulWidget {
  final String tableId;
  final void Function(Order) onAddItems;
  const TableDetails({super.key, required this.tableId, required this.onAddItems});
  @override
  State<TableDetails> createState() => _TableDetailsState();
}

class _TableDetailsState extends State<TableDetails> {
  String? selKey;
  int pax = 2;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final t = s.table(widget.tableId);
    if (selKey == null || !t.parties.any((p) => p.key == selKey)) selKey = t.parties.isEmpty ? null : t.parties.first.key;
    final p = selKey == null ? null : s.party(t.id, selKey!);
    final o = p == null ? null : s.orderOfParty(t, p);
    pax = math.max(1, math.min(pax, math.max(1, t.free)));
    final allBilled = t.parties.isNotEmpty && t.parties.every((x) => s.orderOfParty(t, x)?.billed == true);
    final status = t.parties.isEmpty
        ? (t.reservedFor != null ? 'Reserved' : 'Available')
        : allBilled
            ? 'Billing'
            : (t.parties.length > 1 || t.free > 0 ? 'Shared' : 'Occupied');
    final (sBg, sFg) = switch (status) {
      'Billing' => (C.amberTint, C.amberInk),
      'Reserved' => (C.greenTint, C.greenInk),
      'Available' => (C.soft, C.ink2),
      _ => (C.skyTint, C.skyInk),
    };

    return Panel(
      padding: EdgeInsets.zero,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        Row(children: [
          Text('Table ${t.id}', style: ts(22, w: w5)),
          const SizedBox(width: 10),
          Pill(status, bg: sBg, fg: sFg, size: 13),
        ]),
        const SizedBox(height: 4),
        Text(
            '${t.floor} · ${t.seats} seats · ${t.free} free${t.reservedFor != null ? ' · Reserved ${t.reservedFor}' : ''}',
            style: ts(14, c: C.muted)),
        const SizedBox(height: 14),
        _seatMap(s, t),
        if (t.parties.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < t.parties.length; i++) _partyChip(s, t, t.parties[i], i),
          ]),
        ],
        if (p != null) ...[const SizedBox(height: 18), const Divider(height: 1), const SizedBox(height: 16), ..._partySection(s, t, p, o)],
        if (t.free > 0) ...[const SizedBox(height: 18), const Divider(height: 1), const SizedBox(height: 16), ..._seatSection(s, t)],
      ]),
    );
  }

  Widget _seatMap(Store s, TableModel t) {
    final boxes = <Widget>[];
    for (var i = 0; i < t.parties.length; i++) {
      final p = t.parties[i];
      final c = s.orderOfParty(t, p)?.billed == true ? C.amber : partyColors[i % partyColors.length];
      for (var j = 0; j < p.pax; j++) {
        boxes.add(_seat(c, p.key, Colors.white));
      }
    }
    for (var j = 0; j < t.free; j++) {
      boxes.add(_seat(Colors.white, '', C.muted, border: C.faint));
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: C.soft2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
      child: Wrap(spacing: 6, runSpacing: 6, children: boxes),
    );
  }

  Widget _seat(Color c, String t, Color fg, {Color? border}) => Container(
        width: 38,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: c, borderRadius: BorderRadius.circular(10), border: border == null ? null : Border.all(color: border, width: 1.5)),
        child: Text(t, style: ts(13, w: w6, c: fg)),
      );

  Widget _partyChip(Store s, TableModel t, Party p, int i) {
    final on = p.key == selKey;
    final billed = s.orderOfParty(t, p)?.billed == true;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => selKey = p.key),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? C.ink : C.line, width: on ? 2 : 1)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Dot(color: billed ? C.amber : partyColors[i % partyColors.length]),
            const SizedBox(width: 6),
            Text(s.partyLabel(t, p.key), style: ts(15, w: w5)),
            const SizedBox(width: 6),
            Text('${p.pax}p', style: ts(12, c: C.muted)),
          ]),
        ),
      ),
    );
  }

  List<Widget> _partySection(Store s, TableModel t, Party p, Order? o) {
    final label = s.partyLabel(t, p.key);
    final head = Row(children: [
      Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Text(p.key, style: ts(16, w: w5)),
      ),
      const SizedBox(width: 12),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Party $label', style: ts(18, w: w5)),
        Text('Dine in · ${elapsed(p.seatedAt)}', style: ts(14, c: C.muted)),
      ])),
      QtyStepper(
        value: p.pax,
        size: 34,
        suffix: ' pax',
        onDec: p.pax > 1 ? () => s.setPax(t, p, p.pax - 1) : null,
        onInc: t.free > 0 ? () => s.setPax(t, p, p.pax + 1) : null,
      ),
    ]);
    if (o == null || o.liveLines.isEmpty) {
      return [
        head,
        const SizedBox(height: 16),
        Text(o != null && o.lines.isNotEmpty ? 'All items cancelled' : 'No items yet', textAlign: TextAlign.center, style: ts(14, c: C.muted)),
        const SizedBox(height: 14),
        Row(children: [
          Btn.outline('Free seats', onTap: () => s.freeParty(t, p)),
          const SizedBox(width: 10),
          Expanded(child: Btn('Start order', expand: true, onTap: () => widget.onAddItems(s.ensurePartyOrder(t, p)))),
        ]),
      ];
    }
    return [
      head,
      const SizedBox(height: 14),
      if (o.billed)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF8EC), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF0C27A))),
          child: Text('Bill ${o.billNo} printed · awaiting payment', style: ts(14, c: C.amberInk)),
        ),
      const Label('Order items'),
      const SizedBox(height: 8),
      for (final l in o.lines) SentLineRow(o, l),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          const Align(alignment: Alignment.centerLeft, child: Label('Payment summary')),
          const SizedBox(height: 6),
          SumRow('Subtotal (${o.itemCount} items)', inr(o.subtotal, decimals: true)),
          SumRow('Tax (5%)', inr(o.tax, decimals: true)),
          SumRow('Total', inr(o.total, decimals: true), big: true),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        RoundIcon(Icons.print_outlined, size: 52, onTap: () => printBillFlow(context, o), tooltip: 'Print bill'),
        const SizedBox(width: 10),
        Expanded(
          child: o.billed
              ? Btn.outline('Reopen', expand: true, onTap: () => reopenFlow(context, o))
              : Btn.outline('Add items', expand: true, onTap: () => widget.onAddItems(o)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Btn('Settle →', expand: true, onTap: () => settleFlow(context, o))),
      ]),
    ];
  }

  List<Widget> _seatSection(Store s, TableModel t) {
    final left = t.free - pax;
    return [
      Label(t.parties.isEmpty ? 'How many people?' : 'Seat another party'),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var n = 1; n <= t.free; n++) Choice('$n', on: n == pax, onTap: () => setState(() => pax = n)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.skyTint, borderRadius: BorderRadius.circular(12)),
        child: Text(
            left == 0
                ? (t.parties.isEmpty ? 'Whole table for this party' : 'Table will be full')
                : '$left seat${left == 1 ? '' : 's'} stay open to share · up to ${t.parties.length + 1 + left} parties',
            style: ts(13, c: C.skyInk)),
      ),
      const SizedBox(height: 12),
      Btn('Seat $pax & start order', expand: true, onTap: () {
        final np = s.seatParty(t, pax);
        setState(() => selKey = np.key);
        widget.onAddItems(s.ensurePartyOrder(t, np));
      }),
    ];
  }
}
