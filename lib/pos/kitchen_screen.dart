import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});
  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  OrderType? typeF;
  bool readyTab = false;
  Timer? _t;
  static const warnMin = 10, lateMin = 15;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final all = s.activeKots;
    bool inTab(Kot k) => readyTab ? k.stage == KotStage.ready : k.stage != KotStage.ready;
    OrderType typeOf(Kot k) => s.orderById(k.orderId)!.type;
    final kots = all.where((k) => inTab(k) && (typeF == null || typeOf(k) == typeF)).toList();
    final active = all.where((k) => k.stage != KotStage.ready).toList();
    final now = DateTime.now();
    final avg = active.isEmpty
        ? Duration.zero
        : Duration(seconds: active.fold<int>(0, (a, k) => a + now.difference(k.at).inSeconds) ~/ active.length);
    final lateN = active.where((k) => now.difference(k.at).inMinutes >= lateMin).length;
    int count(OrderType? t) => all.where((k) => inTab(k) && (t == null || typeOf(k) == t)).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Seg<OrderType?>(
          height: 44,
          fontSize: 15,
          items: [
            (null, 'All ${count(null)}'),
            (OrderType.dineIn, 'Dine in ${count(OrderType.dineIn)}'),
            (OrderType.takeaway, 'Takeaway ${count(OrderType.takeaway)}'),
            (OrderType.delivery, 'Delivery ${count(OrderType.delivery)}'),
          ],
          value: typeF,
          onChanged: (v) => setState(() => typeF = v),
        ),
        Seg<bool>(
          height: 44,
          items: [(false, 'Active ${active.length}'), (true, 'Ready ${all.length - active.length}')],
          value: readyTab,
          onChanged: (v) => setState(() => readyTab = v),
        ),
        Pill('Avg ticket ${_mmss(avg)}', bg: Colors.white, border: C.line, size: 14, pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
        Pill('Late $lateN',
            bg: lateN > 0 ? C.redTint : Colors.white,
            fg: lateN > 0 ? C.redInk : C.ink,
            border: C.line,
            size: 14,
            pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      ]),
      const SizedBox(height: 16),
      Expanded(
        child: kots.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('No tickets here', style: ts(16, w: w5)),
                const SizedBox(height: 4),
                Text('New KOTs appear as soon as they are sent', style: ts(13, c: C.muted)),
              ]))
            : LayoutBuilder(builder: (c, cons) {
                final cols = math.max(1, (cons.maxWidth / 290).floor());
                final w = (cons.maxWidth - 12 * (cols - 1)) / cols;
                return SingleChildScrollView(
                  child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [for (final k in kots) SizedBox(width: w, child: _ticket(s, k))]),
                );
              }),
      ),
    ]);
  }

  Widget _ticket(Store s, Kot k) {
    final o = s.orderById(k.orderId)!;
    final el = DateTime.now().difference(k.at);
    final stage = k.stage;
    final lvl = stage == KotStage.ready ? 3 : el.inMinutes >= lateMin ? 2 : el.inMinutes >= warnMin ? 1 : 0;
    const heads = <(Color, Color, Color)>[
      (Colors.white, C.ink, C.line),
      (Color(0xFFFEF3C7), Color(0xFF78350F), Color(0xFFFCD34D)),
      (C.red, Colors.white, C.red),
      (C.greenTint, Color(0xFF14532D), Color(0xFF86EFAC)),
    ];
    final head = heads[lvl];
    final done = k.lines.where((l) => l.state.index >= LineState.ready.index).length;
    final where = o.type == OrderType.dineIn ? 'Table ${s.labelOf(o)}' : (o.customer.isEmpty ? o.token : o.customer);
    final meta = o.type == OrderType.dineIn ? '${o.pax} pax · ${o.server}' : o.token;
    final tint = typeTint(o.type);
    final (action, onAction, actionBg) = switch (stage) {
      KotStage.fresh => ('Start', () => s.startKot(k), C.ink),
      KotStage.preparing => ('Mark ready', () => s.readyKot(k), C.green),
      _ => (o.type == OrderType.dineIn ? 'Served' : 'Handed over', () => s.bumpKot(k), C.ink),
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: head.$3)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: head.$1,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(20, w: w7, c: head.$2))),
              Text(_mmss(el),
                  style: ts(18, w: w6, c: head.$2).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Pill(o.type.label,
                  bg: lvl == 2 ? const Color(0x33FFFFFF) : tint.$1, fg: lvl == 2 ? Colors.white : tint.$2, weight: w6),
              const SizedBox(width: 6),
              Text('#${k.no}', style: ts(12, c: head.$2)),
              const Spacer(),
              Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: head.$2))),
            ]),
          ]),
        ),
        for (final l in k.lines)
          InkWell(
            onTap: () => s.toggleLine(l),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.soft))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 32,
                    child: Text('${l.qty}×',
                        style: ts(16, w: w7, c: l.state.index >= LineState.ready.index ? const Color(0xFFA1A1AA) : C.ink))),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.item.name,
                      style: ts(16,
                          w: w6,
                          c: l.state.index >= LineState.ready.index ? const Color(0xFFA1A1AA) : C.ink,
                          deco: l.state.index >= LineState.ready.index ? TextDecoration.lineThrough : null)),
                  for (final m in l.mods) Text(m, style: ts(13, c: C.ink2)),
                  if (l.note.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                      child: Text(l.note, style: ts(13, w: w5, c: const Color(0xFF92400E))),
                    ),
                ])),
                Icon(l.state.index >= LineState.ready.index ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 22, color: l.state.index >= LineState.ready.index ? C.green : C.faint),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            Expanded(
                child: Text(
                    stage == KotStage.ready
                        ? 'Ready for ${o.type == OrderType.dineIn ? 'service' : o.type == OrderType.delivery ? 'rider' : 'pickup'}'
                        : '$done/${k.lines.length} done',
                    style: ts(12, c: C.muted))),
            if (stage == KotStage.ready) ...[
              Btn.outline('Recall', height: 44, onTap: () => s.recallKot(k)),
              const SizedBox(width: 8),
            ],
            Btn(action, height: 44, bg: actionBg, onTap: onAction),
          ]),
        ),
      ]),
    );
  }
}
