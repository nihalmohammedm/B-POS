import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/keys.dart';
import '../widgets/receipt.dart';
import 'comp_refund.dart';

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class _PayRow {
  String method;
  final TextEditingController amt;
  final TextEditingController rec = TextEditingController();

  /// UPI: the cashier has seen the money arrive (phone / soundbox). Cleared when
  /// the amount or the UPI ID changes, since the check was for that payment.
  double? _okAmt;
  bool get upiOk => _okAmt != null && (_okAmt! - a).abs() < .005;
  set upiOk(bool v) => _okAmt = v ? a : null;
  String? upiId; // which UPI ID's QR was shown; null = the bill default
  _PayRow(this.method, double a) : amt = TextEditingController(text: _num(a));
  double get a => double.tryParse(amt.text) ?? 0;
  double get r => double.tryParse(rec.text) ?? 0;
  bool get done => a > 0 && (method == 'Cash' ? r >= a : upiOk);
}

/// [onComplimentary]: when given, the dialog offers a "Mark complimentary"
/// option (gated on `s.can('discount.apply')`); picking a reason calls this
/// and closes the dialog with no payments, same as Cancel — the caller
/// settles the order as complimentary instead of handling the (null) return.
///
/// [subtotal]/[onDiscount]: when given, the dialog offers "Add discount"
/// (same gate). Picking a discount calls this and closes the dialog with no
/// payments too — the caller applies it and reopens the dialog with the new
/// (lower) [total], same pattern as complimentary.
Future<List<Payment>?> showPaymentDialog(BuildContext context,
        {required String title,
        required String subtitle,
        required double total,
        double? subtotal,
        double currentDiscount = 0,
        String? currentDiscountReason,
        ValueChanged<String>? onComplimentary,
        ValueChanged<(double, String)>? onDiscount,
        VoidCallback? onRemoveDiscount}) =>
    showDialog<List<Payment>>(
        context: context,
        barrierColor: const Color(0x59141414),
        builder: (_) => _PayDialog(
            title: title,
            subtitle: subtitle,
            total: total,
            subtotal: subtotal ?? total,
            currentDiscount: currentDiscount,
            currentDiscountReason: currentDiscountReason,
            onComplimentary: onComplimentary,
            onDiscount: onDiscount,
            onRemoveDiscount: onRemoveDiscount));

class _PayDialog extends StatefulWidget {
  final String title, subtitle;
  final double total, subtotal, currentDiscount;
  final String? currentDiscountReason;
  final ValueChanged<String>? onComplimentary;
  final ValueChanged<(double, String)>? onDiscount;
  final VoidCallback? onRemoveDiscount;
  const _PayDialog(
      {required this.title,
      required this.subtitle,
      required this.total,
      required this.subtotal,
      this.currentDiscount = 0,
      this.currentDiscountReason,
      this.onComplimentary,
      this.onDiscount,
      this.onRemoveDiscount});
  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final List<_PayRow> rows = [_PayRow('UPI', widget.total)];
  int active = 0;

  double get allocated => rows.fold<double>(0, (a, r) => a + r.a);
  double get remaining =>
      double.parse((widget.total - allocated).toStringAsFixed(2));
  bool get ok => remaining.abs() < .01 && rows.every((r) => r.done);
  double get change => rows
      .where((r) => r.method == 'Cash')
      .fold<double>(0, (a, r) => a + math.max(0.0, r.r - r.a));

  void addRow() => setState(() {
        double amt = remaining;
        if (amt <= 0) {
          final first = rows.first;
          final fa = first.a;
          final half = (fa / 2).ceilToDouble();
          first.amt.text = _num(half);
          amt = fa - half;
        }
        rows.add(
            _PayRow(rows.any((r) => r.method == 'UPI') ? 'Cash' : 'UPI', amt));
        active = rows.length - 1;
      });

