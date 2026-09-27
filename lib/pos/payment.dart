import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/receipt.dart';

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class _PayRow {
  String method;
  final TextEditingController amt;
  final TextEditingController rec = TextEditingController();
  bool upiOk = false;
  _PayRow(this.method, double a) : amt = TextEditingController(text: _num(a));
  double get a => double.tryParse(amt.text) ?? 0;
  double get r => double.tryParse(rec.text) ?? 0;
  bool get done => a > 0 && (method == 'Cash' ? r >= a : upiOk);
}

Future<List<Payment>?> showPaymentDialog(BuildContext context,
        {required String title, required String subtitle, required double total}) =>
    showDialog<List<Payment>>(
        context: context,
        barrierColor: const Color(0x59141414),
        builder: (_) => _PayDialog(title: title, subtitle: subtitle, total: total));

class _PayDialog extends StatefulWidget {
  final String title, subtitle;
  final double total;
  const _PayDialog({required this.title, required this.subtitle, required this.total});
  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final List<_PayRow> rows = [_PayRow('Cash', widget.total)];
  int active = 0;

  double get allocated => rows.fold<double>(0, (a, r) => a + r.a);
  double get remaining => double.parse((widget.total - allocated).toStringAsFixed(2));
  bool get ok => remaining.abs() < .01 && rows.every((r) => r.done);
  double get change => rows.where((r) => r.method == 'Cash').fold<double>(0, (a, r) => a + math.max(0.0, r.r - r.a));

  void addRow() => setState(() {
        double amt = remaining;
        if (amt <= 0) {
          final first = rows.first;
          final fa = first.a;
          final half = (fa / 2).ceilToDouble();
          first.amt.text = _num(half);
          amt = fa - half;
        }
        rows.add(_PayRow(rows.any((r) => r.method == 'Cash') ? 'UPI' : 'Cash', amt));
        active = rows.length - 1;
      });

