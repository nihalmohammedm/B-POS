import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/keys.dart';

/// Complimentary bills, discounts, and refunds — all gated by a real
/// permission check (CLAUDE.md §3), unlike cancellation which is only gated
/// by order state. Complimentary and discount both happen inline in the
/// Settle payment dialog (lib/pos/payment.dart, via [reasonPickerDialog] and
/// [discountDialog] below); refunds are reachable from Settings → Settled bills.

/// Picks either a flat ₹ amount or a % off [subtotal], plus a reason, and
/// resolves it to a flat ₹ figure — called from the Settle payment dialog's
/// "Add discount" link. Returns (resolvedAmount, reason).
Future<(double, String)?> discountDialog(BuildContext context,
    {required double subtotal, required List<String> reasons, double initialAmount = 0, String? initialReason}) {
  var isPercent = false;
  final amt = TextEditingController(text: initialAmount > 0 ? _trimZeros(initialAmount) : '');
  String? picked = initialReason;
  final other = TextEditingController(text: picked != null && !reasons.contains(picked) ? picked : '');
  if (picked != null && !reasons.contains(picked)) picked = 'Other';
  return showPanelDialog<(double, String)>(
    context,
    maxWidth: 480,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final entered = double.tryParse(amt.text) ?? 0;
      final resolved = isPercent ? subtotal * entered / 100 : entered;
      final isOther = picked == 'Other';
      final reason = isOther ? other.text.trim() : (picked ?? '');
      final valid = resolved > 0 && resolved <= subtotal + 0.005 && reason.isNotEmpty;
      void done() {
        if (valid) Navigator.pop(ctx, (resolved.clamp(0, subtotal).toDouble(), reason));
      }

      return KeyScope(
        autofocus: true,
        keys: [
          Hotkey(const SingleActivator(LogicalKeyboardKey.enter), done, whileTyping: true),
          Hotkey(const SingleActivator(LogicalKeyboardKey.numpadEnter), done, whileTyping: true),
        ],
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add discount', style: ts(18, w: w5)),
            const SizedBox(height: 4),
            Text('Subtotal ${inr(subtotal, decimals: true)}', style: ts(13, c: C.muted)),
            const SizedBox(height: 16),
            Seg<bool>(
              items: const [(false, '₹ Amount'), (true, '% Off')],
              value: isPercent,
              onChanged: (v) => set(() => isPercent = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amt,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => set(() {}),
              style: ts(20, w: w5),
              decoration: InputDecoration(prefixText: isPercent ? null : '₹ ', suffixText: isPercent ? '%' : null),
            ),
            if (isPercent && entered > 0) ...[
              const SizedBox(height: 6),
              Text('= ${inr(resolved, decimals: true)} off', style: ts(13, c: C.muted)),
            ],
            const SizedBox(height: 16),
            Text('Reason', style: ts(15, w: w5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in reasons) Choice(r, on: picked == r, height: 42, fontSize: 13, onTap: () => set(() => picked = r)),
            ]),
            if (isOther) ...[
              const SizedBox(height: 10),
              TextField(
                  controller: other, autofocus: true, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'Type the reason')),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Btn.outline('Cancel', expand: true, onTap: () => Navigator.pop(ctx))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: Btn('Apply discount', expand: true, onTap: valid ? done : null)),
            ]),
          ]),
        ),
      );
    }),
  );
}

