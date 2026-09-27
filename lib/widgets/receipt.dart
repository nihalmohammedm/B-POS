import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'common.dart';

class ReceiptLine {
  int qty;
  final String name;
  final double rate;
  final List<String> mods;
  final String note;
  ReceiptLine(this.qty, this.name, this.rate, this.mods, this.note);
}

class ReceiptData {
  final bool isKot;
  final String no;
  final OrderType type;
  final String where, server, customer;
  final int pax;
  final DateTime at;
  final List<ReceiptLine> lines;
  final double fee;
  final List<Payment> payments;
  final bool reprint;

  const ReceiptData({
    required this.isKot,
    required this.no,
    required this.type,
    required this.where,
    required this.server,
    required this.pax,
    required this.at,
    required this.lines,
    this.customer = '',
    this.fee = 0,
    this.payments = const [],
    this.reprint = false,
  });

  factory ReceiptData.kot(Store s, Order o, Kot k, {bool reprint = false}) => ReceiptData(
        isKot: true,
        no: '${k.no}',
        type: o.type,
        where: s.labelOf(o),
        server: o.server,
        pax: o.type == OrderType.dineIn ? o.pax : 0,
        at: k.at,
        customer: o.customer,
        reprint: reprint,
        lines: k.lines.map((l) => ReceiptLine(l.qty, l.item.name, l.unit, l.mods, l.note)).toList(),
      );

  factory ReceiptData.bill(Store s, Order o, {List<Payment> payments = const [], String? no}) {
    final merged = <String, ReceiptLine>{};
    for (final l in o.lines) {
      final key = '${l.item.id}|${l.optText}';
      final ex = merged[key];
      if (ex != null) {
        ex.qty += l.qty;
      } else {
        merged[key] = ReceiptLine(l.qty, l.item.name, l.unit, l.mods, '');
      }
    }
    return ReceiptData(
      isKot: false,
      no: no ?? s.previewBillNo(o),
      type: o.type,
      where: s.labelOf(o),
      server: o.server,
      pax: o.type == OrderType.dineIn ? o.pax : 0,
      at: DateTime.now(),
      customer: [o.customer, o.phone].where((x) => x.isNotEmpty).join(' · '),
      fee: o.fee,
      payments: payments,
      lines: merged.values.toList(),
    );
  }
}

String _words(int n) {
  const a = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen',
    'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  const b = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  String two(int x) => x < 20 ? a[x] : b[x ~/ 10] + (x % 10 > 0 ? ' ${a[x % 10]}' : '');
  String three(int x) =>
      (x >= 100 ? '${a[x ~/ 100]} Hundred${x % 100 > 0 ? ' ' : ''}' : '') + (x % 100 > 0 ? two(x % 100) : '');
  if (n == 0) return 'Zero';
  final l = n ~/ 100000, t = (n % 100000) ~/ 1000, r = n % 1000;
  return [if (l > 0) '${two(l)} Lakh', if (t > 0) '${two(t)} Thousand', if (r > 0) three(r)].join(' ');
}

String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _t(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _Dash extends StatelessWidget {
  const _Dash();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: LayoutBuilder(builder: (c, cons) {
          final n = (cons.maxWidth / 6).floor();
          return Row(
              children: List.generate(
                  n, (_) => Container(width: 3, height: 1, margin: const EdgeInsets.only(right: 3), color: const Color(0xFF111111))));
        }),
      );
}

class ReceiptView extends StatelessWidget {
  final ReceiptData d;
  const ReceiptView(this.d, {super.key});

