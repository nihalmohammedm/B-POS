import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/keys.dart';
import '../widgets/receipt.dart';
import 'dialogs.dart';

/// Changes to items the kitchen already has. Every change prints a KOT so the
/// kitchen hears about it: cancellation KOT, modified-item KOT, or a normal KOT
/// for extra units.

/// Tap on a sent item: choose Edit or Cancel.
Future<void> sentItemActions(BuildContext context, Order o, OrderLine l) async {
  final s = StoreScope.read(context);
  if (!s.canAmend(o)) {
    toast(context, o.billed ? 'Bill printed · reopen it to change items' : 'Order is closed', error: true);
    return;
  }
  final pick = await showPanelDialog<String>(context,
      maxWidth: 420,
      builder: (ctx) => KeyScope(
          autofocus: true,
          keys: [
            Hotkey(const CharacterActivator('e'), () => Navigator.pop(ctx, 'edit')),
            Hotkey(const CharacterActivator('c'), () => Navigator.pop(ctx, 'cancel')),
            Hotkey(const SingleActivator(LogicalKeyboardKey.delete), () => Navigator.pop(ctx, 'cancel')),
          ],
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _itemHead(l),
              const SizedBox(height: 20),
              Btn.outline(hasKeyboard ? 'Edit item   E' : 'Edit item', icon: Icons.edit_outlined, expand: true, onTap: () => Navigator.pop(ctx, 'edit')),
              const SizedBox(height: 10),
              Btn(hasKeyboard ? 'Cancel item   C' : 'Cancel item', icon: Icons.block, bg: C.red, expand: true, onTap: () => Navigator.pop(ctx, 'cancel')),
              const SizedBox(height: 10),
              Btn.outline('Close', expand: true, onTap: () => Navigator.pop(ctx)),
            ]),
          )));
  if (!context.mounted) return;
  if (pick == 'edit') {
    await editItemFlow(context, o, l);
  } else if (pick == 'cancel') {
    await cancelItemFlow(context, o, l);
  }
}

Future<void> cancelItemFlow(BuildContext context, Order o, OrderLine l) async {
  final s = StoreScope.read(context);
  final r = await _reasonDialog(context,
      title: 'Cancel item', head: _itemHead(l), maxQty: l.activeQty, confirm: (n) => 'Cancel $n & print KOT');
  if (r == null || !context.mounted) return;
  final ks = s.cancelItem(o, l, r.qty, r.reason, by: s.sessionFullName ?? '');
  await printKotsWithToast(context, s, [for (final k in ks) ReceiptData.kot(s, o, k)]);
}

Future<void> editItemFlow(BuildContext context, Order o, OrderLine l) async {
  final s = StoreScope.read(context);
  MenuItem? live;
  for (final m in s.menu) {
    if (m.id == l.item.id) live = m;
  }
  final current = l.copy()
    ..qty = l.activeQty
    ..cancelledQty = 0;
  // Size and add-ons can only be changed while the item is still on the menu.
  final u = live != null && live.customizable
      ? await showCustomizeDialog(context, live, initial: current)
      : await showNoteDialog(context, current);
  if (u == null || !context.mounted) return;
  if (l.sameConfig(u) && u.qty == l.activeQty) return;

  // Adding more of the same needs no reason; anything that removes food does.
  var reason = '';
  if (!l.sameConfig(u) || u.qty < l.activeQty) {
    final r = await _reasonDialog(context,
        title: 'Why is this changing?', head: _changeHead(l, u), confirm: (_) => 'Save & print KOT');
    if (r == null || !context.mounted) return;
    reason = r.reason;
  }
  final ks = s.editItem(o, l, u, reason, by: s.sessionFullName ?? '');
  await printKotsWithToast(context, s, [for (final k in ks) ReceiptData.kot(s, o, k)]);
}

/// Cancels a whole order. Anything already sent goes out on a cancellation KOT per KOT group.
Future<void> cancelOrderFlow(BuildContext context, Order o) async {
  final s = StoreScope.read(context);
  final title = s.titleOf(o);
  if (o.liveLines.isEmpty) {
    s.closeVoidedOrder(o);
    toast(context, '$title closed');
    return;
  }
  final r = await _reasonDialog(context,
      title: 'Cancel order',
      head: Text('$title · ${o.itemCount} items will be cancelled and cancellation KOTs printed.',
          style: ts(15, c: C.ink2, h: 1.4)),
      confirm: (_) => 'Cancel order & print KOT');
  if (r == null || !context.mounted) return;
  final ks = s.cancelAllItems(o, r.reason, by: s.sessionFullName ?? '');
  final data = [for (final k in ks) ReceiptData.kot(s, o, k)];
  s.closeVoidedOrder(o);
  await printKotsWithToast(context, s, data);
}

// ---------------- shared bits ----------------

Widget _itemHead(OrderLine l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${l.activeQty}× ${l.item.name}', style: ts(20, w: w5)),
      if (l.optText.isNotEmpty) Text(l.optText, style: ts(14, c: C.muted)),
      if (l.note.isNotEmpty) Text('Note: ${l.note}', style: ts(14, c: C.amberInk)),
      const SizedBox(height: 8),
      Row(children: [
        Pill(l.state.label, bg: lineStateColors(l.state).$1, fg: lineStateColors(l.state).$2, border: C.line),
        if (l.cancelledQty > 0) ...[const SizedBox(width: 8), Pill('${l.cancelledQty} already cancelled', bg: C.redTint, fg: C.redInk)],
      ]),
      if (l.state != LineState.queued) ...[
        const SizedBox(height: 10),
        Text('The kitchen has already started this item.', style: ts(13, c: C.redInk)),
      ],
    ]);