String _trimZeros(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Refunds part or all of one payment on an already-settled [o]. Reachable
/// from Settings → Settled bills.
Future<void> refundFlow(BuildContext context, Order o) async {
  final s = StoreScope.read(context);
  if (!s.can('payment.refund')) {
    toast(context, 'Not permitted to issue refunds', error: true);
    return;
  }
  var paymentIndex = 0;
  if (o.payments.length > 1) {
    final picked = await _paymentPicker(context, o);
    if (picked == null || !context.mounted) return;
    paymentIndex = picked;
  }
  final p = o.payments[paymentIndex];
  final already =
      o.refunds.where((r) => r.paymentIndex == paymentIndex).fold<double>(0, (a, r) => a + r.amount);
  final refundable = p.amount - already;
  if (refundable <= 0.005) {
    toast(context, '${p.method} payment is already fully refunded', error: true);
    return;
  }
  final result = await _refundDialog(context, method: p.method, refundable: refundable, reasons: s.cancelReasons);
  if (result == null || !context.mounted) return;
  final ok = s.refundPayment(o, paymentIndex, result.$1, result.$2, by: s.sessionFullName ?? '');
  toast(context, ok ? 'Refunded ${inr(result.$1, decimals: true)} · ${p.method}' : 'Refund failed', error: !ok);
}

Future<int?> _paymentPicker(BuildContext context, Order o) => showPanelDialog<int>(
      context,
      maxWidth: 420,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Refund which payment?', style: ts(18, w: w5)),
          const SizedBox(height: 16),
          for (var i = 0; i < o.payments.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Btn.outline('${o.payments[i].method} · ${inr(o.payments[i].amount, decimals: true)}',
                expand: true, onTap: () => Navigator.pop(ctx, i)),
          ],
          const SizedBox(height: 10),
          Btn.outline('Cancel', expand: true, onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    );

/// (amount, reason)
Future<(double, String)?> _refundDialog(BuildContext context,
    {required String method, required double refundable, required List<String> reasons}) {
  final amt = TextEditingController(text: refundable.toStringAsFixed(2));
  String? picked;
  final other = TextEditingController();
  return showPanelDialog<(double, String)>(
    context,
    maxWidth: 480,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final isOther = picked == 'Other';
      final reason = isOther ? other.text.trim() : (picked ?? '');
      final amount = double.tryParse(amt.text) ?? 0;
      final valid = amount > 0 && amount <= refundable + 0.005 && reason.isNotEmpty;
      void done() {
        if (valid) Navigator.pop(ctx, (amount, reason));
      }

      return KeyScope(
        autofocus: true,
        keys: [
          Hotkey(const SingleActivator(LogicalKeyboardKey.enter), done, whileTyping: true),
          Hotkey(const SingleActivator(LogicalKeyboardKey.numpadEnter), done, whileTyping: true),
        ],
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Refund $method', style: ts(18, w: w5)),
            const SizedBox(height: 4),
            Text('Up to ${inr(refundable, decimals: true)} can be refunded.', style: ts(13, c: C.muted)),
            const SizedBox(height: 16),
            const Label('Amount'),
            const SizedBox(height: 6),
            TextField(
              controller: amt,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => set(() {}),
              style: ts(20, w: w5),
              decoration: const InputDecoration(prefixText: '₹ '),
            ),
            const SizedBox(height: 16),
            Text('Reason', style: ts(15, w: w5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in reasons) Choice(r, on: picked == r, height: 42, fontSize: 13, onTap: () => set(() => picked = r)),
            ]),
            if (isOther) ...[
              const SizedBox(height: 10),
              TextField(
                  controller: other, autofocus: true, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'Type the reason')),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Btn.outline('Cancel', expand: true, onTap: () => Navigator.pop(ctx))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: Btn('Refund', bg: C.red, expand: true, onTap: valid ? done : null)),
            ]),
          ]),
        ),
      );
    }),
  );
}

/// Picks a reason (no quantity) — same `showPanelDialog` + `Choice` chip
/// pattern as item_amend.dart's private `_reasonDialog`, with its own copy
/// here since that one's file-private and this needs a different reason list.
/// Public: also used by the "Mark complimentary" option inside the Settle
/// payment dialog (lib/pos/payment.dart).
Future<String?> reasonPickerDialog(BuildContext context,
    {required String title, required Widget head, required List<String> reasons, required String confirm}) {
  String? picked;
  final other = TextEditingController();
  return showPanelDialog<String>(
    context,
    maxWidth: 480,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final isOther = picked == 'Other';
      final reason = isOther ? other.text.trim() : (picked ?? '');
      void done() {
        if (reason.isNotEmpty) Navigator.pop(ctx, reason);
      }

      return KeyScope(
        autofocus: true,
        keys: [
          Hotkey(const SingleActivator(LogicalKeyboardKey.enter), done, whileTyping: true),
          Hotkey(const SingleActivator(LogicalKeyboardKey.numpadEnter), done, whileTyping: true),
        ],
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label(title),
            const SizedBox(height: 6),
            head,
            const SizedBox(height: 18),
            Text('Reason', style: ts(15, w: w5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in reasons) Choice(r, on: picked == r, height: 46, fontSize: 14, onTap: () => set(() => picked = r)),
            ]),
            if (isOther) ...[
              const SizedBox(height: 10),
              TextField(
                  controller: other, autofocus: true, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'Type the reason')),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Btn.outline('Back', expand: true, onTap: () => Navigator.pop(ctx))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: Btn(confirm, expand: true, onTap: reason.isEmpty ? null : done)),
            ]),
          ]),
        ),
      );
    }),
  );
}