  TextStyle _m(double s, [FontWeight w = FontWeight.w400, Color c = const Color(0xFF111111)]) => TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New', 'Courier', 'Menlo'],
      fontSize: s,
      fontWeight: w,
      color: c,
      height: 1.45);

  Widget _kv(String a, String b, {double s = 12, FontWeight w = FontWeight.w400}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: Text(a, style: _m(s, w))), const SizedBox(width: 8), Text(b, style: _m(s, w))]);

  Widget _c(String t, TextStyle st) => Text(t, textAlign: TextAlign.center, style: st);
  String _n(double v, [bool dec = true]) => inr(v, decimals: dec).substring(1);

  String get _banner => switch (d.type) {
        OrderType.dineIn => 'DINE IN · ${d.where}',
        OrderType.takeaway => 'TAKEAWAY · ${d.where}',
        OrderType.delivery => 'DELIVERY · ${d.where}',
      };
  String get _typeLine => switch (d.type) {
        OrderType.dineIn => 'Table: ${d.where}',
        OrderType.takeaway => 'Takeaway: ${d.where}',
        OrderType.delivery => 'Delivery: ${d.where}',
      };

  @override
  Widget build(BuildContext context) => Container(
        width: 302,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 30, offset: Offset(0, 12))]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: d.isKot ? _kot() : _bill()),
      );

  List<Widget> _kot() => [
        _c('KITCHEN ORDER TICKET', _m(11).copyWith(letterSpacing: 1.5)),
        _c('KOT #${d.no}', _m(24, FontWeight.w700)),
        const SizedBox(height: 6),
        Center(
            child: Container(
                color: const Color(0xFF111111),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(_banner, style: _m(15, FontWeight.w700, Colors.white)))),
        const _Dash(),
        _kv(_d(d.at), _t(d.at)),
        _kv('Server: ${d.server}', d.pax > 0 ? 'Pax: ${d.pax}' : ''),
        if (d.customer.isNotEmpty && d.type != OrderType.dineIn) Text('Customer: ${d.customer}', style: _m(12)),
        if (d.reprint) _c('*** REPRINT ***', _m(12, FontWeight.w700)),
        const _Dash(),
        for (final l in d.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 34, child: Text('${l.qty}x', style: _m(15, FontWeight.w700))),
                Expanded(child: Text(l.name.toUpperCase(), style: _m(15, FontWeight.w700))),
              ]),
              for (final m in l.mods) Padding(padding: const EdgeInsets.only(left: 34), child: Text(m, style: _m(13))),
              if (l.note.isNotEmpty)
                Padding(padding: const EdgeInsets.only(left: 34), child: Text('** ${l.note} **', style: _m(13, FontWeight.w700))),
            ]),
          ),
        const _Dash(),
        _kv('Total items', '${d.lines.fold<int>(0, (a, l) => a + l.qty)}', w: FontWeight.w600),
        const SizedBox(height: 12),
        _c('— BISTRO 21 —', _m(11).copyWith(letterSpacing: 1)),
      ];

  List<Widget> _bill() {
    final sub = d.lines.fold<double>(0, (a, l) => a + l.qty * l.rate);
    final tax = sub * .05, raw = sub + tax + d.fee, total = raw.roundToDouble(), round = total - raw;
    final cash = d.payments.where((p) => p.method == 'Cash' && p.tendered > 0).toList();
    final tendered = cash.fold<double>(0, (a, p) => a + p.tendered), change = cash.fold<double>(0, (a, p) => a + p.change);
    final grey = _m(11, FontWeight.w400, const Color(0xFF444444));
    return [
      _c('BISTRO 21', _m(17, FontWeight.w700)),
      _c('MG Road, Kochi 682016', _m(12)),
      _c('Ph: +91 484 400 2121', _m(12)),
      _c('GSTIN: 32ABCDE1234F1Z5', _m(12)),
      const SizedBox(height: 8),
      _c(d.payments.isNotEmpty ? 'TAX INVOICE' : 'BILL · NOT PAID', _m(12, FontWeight.w700).copyWith(letterSpacing: 1.5)),
      const _Dash(),
      _kv('Bill No: ${d.no}', _d(d.at)),
      _kv(_typeLine, _t(d.at)),
      _kv('Server: ${d.server}', d.pax > 0 ? 'Pax: ${d.pax}' : ''),
      if (d.customer.isNotEmpty) Text('Customer: ${d.customer}', style: _m(12)),
      const _Dash(),
      Row(children: [
        Expanded(child: Text('ITEM', style: _m(11, FontWeight.w600))),
        SizedBox(width: 30, child: Text('QTY', textAlign: TextAlign.right, style: _m(11, FontWeight.w600))),
        SizedBox(width: 56, child: Text('RATE', textAlign: TextAlign.right, style: _m(11, FontWeight.w600))),
        SizedBox(width: 66, child: Text('AMT', textAlign: TextAlign.right, style: _m(11, FontWeight.w600))),
      ]),
      const _Dash(),
      for (final l in d.lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(l.name, style: _m(12))),
              SizedBox(width: 30, child: Text('${l.qty}', textAlign: TextAlign.right, style: _m(12))),
              SizedBox(width: 56, child: Text(_n(l.rate, false), textAlign: TextAlign.right, style: _m(12))),
              SizedBox(width: 66, child: Text(_n(l.qty * l.rate), textAlign: TextAlign.right, style: _m(12))),
            ]),
            for (final m in l.mods) Padding(padding: const EdgeInsets.only(left: 8), child: Text(m, style: grey)),
          ]),
        ),
      const _Dash(),
      _kv('Subtotal (${d.lines.fold<int>(0, (a, l) => a + l.qty)} items)', _n(sub)),
      _kv('CGST @2.5%', _n(tax / 2)),
      _kv('SGST @2.5%', _n(tax / 2)),
      if (d.fee > 0) _kv('Delivery charge', _n(d.fee)),
      _kv('Round off', '${round >= 0 ? '+' : '-'}${_n(round.abs())}'),
      const _Dash(),
      _kv('TOTAL', inr(total, decimals: true), s: 18, w: FontWeight.w700),
      const _Dash(),
      if (d.payments.isNotEmpty) ...[
        for (final p in d.payments) _kv('Paid · ${p.method}', _n(p.amount)),
        if (tendered > 0) ...[_kv('Cash tendered', _n(tendered)), _kv('Change returned', _n(change), w: FontWeight.w700)],
      ] else ...[
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 112,
            height: 112,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF111111), width: 1.5)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.qr_code_2, size: 64, color: Color(0xFF111111)),
              Text(inr(total), style: _m(10)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        _c('Scan to pay · bistro21@okhdfc', _m(11)),
      ],
      const SizedBox(height: 14),
      _c('Thank you! Visit again', _m(12, FontWeight.w600)),
      _c('Rupees ${_words(total.round())} Only', grey.copyWith(fontSize: 10)),
    ];
  }
}