Widget _changeHead(OrderLine from, OrderLine to) {
  String d(OrderLine x, int q) =>
      '$q× ${x.item.name}${x.optText.isNotEmpty ? ' · ${x.optText}' : ''}${x.note.isNotEmpty ? ' · "${x.note}"' : ''}';
  final sameItem = from.sameConfig(to);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(sameItem ? 'Reduce quantity' : 'Change item', style: ts(20, w: w5)),
    const SizedBox(height: 10),
    Text(sameItem ? '${from.activeQty} → ${to.qty}  ${from.item.name}' : '−  ${d(from, from.activeQty)}',
        style: ts(15, c: C.redInk, w: w5)),
    if (!sameItem) Text('+  ${d(to, to.qty)}', style: ts(15, c: C.greenInk, w: w5)),
  ]);
}

class _Reason {
  final int qty;
  final String reason;
  const _Reason(this.qty, this.reason);
}

/// Picks a cancellation reason (and, when [maxQty] is given, how many units).
Future<_Reason?> _reasonDialog(BuildContext context,
    {required String title, required Widget head, int? maxQty, required String Function(int qty) confirm}) {
  final reasons = StoreScope.read(context).cancelReasons;
  int qty = maxQty ?? 1;
  String? picked;
  final other = TextEditingController();
  return showPanelDialog<_Reason>(context,
      maxWidth: 520,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
            final isOther = picked == 'Other';
            final reason = isOther ? other.text.trim() : (picked ?? '');
            void done() {
              if (reason.isNotEmpty) Navigator.pop(ctx, _Reason(qty, reason));
            }

            const digits = [
              LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
              LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
              LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
            ];
            return KeyScope(
                autofocus: true,
                keys: [
                  for (var i = 0; i < reasons.length && i < 9; i++)
                    Hotkey(SingleActivator(digits[i]), () => set(() => picked = reasons[i])),
                  if (maxQty != null) ...[
                    Hotkey(const CharacterActivator('+'), () => set(() => qty = (qty + 1).clamp(1, maxQty))),
                    Hotkey(const CharacterActivator('-'), () => set(() => qty = (qty - 1).clamp(1, maxQty))),
                  ],
                  // Enter also confirms from the "Other" reason box.
                  Hotkey(const SingleActivator(LogicalKeyboardKey.enter), done, whileTyping: true),
                  Hotkey(const SingleActivator(LogicalKeyboardKey.numpadEnter), done, whileTyping: true),
                ],
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Label(title),
                    const SizedBox(height: 6),
                    head,
                    if (maxQty != null && maxQty > 1) ...[
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: Text('How many to cancel?', style: ts(15, w: w5))),
                        QtyStepper(
                            value: qty,
                            size: 44,
                            onDec: qty > 1 ? () => set(() => qty--) : null,
                            onInc: qty < maxQty ? () => set(() => qty++) : null),
                      ]),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, children: [
                        Choice('1', on: qty == 1, height: 40, width: 48, fontSize: 15, onTap: () => set(() => qty = 1)),
                        Choice('All $maxQty', on: qty == maxQty, height: 40, fontSize: 15, onTap: () => set(() => qty = maxQty)),
                      ]),
                    ],
                    const SizedBox(height: 18),
                    Text('Reason', style: ts(15, w: w5)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final r in reasons)
                        Choice(r, on: picked == r, height: 46, fontSize: 14, onTap: () => set(() => picked = r)),
                    ]),
                    if (isOther) ...[
                      const SizedBox(height: 10),
                      TextField(
                          controller: other,
                          autofocus: true,
                          onChanged: (_) => set(() {}),
                          decoration: const InputDecoration(hintText: 'Type the reason')),
                    ],
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
                child: Row(children: [
                  Expanded(child: Btn.outline('Back', expand: true, onTap: () => Navigator.pop(ctx))),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 2,
                      child: Btn(confirm(qty),
                          bg: C.red,
                          expand: true,
                          onTap: reason.isEmpty ? null : () => Navigator.pop(ctx, _Reason(qty, reason)))),
                ]),
              ),
            ]));
          }));
}

/// A sent item in an order list. Tapping it opens Edit / Cancel while the order
/// is still open; cancelled units stay visible, struck through.
class SentLineRow extends StatelessWidget {
  final Order o;
  final OrderLine l;
  const SentLineRow(this.o, this.l, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final gone = l.activeQty == 0;
    final strike = gone ? TextDecoration.lineThrough : null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 34, child: Text('${gone ? l.qty : l.activeQty}×', style: ts(14, c: C.muted, deco: strike))),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.item.name, style: ts(15, c: gone ? C.muted : C.ink, deco: strike)),
          if (l.optText.isNotEmpty) Text(l.optText, style: ts(13, c: C.muted, deco: strike)),
          if (l.note.isNotEmpty) Text(l.note, style: ts(13, c: C.amberInk, deco: strike)),
          Wrap(spacing: 8, children: [
            if (!gone) Text(l.state.label, style: ts(12, c: lineStateColors(l.state).$2)),
            if (l.cancelledQty > 0) Text(gone ? 'Cancelled' : '${l.cancelledQty} cancelled', style: ts(12, w: w5, c: C.redInk)),
          ]),
        ])),
        Text(inr(l.total), style: ts(15, c: gone ? C.muted : C.ink)),
      ]),
    );
    if (gone || !s.canAmend(o)) return row;
    return InkWell(borderRadius: BorderRadius.circular(10), onTap: () => sentItemActions(context, o, l), child: row);
  }
}