  List<Payment> _payments() {
    final s = StoreScope.read(context);
    return [
      for (final r in rows)
        if (r.method == 'Cash')
          Payment('Cash', r.a, r.r)
        else
          Payment(
              'UPI',
              r.a,
              0,
              (s.printLayout.upiAccounts
                              .where((a) => a.id == r.upiId)
                              .firstOrNull ??
                          s.printLayout.billUpi)
                      ?.label ??
                  '',
              s.sessionFullName ?? ''),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final remTxt = remaining.abs() < .01
        ? 'Fully allocated'
        : remaining > 0
            ? 'Remaining ${inr(remaining, decimals: true)}'
            : 'Over by ${inr(-remaining, decimals: true)}';
    void complete() {
      if (ok) Navigator.pop(context, _payments());
    }

    return KeyScope(
      autofocus: true,
      keys: [
        // Enter is safe while typing here: the amount fields are single-line.
        Hotkey(const SingleActivator(LogicalKeyboardKey.enter), complete,
            whileTyping: true),
        Hotkey(const SingleActivator(LogicalKeyboardKey.numpadEnter), complete,
            whileTyping: true),
        Hotkey(const SingleActivator(LogicalKeyboardKey.enter, control: true),
            complete),
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyS, control: true),
            addRow,
            when: () => rows.length < 4),
      ],
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: 900,
              maxHeight: MediaQuery.of(context).size.height * .94),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(widget.title, style: ts(20, w: w5)),
                      const SizedBox(height: 4),
                      Text(widget.subtitle, style: ts(14, c: C.muted)),
                    ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Label('Total due'),
                  Text(inr(widget.total, decimals: true), style: ts(26, w: w6)),
                ]),
                const SizedBox(width: 12),
                RoundIcon(Icons.close,
                    size: 40, onTap: () => Navigator.pop(context)),
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
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Expanded(child: left),
                              Expanded(child: right)
                            ])
                      : Column(
                          children: [left, const Divider(height: 1), right]);
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
                        bg: C.greenTint,
                        fg: C.greenInk,
                        size: 15,
                        weight: w6,
                        pad: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8)),
                  Btn.outline('Cancel', onTap: () => Navigator.pop(context)),
                  Btn('Complete · ${inr(widget.total)}',
                      onTap: ok
                          ? () => Navigator.pop(context, _payments())
                          : null),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _methodBtn(_PayRow r, String m, IconData icon) {
    final on = r.method == m;
    return Expanded(
      child: Material(
        color: on ? C.ink : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => r.method = m),
          child: Container(
            height: 76,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? C.ink : C.line, width: 1.5)),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 26, color: on ? Colors.white : C.ink),
              const SizedBox(height: 4),
              Text(m, style: ts(16, w: w6, c: on ? Colors.white : C.ink)),
            ]),
          ),
        ),
      ),
    );
  }

  /// One payment, whole bill: just pick Cash/UPI. The amount is always the total,
  /// so there is no amount field to fill in; splitting is an explicit opt-in.
  Widget _singlePane() {
    final r = rows.first;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Pay with', style: ts(15, w: w5)),
        const SizedBox(height: 12),
        Row(children: [
          _methodBtn(r, 'Cash', Icons.payments_outlined),
          const SizedBox(width: 12),
          _methodBtn(r, 'UPI', Icons.qr_code_2),
        ]),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: addRow,
          icon: const Icon(Icons.call_split, size: 18),
          label: const Text('Split between cash / UPI'),
        ),
        if (widget.onComplimentary != null &&
            StoreScope.of(context).can('discount.apply'))
          TextButton.icon(
            onPressed: _markComplimentary,
            icon: const Icon(Icons.card_giftcard_outlined, size: 18),
            label: const Text('Mark complimentary · nothing charged'),
          ),
        if (widget.onDiscount != null &&
            StoreScope.of(context).can('discount.apply'))
          widget.currentDiscount > 0
              ? Row(children: [
                  Expanded(
                      child: Text(
                          'Discount applied: -${inr(widget.currentDiscount, decimals: true)}'
                          '${widget.currentDiscountReason == null ? '' : ' · ${widget.currentDiscountReason}'}',
                          style: ts(13, c: C.redInk))),
                  TextButton(
                      onPressed: _removeDiscount, child: const Text('Remove')),
                ])
              : TextButton.icon(
                  onPressed: _addDiscount,
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('Add discount'),
                ),
      ]),
    );
  }

  Future<void> _markComplimentary() async {
    final s = StoreScope.of(context);
    final reason = await reasonPickerDialog(context,
        title: 'Settle as complimentary',
        reasons: s.complimentaryReasons,
        head: Text(
            '${inr(widget.total, decimals: true)} will be settled with nothing charged.',
            style: ts(15, c: C.ink2, h: 1.4)),
        confirm: 'Settle · Complimentary');
    if (reason == null || !mounted) return;
    widget.onComplimentary!(reason);
    Navigator.pop(context);
  }

  Future<void> _addDiscount() async {
    final s = StoreScope.of(context);
    final result = await discountDialog(context,
        subtotal: widget.subtotal, reasons: s.discountReasons);
    if (result == null || !mounted) return;
    widget.onDiscount!(result);
    Navigator.pop(context);
  }

  void _removeDiscount() {
    widget.onRemoveDiscount!();
    Navigator.pop(context);
  }

  Widget _rowsPane(String remTxt) => rows.length == 1
      ? _singlePane()
      : Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Split payment', style: ts(15, w: w5)),
              const Spacer(),
              Text(remTxt,
                  style: ts(13,
                      w: w5, c: remaining.abs() < .01 ? C.greenInk : C.red)),
            ]),
            const SizedBox(height: 12),
            for (var i = 0; i < rows.length; i++)
              Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _rowCard(i)),
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
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: C.faint, width: 1.5)),
                    child: Text('+ Add another payment', style: ts(15, w: w5)),
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
        : 'UPI · ${inr(r.a)}';
    return GestureDetector(
      onTap: () => setState(() => active = i),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: on ? Colors.white : C.soft2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? C.ink : C.line, width: on ? 2 : 1)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
                radius: 13,
                backgroundColor: C.soft,
                child: Text('${i + 1}', style: ts(12, w: w6))),
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
                        if (rows.length == 1)
                          rows.first.amt.text = _num(widget.total);
                      })),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: r.amt,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                onTap: () => setState(() => active = i),
                style: ts(20, w: w5),
                decoration: const InputDecoration(prefixText: '₹ '),
              ),
            ),
            if (remaining.abs() >= .01) ...[
              const SizedBox(width: 8),
              Btn.outline(
                  remaining > 0
                      ? 'Add rest ${inr(remaining)}'
                      : 'Cut ${inr(-remaining)}',
                  height: 48,
                  fontSize: 13,
                  onTap: () => setState(
                      () => r.amt.text = _num(math.max(0.0, r.a + remaining)))),
            ],
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Dot(color: r.done ? C.green : const Color(0xFFD0D0D0), size: 7),
            const SizedBox(width: 6),
            Expanded(
                child: Text(status,
                    style: ts(13,
                        w: w5,
                        c: r.done
                            ? C.greenInk
                            : (r.method == 'Cash' && r.r > 0
                                ? C.amberInk
                                : C.muted)))),
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
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.line)),
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
      final accts = StoreScope.of(context).printLayout.upiAccounts;
      final acct = accts.isEmpty
          ? null
          : accts.firstWhere((a) => a.id == r.upiId,
              orElse: () => StoreScope.of(context).printLayout.billUpi!);
      return Padding(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: C.greenTint, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(
                  child: Text(
                      rows.length > 1
                          ? 'UPI · Payment ${idx + 1}'
                          : 'Collect via UPI',
                      style: ts(15, w: w5, c: C.greenInk))),
              Text(inr(r.a, decimals: true),
                  style: ts(26, w: w6, c: C.greenInk)),
            ]),
          ),
          if (acct != null) ...[
            if (accts.length > 1) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in accts)
                  ChoiceChip(
                      label: Text(a.label, style: ts(14)),
                      selected: a.id == acct.id,
                      onSelected: (_) => setState(() {
                            r.upiId = a.id;
                            r.upiOk = false;
                          })),
              ]),
            ],
            const SizedBox(height: 16),
            Center(
                child: QrImageView(
                    data: acct.uri(r.a),
                    size: 200,
                    backgroundColor: Colors.white)),
            const SizedBox(height: 6),
            Center(child: Text(acct.vpa, style: ts(13, c: C.muted))),
          ],
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => r.upiOk = !r.upiOk),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                  color: r.upiOk ? C.greenTint : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: r.upiOk ? C.green : C.line,
                      width: r.upiOk ? 2 : 1)),
              child: Row(children: [
                Icon(
                    r.upiOk ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: r.upiOk ? C.green : C.muted,
                    size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payment received', style: ts(16, w: w5)),
                        Text(
                            'Tick once ${inr(r.a, decimals: true)} shows on your phone or soundbox',
                            style: ts(12, c: C.muted)),
                      ]),
                ),
              ]),
            ),
          ),
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
          Text(
              rows.length > 1
                  ? 'Cash received · Payment ${idx + 1}'
                  : 'Cash received',
              style: ts(15, w: w5)),
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
            suffixIcon: TextButton(
                onPressed: () => setState(r.rec.clear),
                child: const Text('Clear')),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < quick.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
                child: _quick(
                    i == 0 ? 'Exact' : inr(quick[i]),
                    i == 0 ? inr(quick[i]) : '',
                    () => setState(() => r.rec.text = _num(quick[i])))),
          ],
        ]),
        const SizedBox(height: 14),
        const Label('Tap to add to received'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            for (final n in [10, 20, 50, 100, 200, 500])
              _quick('+ ₹$n', '',
                  () => setState(() => r.rec.text = _num(r.r + n))),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: short ? const Color(0xFFFFF8EC) : C.greenTint,
              borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
                child: Text(
                    r.r == 0
                        ? 'Enter cash received'
                        : short
                            ? 'Still to collect'
                            : 'Balance to return',
                    style: ts(15, w: w5, c: short ? C.amberInk : C.greenInk))),
            if (r.r != 0)
              Text(inr(bal.abs(), decimals: true),
                  style: ts(26, w: w6, c: short ? C.amberInk : C.greenInk)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------- Flows shared by Tables / Orders ----------------
Future<void> settleFlow(BuildContext context, Order o,
    {bool print = true}) async {
  final s = StoreScope.read(context);
  final label = s.labelOf(o);
  List<Payment>? pays;
  if (o.isPaid && o.payments.isNotEmpty) {
    // Paid up front: the paid invoice was printed then; just close the order.
    s.settle(o);
    toast(context, '$label handed over · paid ${inr(o.paid)}');
    return;
  }
  if (o.isPaid) {
    pays = [Payment(o.payNote.split(' · ').last, o.total)];
  } else {
    String? complimentaryReason;
    (double, String)? discountResult;
    var removeDiscount = false;
    pays = await showPaymentDialog(context,
        title: 'Settle payment · $label',
        subtitle:
            '${s.titleOf(o)} · Subtotal ${inr(o.subtotal, decimals: true)}'
            '${o.discountAmount > 0 ? ' · Discount -${inr(o.discountAmount, decimals: true)}' : ''}'
            ' · Tax ${inr(o.tax, decimals: true)}${o.fee > 0 ? ' · ${o.type == OrderType.delivery ? 'Delivery' : 'Parcel'} ${inr(o.fee)}' : ''}',
        total: o.total,
        subtotal: o.subtotal,
        currentDiscount: o.discountAmount,
        currentDiscountReason: o.discountReason,
        onComplimentary: (r) => complimentaryReason = r,
        onDiscount: (r) => discountResult = r,
        onRemoveDiscount: () => removeDiscount = true);
    if (complimentaryReason != null) {
      if (!context.mounted) return;
      s.assignBillNo(o);
      final data = ReceiptData.bill(s, o, no: o.billNo);
      s.settleComplimentary(o,
          reason: complimentaryReason!, by: s.sessionFullName ?? '');
      toast(context, '$label settled · Complimentary ($complimentaryReason)');
      if (print)
        await showPrintPreview(context,
            bill: data, subtitle: 'Complimentary · $complimentaryReason');
      return;
    }
    if (discountResult != null) {
      if (!context.mounted) return;
      s.setDiscount(o, amount: discountResult!.$1, reason: discountResult!.$2);
      return settleFlow(context, o,
          print: print); // reopen with the new, lower total
    }
    if (removeDiscount) {
      if (!context.mounted) return;
      s.clearDiscount(o);
      return settleFlow(context, o, print: print);
    }
  }
  if (pays == null || !context.mounted) return;
  s.assignBillNo(o);
  final data = ReceiptData.bill(s, o, payments: pays, no: o.billNo);
  final total = o.total;
  s.settle(o, payments: pays);
  final change = pays.fold<double>(0, (a, p) => a + p.change);
  toast(context,
      '$label settled · ${inr(total)}${change > 0 ? ' · Return ${inr(change, decimals: true)}' : ''}');
  if (print) {
    await showPrintPreview(context,
        bill: data,
        subtitle: pays.map((p) => '${p.method} ${inr(p.amount)}').join(' + '));
  }
}

Future<void> printBillFlow(BuildContext context, Order o) async {
  final s = StoreScope.read(context);
  final ok = await showPrintPreview(context,
      bill: ReceiptData.bill(s, o, no: s.previewBillNo(o)),
      subtitle:
          '${s.titleOf(o)} · ${o.billed ? 'reprint' : 'locks the table until paid'}',
      printLabel: o.billed ? 'Reprint bill' : 'Print bill',
      // Printer down: still lock the table so the guest can pay and settle.
      skipLabel: o.billed ? null : 'Bill without printing', onSkip: () {
    final no = s.printBill(o);
    toast(context,
        '${s.labelOf(o)} billed $no · not printed · reprint from Orders when the printer is back');
  });
  if (ok && !o.billed) s.printBill(o);
}

/// Prints the bill if needed, then clears the table and leaves the bill waiting
/// under Payments.
Future<void> holdBillFlow(BuildContext context, Order o) async {
  final s = StoreScope.read(context);
  if (o.held) return;
  if (!o.billed) {
    await printBillFlow(context, o);
    if (!context.mounted || !o.billed) return;
  }
  final label = s.labelOf(o);
  final ok = await confirmDialog(context,
      title: 'Hold bill for $label?',
      body:
          'Table $label will be cleared. Bill ${o.billNo} (${inr(o.total)}) stays under Payments, waiting to settle.',
      ok: 'Hold bill');
  if (!ok || !context.mounted) return;
  if (s.holdBill(o))
    toast(context, '$label held · bill ${o.billNo} waiting in Payments');
}

Future<void> reopenFlow(BuildContext context, Order o) async {
  final s = StoreScope.read(context);
  final label = s.labelOf(o);
  if (o.held) {
    toast(context, '$label is on hold · settle it from Payments', error: true);
    return;
  }
  if (o.isPaid) {
    toast(context, '$label is already paid · a paid bill can\'t be reopened',
        error: true);
    return;
  }
  final ok = await confirmDialog(context,
      title: 'Reopen $label?',
      body:
          'Bill ${o.billNo} (${inr(o.total)}) will be voided. Print a new bill after adding items.',
      ok: 'Reopen');
  if (!ok || !context.mounted) return;
  final v = s.reopen(o);
  toast(context, '$label reopened · bill $v voided');
}
