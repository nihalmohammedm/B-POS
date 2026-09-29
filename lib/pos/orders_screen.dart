import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/keys.dart';
import '../widgets/receipt.dart';
import 'item_amend.dart';
import 'payment.dart';

class OrdersScreen extends StatefulWidget {
  final void Function(Order) onAddItems;
  const OrdersScreen({super.key, required this.onAddItems});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  OrderType? typeF;
  String q = '';
  int? selId;
  final _searchF = FocusNode(debugLabel: 'orders search');

  @override
  void dispose() {
    _searchF.dispose();
    super.dispose();
  }

  bool _match(Order o) {
    final x = q.trim().toLowerCase();
    if (x.isEmpty) return true;
    return ['${o.id}', o.token, o.customer, o.phone, o.tableId ?? ''].any((v) => v.toLowerCase().contains(x));
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final all = s.activeOrders;
    final list = all.where((o) => (typeF == null || o.type == typeF) && _match(o)).toList();
    Order? sel;
    for (final o in list) {
      if (o.id == selId) sel = o;
    }
    sel ??= list.isEmpty ? null : list.first;
    int count(OrderType? t) => all.where((o) => t == null || o.type == t).length;

    final o = sel;
    final keys = [
      ...listKeys<Order>(
          items: list, selected: o, select: (x) => setState(() => selId = x.id), search: _searchF, filter: (t) => setState(() => typeF = t)),
      if (o != null) ...[
        Hotkey(const SingleActivator(LogicalKeyboardKey.enter), () {
          final (_, act) = OrderDetail(orderId: o.id, onAddItems: widget.onAddItems)._primary(context, s, o, s.stageOf(o));
          act();
        }),
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyP, control: true), () => printBillFlow(context, o)),
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyK, control: true), () {
          final k = s.lastKot(o);
          if (k != null) showPrintPreview(context, kot: ReceiptData.kot(s, o, k, reprint: true), subtitle: '${s.titleOf(o)} · reprint');
        }),
        Hotkey(const SingleActivator(LogicalKeyboardKey.insert), () => widget.onAddItems(o),
            when: () => !o.billed && o.type != OrderType.delivery),
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyR, control: true), () => reopenFlow(context, o), when: () => o.billed),
        Hotkey(const SingleActivator(LogicalKeyboardKey.delete, control: true), () => cancelOrderFlow(context, o),
            when: () => s.canCancel(o)),
      ],
    ];

    return KeyScope(autofocus: true, keys: keys, child: LayoutBuilder(builder: (c, cons) {
      final wide = cons.maxWidth >= 980;
      final pane = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
          SizedBox(
            width: 260,
            child: TextField(
              focusNode: _searchF,
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(hintText: hasKeyboard ? 'Search orders   /' : 'Search orders', prefixIcon: const Icon(Icons.search, size: 20)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: Panel(
            padding: EdgeInsets.zero,
            child: list.isEmpty
                ? Center(child: Text('No ongoing orders', style: ts(15, c: C.muted)))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) => _row(s, list[i], sel?.id == list[i].id, wide),
                  ),
          ),
        ),
      ]);
      if (!wide) return pane;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: pane),
        const SizedBox(width: 20),
        SizedBox(
            width: 380,
            child: sel == null ? const SizedBox() : OrderDetail(key: ValueKey(sel.id), orderId: sel.id, onAddItems: widget.onAddItems)),
      ]);
    }));
  }

  Widget _row(Store s, Order o, bool on, bool wide) {
    final st = s.stageOf(o);
    final m = minsSince(o.at);
    final late = m >= 30;
    return InkWell(
      onTap: () {
        setState(() => selId = o.id);
        if (!wide) {
          showPanelDialog(context,
              maxWidth: 440,
              builder: (ctx) => SizedBox(
                  height: MediaQuery.of(ctx).size.height * .85,
                  child: OrderDetail(
                      orderId: o.id,
                      onAddItems: (x) {
                        Navigator.pop(ctx);
                        widget.onAddItems(x);
                      })));
        }
      },
      child: Container(
        color: on ? const Color(0xFFF7F9FC) : Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 20, 14),
        child: Row(children: [
          Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(color: on ? typeColor(o.type) : Colors.transparent, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 14),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.titleOf(o), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w: w5)),
            const SizedBox(height: 2),
            Text('${o.type.label} · ${o.type == OrderType.dineIn ? '#${o.id}' : o.token}', style: ts(13, c: C.muted)),
          ])),
          SizedBox(
            width: 150,
            child: Row(children: [
              Dot(color: stageColor(st)),
              const SizedBox(width: 7),
              Flexible(child: Text(st.label, overflow: TextOverflow.ellipsis, style: ts(14, c: C.ink2))),
            ]),
          ),
          SizedBox(
              width: 56,
              child: Text('${m}m', textAlign: TextAlign.right, style: ts(14, c: late ? C.redInk : C.muted, w: late ? w6 : FontWeight.w400))),
          SizedBox(width: 84, child: Text(inr(o.total), textAlign: TextAlign.right, style: ts(15, w: w5))),
        ]),
      ),
    );
  }
}