/// Shows KOT and/or bill. Returns true if Print was tapped (and the simulated send completed).
Future<bool> showPrintPreview(BuildContext context,
    {ReceiptData? kot, ReceiptData? bill, bool billFirst = false, String subtitle = '', String? printLabel}) async {
  final s = StoreScope.of(context);
  bool isBill = billFirst || kot == null;
  bool sending = false;
  String? sentTo;
  final r = await showPanelDialog<bool>(context,
      maxWidth: 520,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
            final d = isBill ? bill! : kot!;
            final both = kot != null && bill != null;
            final title = d.isKot ? 'KOT #${d.no}' : (d.payments.isNotEmpty ? 'Tax invoice ${d.no}' : 'Bill ${d.no}');
            final candidates = isBill ? s.billPrinters : s.kotPrinters;
            final printer = candidates.isEmpty ? null : candidates.first;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
                child: Row(children: [
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: ts(18, w: w5)),
                    if (subtitle.isNotEmpty) Text(subtitle, style: ts(13, c: C.muted)),
                  ])),
                  if (both)
                    Seg<bool>(
                        items: const [(false, 'KOT'), (true, 'Bill')], value: isBill, height: 34, onChanged: (v) => set(() => isBill = v)),
                  const SizedBox(width: 8),
                  RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(ctx, false)),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFE9E9E9),
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16), child: Center(child: ReceiptView(d))),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          printer == null ? 'No ${isBill ? 'bill' : 'KOT'} printer set up · see Settings' : 'Printer · ${printer.name}',
                          maxLines: 2, style: ts(13, c: printer == null ? C.red : C.muted))),
                  Btn.outline('Close', height: 48, onTap: () => Navigator.pop(ctx, false)),
                  const SizedBox(width: 10),
                  Btn(sending ? 'Sending…' : (printLabel ?? (isBill ? 'Print bill' : 'Print KOT')),
                      icon: sending ? null : Icons.print_outlined,
                      height: 48,
                      onTap: printer == null || sending
                          ? null
                          : () async {
                              set(() => sending = true);
                              await Future.delayed(const Duration(milliseconds: 550));
                              sentTo = printer.name;
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            }),
                ]),
              ),
            ]);
          }));
  if (r == true && context.mounted) toast(context, '${isBill ? 'Bill' : 'KOT'} sent to ${sentTo ?? 'printer'}');
  return r == true;
}
