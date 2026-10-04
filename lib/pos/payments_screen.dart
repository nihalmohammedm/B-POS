import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/keys.dart';
import '../widgets/receipt.dart';
import 'payment.dart';

/// Bills that have been printed but not paid yet, longest-waiting first, with
/// the bill itself on the side and Collect / Reprint / Reopen.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

/// Minutes a bill can wait before it's flagged amber, then red.
const _warnMin = 10, _lateMin = 20;

class _PaymentsScreenState extends State<PaymentsScreen> {
  OrderType? typeF;
  String q = '';
  int? selId;
  final _searchF = FocusNode(debugLabel: 'payments search');

  @override
  void dispose() {
    _searchF.dispose();
    super.dispose();
  }

  bool _match(Order o, Store s) {
    final x = q.trim().toLowerCase();
    if (x.isEmpty) return true;
    return [o.billNo ?? '', s.labelOf(o), o.token, o.customer, o.phone, o.server].any((v) => v.toLowerCase().contains(x));
  }

  static DateTime _since(Order o) => o.billedAt ?? o.at;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final all = s.awaitingPayment;
    final list = all.where((o) => (typeF == null || o.type == typeF) && _match(o, s)).toList();
    Order? sel;
    for (final o in list) {
      if (o.id == selId) sel = o;
    }
    sel ??= list.isEmpty ? null : list.first;
    int count(OrderType? t) => all.where((o) => t == null || o.type == t).length;
    final due = all.fold<double>(0, (a, o) => a + o.total);
    final oldest = all.isEmpty ? null : minsSince(_since(all.first));

    final o = sel;
    final keys = [
      ...listKeys<Order>(
          items: list, selected: o, select: (x) => setState(() => selId = x.id), search: _searchF, filter: (t) => setState(() => typeF = t)),
      if (o != null) ...[
        Hotkey(const SingleActivator(LogicalKeyboardKey.enter), () => settleFlow(context, o)),
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyP, control: true), () => printBillFlow(context, o)),
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyR, control: true), () => reopenFlow(context, o)),
      ],
    ];

    return KeyScope(autofocus: true, keys: keys, child: LayoutBuilder(builder: (c, cons) {
      final wide = cons.maxWidth >= 980;
      final pane = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _stat('Bills waiting', '${all.length}'),
          _stat('To collect', inr(due), strong: true),
          _stat('Oldest', oldest == null ? '—' : _mins(oldest), alert: (oldest ?? 0) >= _lateMin),
        ]),
        const SizedBox(height: 14),
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
              decoration: InputDecoration(
                  hintText: hasKeyboard ? 'Bill no, table, customer   /' : 'Bill no, table, customer',
                  prefixIcon: const Icon(Icons.search, size: 20)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: Panel(
            padding: EdgeInsets.zero,
            child: list.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle_outline, size: 36, color: C.green),
                      const SizedBox(height: 10),
                      Text(all.isEmpty ? 'No bills waiting for payment' : 'No bills match', style: ts(15, c: C.muted)),
                    ]),
                  )
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
        SizedBox(width: 400, child: sel == null ? const SizedBox() : _BillDetail(key: ValueKey(sel.id), order: sel)),
      ]);
    }));
  }

  static String _mins(int m) => m < 60 ? '${m}m' : '${m ~/ 60}h ${m % 60}m';

  Widget _stat(String label, String value, {bool strong = false, bool alert = false}) => Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
        decoration: BoxDecoration(
            color: alert ? C.redTint : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: alert ? C.red : C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(label),
          const SizedBox(height: 4),
          Text(value, style: ts(strong ? 24 : 22, w: w6, c: alert ? C.redInk : C.ink)),
        ]),
      );

  Widget _row(Store s, Order o, bool on, bool wide) {
    final m = minsSince(_since(o));
    final (ageC, ageW) = m >= _lateMin ? (C.redInk, w6) : m >= _warnMin ? (C.amberInk, w6) : (C.muted, FontWeight.w400);
    final tint = typeTint(o.type);
    return InkWell(
      onTap: () {
        setState(() => selId = o.id);
        if (!wide) {
          showPanelDialog(context,
              maxWidth: 440,
              builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * .88, child: _BillDetail(order: o, inDialog: true, host: context)));
        }
      },
      child: Container(
        color: on ? const Color(0xFFF7F9FC) : Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(color: on ? typeColor(o.type) : Colors.transparent, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 14),
          SizedBox(width: 70, child: Text(o.billNo ?? '—', style: ts(16, w: w6))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(s.titleOf(o), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w: w5))),
                const SizedBox(width: 8),
                Pill(o.type.label, bg: tint.$1, fg: tint.$2, size: 11),
              ]),
              const SizedBox(height: 2),
              Text(
                  [
                    '${o.itemCount} items',
                    if (o.server.isNotEmpty) o.server,
                    if (o.type != OrderType.dineIn && o.phone.isNotEmpty) o.phone,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(13, c: C.muted)),
            ]),
          ),
          SizedBox(
            width: 70,
            child: Tooltip(
              message: o.billedAt == null ? 'Waiting since the order was opened' : 'Waiting since the bill was printed',
              child: Text(_mins(m), textAlign: TextAlign.right, style: ts(14, c: ageC, w: ageW)),
            ),
          ),
          SizedBox(width: 96, child: Text(inr(o.total), textAlign: TextAlign.right, style: ts(17, w: w6))),
          if (wide) ...[
            const SizedBox(width: 14),
            Btn('Collect', height: 44, bg: C.green, onTap: () => settleFlow(context, o)),
          ],
        ]),
      ),
    );
  }
}

/// The printed bill as the customer has it, plus the actions on it.
class _BillDetail extends StatelessWidget {
  final Order order;
  final bool inDialog;
  /// The page behind the dialog: actions run there once the dialog closes.
  final BuildContext? host;
  const _BillDetail({super.key, required this.order, this.inDialog = false, this.host});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final o = order;
    final ctx = host ?? context;
    Future<void> then(Future<void> Function() f) async {
      if (inDialog) Navigator.pop(context);
      await f();
    }

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bill ${o.billNo ?? ''} · ${s.titleOf(o)}', style: ts(18, w: w5)),
                Text(o.billedAt == null ? 'Printed · unpaid' : 'Printed ${elapsed(o.billedAt!)} ago · unpaid',
                    style: ts(13, c: C.amberInk)),
              ]),
            ),
            if (inDialog) RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(context)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: const Color(0xFFE9E9E9),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ReceiptView(ReceiptData.bill(s, o, no: o.billNo), layout: s.printLayout),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('To collect', style: ts(15, c: C.ink2))),
              Text(inr(o.total, decimals: true), style: ts(24, w: w6)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Btn.outline('Reprint', icon: Icons.print_outlined, expand: true, onTap: () => then(() => printBillFlow(ctx, o)))),
              const SizedBox(width: 10),
              Expanded(child: Btn.outline('Reopen', icon: Icons.lock_open, expand: true, onTap: () => then(() => reopenFlow(ctx, o)))),
            ]),
            const SizedBox(height: 10),
            Btn('Collect ${inr(o.total)}', bg: C.green, height: 56, expand: true, onTap: () => then(() => settleFlow(ctx, o))),
            const SizedBox(height: 10),
            Btn.outline('Settle without printing', icon: Icons.print_disabled_outlined, expand: true,
                onTap: () => then(() => settleFlow(ctx, o, print: false))),
          ]),
        ),
      ]),
    );
  }
}