class OrderDetail extends StatelessWidget {
  final int orderId;
  final void Function(Order) onAddItems;
  const OrderDetail({super.key, required this.orderId, required this.onAddItems});

  static const flows = {
    OrderType.dineIn: [OrderStage.preparing, OrderStage.served, OrderStage.billing],
    OrderType.takeaway: [OrderStage.preparing, OrderStage.ready],
    OrderType.delivery: [OrderStage.preparing, OrderStage.ready, OrderStage.outForDelivery],
  };

  (String, VoidCallback) _primary(BuildContext context, Store s, Order o, OrderStage st) {
    if (o.type == OrderType.dineIn) {
      if (st == OrderStage.billing) return ('Settle payment', () => settleFlow(context, o));
      if (st == OrderStage.served) return ('Print bill', () => printBillFlow(context, o));
      return ('Mark served', () => s.markServed(o));
    }
    if (o.type == OrderType.takeaway) {
      if (st == OrderStage.ready) return (o.isPaid ? 'Hand over' : 'Settle & hand over', () => settleFlow(context, o));
      return ('Mark ready', () => s.markReady(o));
    }
    if (st == OrderStage.outForDelivery) return ('Mark delivered', () => settleFlow(context, o));
    if (st == OrderStage.ready) return ('Dispatch with rider', () => s.dispatch(o));
    return ('Mark ready', () => s.markReady(o));
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final o = s.orderById(orderId);
    if (o == null) return Panel(child: Center(child: Text('Order closed', style: ts(15, c: C.muted))));
    final st = s.stageOf(o);
    final flow = flows[o.type]!;
    final idx = flow.indexOf(st) < 0 ? 0 : flow.indexOf(st);
    final sub = o.type == OrderType.dineIn
        ? '${o.pax} guests${o.server.isEmpty ? '' : ' · ${o.server}'}'
        : o.type == OrderType.delivery
            ? '${o.address}${o.rider != null ? ' · Rider ${o.rider}' : ''}'
            : o.phone;
    final (label, action) = _primary(context, s, o, st);
    final kot = s.lastKot(o);

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o.type.label} · ${o.type == OrderType.dineIn ? '#${o.id}' : o.token} · ${elapsed(o.at)}',
                style: ts(13, c: C.muted)),
            const SizedBox(height: 4),
            Text(s.titleOf(o), style: ts(22, w: w5)),
            if (sub.isNotEmpty) Text(sub, style: ts(14, c: C.ink2, h: 1.4)),
            const SizedBox(height: 14),
            Row(children: [
              for (var i = 0; i < flow.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                    child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                            color: i <= idx ? typeColor(o.type) : const Color(0xFFECECEC), borderRadius: BorderRadius.circular(4)))),
              ],
            ]),
            const SizedBox(height: 8),
            Text(st.label, style: ts(14, w: w5)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), children: [
            for (final l in o.lines) SentLineRow(o, l),
            if (s.canAmend(o) && o.lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Tap an item to edit or cancel it', style: ts(12, c: C.muted)),
              ),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text(o.isPaid ? '${o.payNote}${o.billNo == null ? '' : ' · Bill ${o.billNo}'}' : (o.billed ? 'Bill ${o.billNo} · unpaid' : o.payNote),
                      style: ts(14, c: o.isPaid ? C.greenInk : C.ink2))),
              Text(inr(o.total), style: ts(22, w: w6)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  switch (v) {
                    case 'add':
                      onAddItems(o);
                    case 'kot':
                      if (kot != null) {
                        showPrintPreview(context,
                            kot: ReceiptData.kot(s, o, kot, reprint: true), bill: ReceiptData.bill(s, o), subtitle: '${s.titleOf(o)} · reprint');
                      }
                    case 'bill':
                      printBillFlow(context, o);
                    case 'reopen':
                      reopenFlow(context, o);
                    case 'cancel':
                      cancelOrderFlow(context, o);
                  }
                },
                itemBuilder: (_) => [
                  if (!o.billed && o.type != OrderType.delivery) const PopupMenuItem(value: 'add', child: Text('Add items')),
                  if (kot != null) const PopupMenuItem(value: 'kot', child: Text('Reprint KOT')),
                  const PopupMenuItem(value: 'bill', child: Text('Print bill')),
                  if (o.billed && !o.isPaid) const PopupMenuItem(value: 'reopen', child: Text('Reopen bill')),
                  PopupMenuItem(
                      value: 'cancel',
                      enabled: s.canCancel(o),
                      child: Text('Cancel order', style: TextStyle(color: s.canCancel(o) ? C.redInk : C.faint))),
                ],
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.line)),
                  child: const Icon(Icons.more_horiz),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Btn(label, expand: true, onTap: action)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
