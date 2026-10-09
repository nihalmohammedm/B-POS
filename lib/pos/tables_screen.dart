import 'dart:math' as math;
import 'package:flutter/gestures.dart';
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
  bool _editing = false;
  String? _dragId;
  Offset _drag = Offset.zero;
  // The plan's size in cells and its on-screen scale, set while building (used by the drag handlers).
  int _cols = 1, _rows = 1;
  double _scale = 1;

  static const _unitW = 150.0, _unitH = 128.0, _gap = 24.0;

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
          if (floor != null && _editing)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Btn.outline('Reset', height: 44, icon: Icons.restart_alt, onTap: () => _reset(s)),
              const SizedBox(width: 8),
              Btn('Done', height: 44, icon: Icons.check, onTap: () => setState(() => _editing = false)),
            ]),
        ]),
        if (_editing) ...[
          const SizedBox(height: 10),
          Text('Drag a table to move it within the floor. Tables snap to the grid and can\'t overlap. Tap Done when you\'re happy.',
              style: ts(13, c: C.muted)),
        ],
        const SizedBox(height: 16),
        Expanded(
          // Hold the grey area for 3 seconds to start editing the layout (managers/owners only).
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: const Duration(seconds: 3)),
                (r) => r.onLongPress = _editing || floor == null || !s.can('settings.manage')
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        setState(() => _editing = true);
                      },
              ),
            },
            child: Container(
              decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F6), borderRadius: BorderRadius.circular(24), border: Border.all(color: C.line)),
              child: floor == null ? const SizedBox() : _canvas(s, wide),
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

  Future<void> _reset(Store s) async {
    final ok = await confirmDialog(context,
        title: 'Reset the layout?', body: 'Tables on $floor go back to an automatic arrangement.', ok: 'Reset');
    if (ok && mounted) s.resetLayout(floor!);
  }

  /// The floor plan: every table at its saved grid cell. The grid is as many columns and rows as fit
  /// on screen (no scrolling); if the tables need more room than that, the whole plan scales down to fit.
  /// Hold the grey area for 3 seconds to drag tables around; positions persist and menu syncs keep them.
  Widget _canvas(Store s, bool wide) {
    const pw = _unitW + _gap, ph = _unitH + _gap;
    return LayoutBuilder(builder: (c, cons) {
      final availW = math.max(1.0, cons.maxWidth - 48), availH = math.max(1.0, cons.maxHeight - 48);
      final fitCols = math.max(1, ((availW + _gap) / pw).floor()), fitRows = math.max(1, ((availH + _gap) / ph).floor());
      s.placeUnplaced(floor!, fitCols);
      final list = s.tablesOn(floor!)..sort((a, b) => a.id == _dragId ? 1 : b.id == _dragId ? -1 : 0);
      var cols = fitCols, rows = fitRows;
      for (final t in list) {
        cols = math.max(cols, t.gx! + t.w);
        rows = math.max(rows, t.gy! + t.h);
      }
      _cols = cols;
      _rows = rows;
      final cw = cols * pw - _gap, ch = rows * ph - _gap;
      _scale = math.min(1.0, math.min(availW / cw, availH / ch));
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: cw * _scale,
            height: ch * _scale,
            child: FittedBox(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: cw,
                height: ch,
                child: Stack(clipBehavior: Clip.none, children: [
                  if (_editing) Positioned.fill(child: CustomPaint(painter: _GridPainter(cols, rows, _unitW, _unitH, _gap))),
                  for (final t in list)
                    Positioned(
                      // Keyed so the dragged table keeps its own gesture when it is moved to the top of the stack.
                      key: ValueKey(t.id),
                      left: t.gx! * pw + (t.id == _dragId ? _drag.dx : 0),
                      top: t.gy! * ph + (t.id == _dragId ? _drag.dy : 0),
                      child: _editing
                          ? GestureDetector(
                              onPanStart: (_) => setState(() {
                                _dragId = t.id;
                                _drag = Offset.zero;
                                sel = t.id;
                              }),
                              // Deltas arrive in screen pixels; the plan may be scaled down.
                              onPanUpdate: (d) => setState(() => _drag += d.delta / _scale),
                              onPanEnd: (_) => _drop(s, t),
                              onPanCancel: () => setState(() => _dragId = null),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow:
                                      t.id == _dragId ? const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))] : null,
                                ),
                                child: IgnorePointer(child: _tile(s, t, wide)),
                              ),
                            )
                          : _tile(s, t, wide),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }

  void _drop(Store s, TableModel t) {
    const pw = _unitW + _gap, ph = _unitH + _gap;
    final gx = ((t.gx! * pw + _drag.dx) / pw).round(), gy = ((t.gy! * ph + _drag.dy) / ph).round();
    setState(() {
      _dragId = null;
      _drag = Offset.zero;
    });
    s.moveTable(t, gx, gy, cols: _cols, rows: _rows);
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
    final w = _unitW * t.w + _gap * (t.w - 1), h = _unitH * t.h + _gap * (t.h - 1);
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
          if (o.discountAmount > 0)
            SumRow('Discount${o.discountReason == null ? '' : ' · ${o.discountReason}'}', '-${inr(o.discountAmount, decimals: true)}'),
          SumRow('Tax (5%)', inr(o.tax, decimals: true)),
          SumRow('Total', inr(o.total, decimals: true), big: true),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        RoundIcon(Icons.print_outlined, size: 52, onTap: () => printBillFlow(context, o), tooltip: 'Print bill'),
        const SizedBox(width: 10),
        RoundIcon(Icons.print_disabled_outlined, size: 52, onTap: () => settleFlow(context, o, print: false), tooltip: 'Settle without printing'),
        const SizedBox(width: 10),
        RoundIcon(Icons.pause_circle_outline, size: 52, onTap: () => holdBillFlow(context, o), tooltip: 'Hold bill · clear the table'),
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

/// Faint cell outlines behind the tables while the layout is being edited.
class _GridPainter extends CustomPainter {
  final int cols, rows;
  final double cw, ch, gap;
  _GridPainter(this.cols, this.rows, this.cw, this.ch, this.gap);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x0A000000);
    final line = Paint()
      ..color = const Color(0x1F000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final rr = RRect.fromRectAndRadius(Rect.fromLTWH(c * (cw + gap), r * (ch + gap), cw, ch), const Radius.circular(20));
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, line);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => o.cols != cols || o.rows != rows;
}