  @override
  Widget build(BuildContext context) {
    final remTxt = remaining.abs() < .01
        ? 'Fully allocated'
        : remaining > 0
            ? 'Remaining ${inr(remaining, decimals: true)}'
            : 'Over by ${inr(-remaining, decimals: true)}';
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900, maxHeight: MediaQuery.of(context).size.height * .94),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: ts(20, w: w5)),
                const SizedBox(height: 4),
                Text(widget.subtitle, style: ts(14, c: C.muted)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Label('Total due'),
                Text(inr(widget.total, decimals: true), style: ts(26, w: w6)),
              ]),
              const SizedBox(width: 12),
              RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              child: LayoutBuilder(builder: (c, cons) {
                final wide = cons.maxWidth > 700;
                final left = _rowsPane(remTxt);
                final right = Container(color: C.soft2, child: _activePane());
                return wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), Expanded(child: right)])
                    : Column(children: [left, const Divider(height: 1), right]);
              }),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                if (change > 0)
                  Pill('Return ${inr(change, decimals: true)} to guest',
                      bg: C.greenTint, fg: C.greenInk, size: 15, weight: w6, pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                Btn.outline('Cancel', onTap: () => Navigator.pop(context)),
                Btn('Complete · ${inr(widget.total)}',
                    onTap: ok
                        ? () => Navigator.pop(
                            context, rows.map((r) => Payment(r.method, r.a, r.method == 'Cash' ? r.r : 0)).toList())
                        : null),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _rowsPane(String remTxt) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Payments', style: ts(15, w: w5)),
            const Spacer(),
            Text(remTxt, style: ts(13, w: w5, c: remaining.abs() < .01 ? C.greenInk : C.red)),
          ]),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: _rowCard(i)),
          if (rows.length < 4)
            Material(
              color: C.soft2,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: addRow,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.faint, width: 1.5)),
                  child: Text('+ Split payment', style: ts(15, w: w5)),
                ),
              ),
            ),
        ]),
      );

  Widget _rowCard(int i) {
    final r = rows[i];
    final on = i == active;
    final status = r.method == 'Cash'
        ? (r.r == 0
            ? 'Enter cash received'
            : r.r < r.a
                ? 'Short by ${inr(r.a - r.r, decimals: true)}'
                : 'Received ${inr(r.r)} · Return ${inr(r.r - r.a, decimals: true)}')
        : (r.upiOk ? 'UPI payment received' : 'Awaiting UPI payment');
    return GestureDetector(
      onTap: () => setState(() => active = i),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: on ? Colors.white : C.soft2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? C.ink : C.line, width: on ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 13, backgroundColor: C.soft, child: Text('${i + 1}', style: ts(12, w: w6))),
            const SizedBox(width: 8),
            Seg<String>(
                height: 34,
                items: const [('Cash', 'Cash'), ('UPI', 'UPI')],
                value: r.method,
                onChanged: (v) => setState(() {
                      r.method = v;
                      active = i;
                    })),
            const Spacer(),
            if (rows.length > 1)
              RoundIcon(Icons.close,
                  size: 34,
                  fg: C.red,
                  onTap: () => setState(() {
                        rows.removeAt(i);
                        active = 0;
                      })),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: r.amt,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                onTap: () => setState(() => active = i),
                style: ts(20, w: w5),
                decoration: const InputDecoration(prefixText: '₹ '),
              ),
            ),
            if (remaining.abs() >= .01) ...[
              const SizedBox(width: 8),
              Btn.outline(remaining > 0 ? '+ ${inr(remaining)}' : '− ${inr(-remaining)}',
                  height: 48, fontSize: 13, onTap: () => setState(() => r.amt.text = _num(math.max(0.0, r.a + remaining)))),
            ],
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Dot(color: r.done ? C.green : const Color(0xFFD0D0D0), size: 7),
            const SizedBox(width: 6),
            Expanded(
                child: Text(status,
                    style: ts(13, w: w5, c: r.done ? C.greenInk : (r.method == 'Cash' && r.r > 0 ? C.amberInk : C.muted)))),
          ]),
        ]),
      ),
    );
  }

  Widget _quick(String label, String sub, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: ts(15, w: w6)),
              if (sub.isNotEmpty) Text(sub, style: ts(11, c: C.muted)),
            ]),
          ),
        ),
      );

  Widget _activePane() {
    final idx = math.min(active, rows.length - 1);
    final r = rows[idx];
    if (r.method == 'UPI') {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('UPI · Payment ${idx + 1}', style: ts(15, w: w5)),
            const Spacer(),
            Text('bistro21@okhdfc', style: ts(13, c: C.muted)),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.faint, width: 1.5)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.qr_code_2, size: 96),
                Text(inr(r.a), style: ts(22, w: w6)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text('Ask the guest to scan with any UPI app, then confirm once received.',
              textAlign: TextAlign.center, style: ts(13, c: C.muted)),
          const SizedBox(height: 14),
          Btn(r.upiOk ? 'Received ✓ · Undo' : 'Mark as received',
              bg: r.upiOk ? C.greenTint : C.ink,
              fg: r.upiOk ? C.greenInk : Colors.white,
              expand: true,
              onTap: () => setState(() => r.upiOk = !r.upiOk)),
        ]),
      );
    }
    final bal = r.r - r.a;
    final quick = <double>{
      r.a,
      (r.a / 100).ceil() * 100.0,
      (r.a / 500).ceil() * 500.0,
      (r.a / 1000).ceil() * 1000.0,
      (r.a / 2000).ceil() * 2000.0,
    }.where((v) => v > 0).take(4).toList();
    final short = r.r > 0 && bal < 0;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Cash received · Payment ${idx + 1}', style: ts(15, w: w5)),
          const Spacer(),
          Text('Due ${inr(r.a)}', style: ts(13, c: C.muted)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: r.rec,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: ts(28, w: w6),
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: '0',
            suffixIcon: TextButton(onPressed: () => setState(r.rec.clear), child: const Text('Clear')),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < quick.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
                child: _quick(i == 0 ? 'Exact' : inr(quick[i]), i == 0 ? inr(quick[i]) : '',
                    () => setState(() => r.rec.text = _num(quick[i])))),
          ],
        ]),
        const SizedBox(height: 14),
        const Label('Add notes'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            for (final n in [10, 20, 50, 100, 200, 500]) _quick('+ ₹$n', '', () => setState(() => r.rec.text = _num(r.r + n))),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: short ? const Color(0xFFFFF8EC) : C.greenTint, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
                child: Text(short ? 'Still to collect' : 'Balance to return',
                    style: ts(15, w: w5, c: short ? C.amberInk : C.greenInk))),
            Text(inr(r.r == 0 ? 0 : bal.abs(), decimals: true), style: ts(26, w: w6, c: short ? C.amberInk : C.greenInk)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------- Flows shared by Tables / Orders ----------------
Future<void> settleFlow(BuildContext context, Order o) async {
  final s = StoreScope.read(context);
  final label = s.labelOf(o);
  List<Payment>? pays;
  if (o.isPaid) {
    pays = [Payment(o.payNote.split(' · ').last, o.total)];
  } else {
    pays = await showPaymentDialog(context,
        title: 'Settle payment · $label',
        subtitle:
            '${s.titleOf(o)} · Subtotal ${inr(o.subtotal, decimals: true)} · Tax ${inr(o.tax, decimals: true)}${o.fee > 0 ? ' · Delivery ${inr(o.fee)}' : ''}',
        total: o.total);
  }
  if (pays == null || !context.mounted) return;
  s.assignBillNo(o);
  final data = ReceiptData.bill(s, o, payments: pays, no: o.billNo);
  final total = o.total;
  s.settle(o);
  final change = pays.fold<double>(0, (a, p) => a + p.change);
  toast(context, '$label settled · ${inr(total)}${change > 0 ? ' · Return ${inr(change, decimals: true)}' : ''}');
  await showPrintPreview(context, bill: data, subtitle: pays.map((p) => '${p.method} ${inr(p.amount)}').join(' + '));
}

Future<void> printBillFlow(BuildContext context, Order o) async {
  final s = StoreScope.read(context);
  final ok = await showPrintPreview(context,
      bill: ReceiptData.bill(s, o, no: s.previewBillNo(o)),
      subtitle: '${s.titleOf(o)} · ${o.billed ? 'reprint' : 'locks the table until paid'}',
      printLabel: o.billed ? 'Reprint bill' : 'Print bill');
  if (ok && !o.billed) s.printBill(o);
}

Future<void> reopenFlow(BuildContext context, Order o) async {
  final s = StoreScope.read(context);
  final label = s.labelOf(o);
  final ok = await confirmDialog(context,
      title: 'Reopen $label?',
      body: 'Bill ${o.billNo} (${inr(o.total)}) will be voided. Print a new bill after adding items.',
      ok: 'Reopen');
  if (!ok || !context.mounted) return;
  final v = s.reopen(o);
  toast(context, '$label reopened · bill $v voided');
}
