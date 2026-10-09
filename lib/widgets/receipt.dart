import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart' as esc;
import '../models.dart';
import '../print_layout.dart';
import '../store.dart';
import '../theme.dart';
import 'common.dart';
import 'keys.dart';

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
  final String businessName, businessAddress, businessPhone;
  final int pax;
  final DateTime at;
  final List<ReceiptLine> lines;
  final double fee;
  /// Bill only: flat ₹ knocked off the subtotal before tax, and why.
  final double discount;
  final String discountReason;
  final List<Payment> payments;
  final bool reprint;
  /// KOT only: normal, cancellation, or modified item.
  final KotKind kind;
  /// KOT only: units the kitchen should stop making.
  final List<ReceiptLine> voided;
  final String reason, by;
  /// KOT only: kitchen section this ticket is for, and its display name.
  final String? groupId;
  final String group;
  /// KOT only, when one send made several KOTs: this is [part] of [parts], and
  /// [others] names the rest ("Bread #13") so the kitchen knows to look for them.
  final int part, parts;
  final List<String> others;

  const ReceiptData({
    required this.isKot,
    required this.no,
    required this.type,
    required this.where,
    required this.server,
    required this.pax,
    required this.at,
    required this.lines,
    this.businessName = '',
    this.businessAddress = '',
    this.businessPhone = '',
    this.customer = '',
    this.fee = 0,
    this.discount = 0,
    this.discountReason = '',
    this.payments = const [],
    this.reprint = false,
    this.kind = KotKind.order,
    this.voided = const [],
    this.reason = '',
    this.by = '',
    this.groupId,
    this.group = '',
    this.part = 0,
    this.parts = 0,
    this.others = const [],
  });

  factory ReceiptData.kot(Store s, Order o, Kot k, {bool reprint = false}) => ReceiptData(
        isKot: true,
        no: '${k.no}',
        type: o.type,
        where: s.labelOf(o),
        server: o.server,
        businessName: s.outletName,
        pax: o.type == OrderType.dineIn ? o.pax : 0,
        at: k.at,
        customer: o.customer,
        reprint: reprint,
        kind: k.kind,
        reason: k.reason,
        by: k.by,
        groupId: k.group,
        group: s.kotGroup(k.group)?.name ?? '',
        part: k.batch.length > 1 ? k.batch.indexOf(k.no) + 1 : 0,
        parts: k.batch.length > 1 ? k.batch.length : 0,
        others: [
          if (k.batch.length > 1)
            for (final n in k.batch)
              if (n != k.no) _kotLabel(s, n),
        ],
        // What's still to be made: units cancelled since are on their own cancellation KOT.
        lines: [
          for (final l in k.lines)
            if (l.activeQty > 0) ReceiptLine(l.activeQty, l.item.name, l.unit, l.mods, l.note),
        ],
        voided: k.voided.map((l) => ReceiptLine(l.qty, l.item.name, l.unit, l.mods, l.note)).toList(),
      );

  /// [payments] defaults to what's already been paid on the order, so a reprint
  /// of a prepaid bill still reads as a paid tax invoice.
  factory ReceiptData.bill(Store s, Order o, {List<Payment>? payments, String? no}) {
    final merged = <String, ReceiptLine>{};
    for (final l in o.liveLines) {
      final key = '${l.item.id}|${l.optText}';
      final ex = merged[key];
      if (ex != null) {
        ex.qty += l.activeQty;
      } else {
        merged[key] = ReceiptLine(l.activeQty, l.item.name, l.unit, l.mods, '');
      }
    }
    return ReceiptData(
      isKot: false,
      no: no ?? s.previewBillNo(o),
      type: o.type,
      where: s.labelOf(o),
      server: o.server,
      businessName: s.outletName,
      businessAddress: s.outletAddress,
      businessPhone: s.outletPhone,
      pax: o.type == OrderType.dineIn ? o.pax : 0,
      at: DateTime.now(),
      customer: [o.customer, o.phone].where((x) => x.isNotEmpty).join(' · '),
      fee: o.fee,
      discount: o.discountAmount,
      discountReason: o.discountReason ?? '',
      payments: payments ?? o.payments,
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

/// Where the auto-cutter cuts, drawn at the bottom of the preview.
class _CutLine extends StatelessWidget {
  const _CutLine();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 22,
        child: Row(children: [
          const Icon(Icons.content_cut, size: 14, color: Color(0xFFB0B0B0)),
          const SizedBox(width: 4),
          Expanded(
            child: LayoutBuilder(builder: (c, cons) {
              final n = (cons.maxWidth / 8).floor();
              return Row(
                  children: List.generate(
                      n, (_) => Container(width: 4, height: 1, margin: const EdgeInsets.only(right: 4), color: const Color(0xFFB0B0B0))));
            }),
          ),
        ]),
      );
}

class ReceiptView extends StatelessWidget {
  final ReceiptData d;
  final PrintLayout layout;
  ReceiptView(this.d, {super.key, PrintLayout? layout}) : layout = layout ?? PrintLayout();

  bool get _narrow => layout.paperMm == 58;

  TextStyle _m(double s, [FontWeight w = FontWeight.w400, Color c = const Color(0xFF111111)]) => TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New', 'Courier', 'Menlo'],
      fontSize: _narrow ? s * .9 : s,
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

  /// One printer text line at preview scale, used to draw the top/bottom feed.
  double get _lineH => (_narrow ? 12 * .9 : 12) * 1.45;

  @override
  Widget build(BuildContext context) => Container(
        width: _narrow ? 226 : 302,
        padding: EdgeInsets.fromLTRB(_narrow ? 12 : 16, 12 + layout.topLines(d.isKot) * _lineH, _narrow ? 12 : 16, 0),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 30, offset: Offset(0, 12))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          ...(d.isKot ? _kot() : _bill()),
          SizedBox(height: layout.bottomLines(d.isKot) * _lineH),
          const _CutLine(),
        ]),
      );

  Widget _kotItem(ReceiptLine line, double size, {String sign = ''}) {
    final l = layout;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 40, child: Text('$sign${line.qty}x', style: _m(size, FontWeight.w700))),
          Expanded(child: Text(l.kotUppercase ? line.name.toUpperCase() : line.name, style: _m(size, FontWeight.w700))),
        ]),
        if (l.kotShowMods)
          for (final m in line.mods) Padding(padding: const EdgeInsets.only(left: 40), child: Text(m, style: _m(13))),
        if (l.kotShowNotes && line.note.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: 40), child: Text('** ${line.note} **', style: _m(13, FontWeight.w700))),
      ]),
    );
  }

  Widget _section(String t) => Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2), child: Text(t, style: _m(11, FontWeight.w700).copyWith(letterSpacing: 1.2)));

  List<Widget> _kot() {
    final l = layout;
    final itemSize = l.kotLargeItems ? 15.0 : 13.0;
    final server = l.kotShowServer && d.server.isNotEmpty ? 'Server: ${d.server}' : '';
    final pax = l.kotShowPax && d.pax > 0 ? 'Pax: ${d.pax}' : '';
    final alert = switch (d.kind) { KotKind.order => '', KotKind.cancel => l.kotCancelTitle.trim(), KotKind.modify => l.kotModifyTitle.trim() };
    int count(List<ReceiptLine> x) => x.fold<int>(0, (a, e) => a + e.qty);
    return [
      if (l.kotTitle.trim().isNotEmpty) _c(l.kotTitle.trim(), _m(11).copyWith(letterSpacing: 1.5)),
      _c('KOT #${d.no}', _m(24, FontWeight.w700)),
      if (l.kotShowGroup && d.group.isNotEmpty) _c(d.group.toUpperCase(), _m(18, FontWeight.w700).copyWith(letterSpacing: 2)),
      if (l.kotShowSplit && d.parts > 1) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF111111), width: 2)),
          child: Column(children: [
            _c('KOT ${d.part} OF ${d.parts}', _m(16, FontWeight.w700).copyWith(letterSpacing: 1)),
            _c('Also: ${d.others.map((x) => x.toUpperCase()).join(' · ')}', _m(12, FontWeight.w600)),
          ]),
        ),
      ],
      if (alert.isNotEmpty) ...[
        const SizedBox(height: 6),
        Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: _c('*** $alert ***', _m(16, FontWeight.w700, Colors.white))),
      ],
      if (l.kotShowBanner) ...[
        const SizedBox(height: 6),
        Center(
            child: Container(
                color: const Color(0xFF111111),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(_banner, style: _m(15, FontWeight.w700, Colors.white)))),
      ],
      const _Dash(),
      _kv(_d(d.at), _t(d.at)),
      if (!l.kotShowBanner) Text(_typeLine, style: _m(12, FontWeight.w700)),
      if (server.isNotEmpty || pax.isNotEmpty) _kv(server, pax),
      if (l.kotShowCustomer && d.customer.isNotEmpty && d.type != OrderType.dineIn) Text('Customer: ${d.customer}', style: _m(12)),
      if (d.reprint) _c('*** REPRINT ***', _m(12, FontWeight.w700)),
      const _Dash(),
      if (d.voided.isNotEmpty) ...[
        _section(d.kind == KotKind.modify ? 'REMOVE' : 'DO NOT MAKE'),
        for (final line in d.voided) _kotItem(line, itemSize, sign: '-'),
      ],
      if (d.voided.isNotEmpty && d.lines.isNotEmpty) ...[const _Dash(), _section('MAKE INSTEAD')],
      for (final line in d.lines) _kotItem(line, itemSize, sign: d.kind == KotKind.modify ? '+' : ''),
      if (l.kotShowReason && (d.reason.isNotEmpty || d.by.isNotEmpty)) ...[
        const _Dash(),
        if (d.reason.isNotEmpty) Text('Reason: ${d.reason}', style: _m(12, FontWeight.w600)),
        if (d.by.isNotEmpty) Text('By: ${d.by}', style: _m(12)),
      ],
      const _Dash(),
      if (l.kotShowTotal) ...[
        if (d.voided.isNotEmpty) _kv('Items cancelled', '${count(d.voided)}', w: FontWeight.w600),
        if (d.kind != KotKind.cancel) _kv(d.kind == KotKind.modify ? 'Items to make' : 'Total items', '${count(d.lines)}', w: FontWeight.w600),
      ],
      if (l.kotShowSplit && d.parts > 1) _c('** ${d.parts - 1} more KOT${d.parts > 2 ? 's' : ''} for this order **', _m(12, FontWeight.w700)),
      for (final f in PrintLayout.linesOf(l.kotFooter)) _c(f, _m(12)),
      if (l.kotShowOutlet && d.businessName.isNotEmpty) ...[
        const SizedBox(height: 12),
        _c('— ${d.businessName} —', _m(11).copyWith(letterSpacing: 1)),
      ],
    ];
  }

  List<Widget> _bill() {
    final l = layout;
    final t = BillTotals.of(d);
    final grey = _m(11, FontWeight.w400, const Color(0xFF444444));
    final name = l.billName.trim().isNotEmpty ? l.billName.trim() : d.businessName;
    final server = l.billShowServer && d.server.isNotEmpty ? 'Server: ${d.server}' : '';
    final pax = l.billShowPax && d.pax > 0 ? 'Pax: ${d.pax}' : '';
    final title = (d.payments.isNotEmpty ? l.billTitlePaid : l.billTitleUnpaid).trim();
    final qtyW = _narrow ? 24.0 : 30.0, rateW = _narrow ? 44.0 : 56.0, amtW = _narrow ? 56.0 : 66.0;
    return [
      if (l.billShowName && name.isNotEmpty) _c(name, _m(17, FontWeight.w700)),
      if (l.billShowAddress && d.businessAddress.isNotEmpty) _c(d.businessAddress, _m(12)),
      if (l.billShowPhone && d.businessPhone.isNotEmpty) _c('Ph: ${d.businessPhone}', _m(12)),
      for (final h in PrintLayout.linesOf(l.billHeader)) _c(h, _m(12)),
      if (title.isNotEmpty) ...[
        const SizedBox(height: 8),
        _c(title, _m(12, FontWeight.w700).copyWith(letterSpacing: 1.5)),
      ],
      const _Dash(),
      _kv('Bill No: ${d.no}', _d(d.at)),
      _kv(_typeLine, _t(d.at)),
      if (server.isNotEmpty || pax.isNotEmpty) _kv(server, pax),
      if (l.billShowCustomer && d.customer.isNotEmpty) Text('Customer: ${d.customer}', style: _m(12)),
      const _Dash(),
      Row(children: [
        Expanded(child: Text('ITEM', style: _m(11, FontWeight.w600))),
        SizedBox(width: qtyW, child: Text('QTY', textAlign: TextAlign.right, style: _m(11, FontWeight.w600))),
        if (l.billShowRate) SizedBox(width: rateW, child: Text('RATE', textAlign: TextAlign.right, style: _m(11, FontWeight.w600))),
        SizedBox(width: amtW, child: Text('AMT', textAlign: TextAlign.right, style: _m(11, FontWeight.w600))),
      ]),
      const _Dash(),
      for (final line in d.lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(line.name, style: _m(12))),
              SizedBox(width: qtyW, child: Text('${line.qty}', textAlign: TextAlign.right, style: _m(12))),
              if (l.billShowRate)
                SizedBox(width: rateW, child: Text(_n(line.rate, false), textAlign: TextAlign.right, style: _m(12))),
              SizedBox(width: amtW, child: Text(_n(line.qty * line.rate), textAlign: TextAlign.right, style: _m(12))),
            ]),
            if (l.billShowMods)
              for (final m in line.mods) Padding(padding: const EdgeInsets.only(left: 8), child: Text(m, style: grey)),
          ]),
        ),
      const _Dash(),
      _kv('Subtotal (${t.items} items)', _n(t.sub)),
      if (t.discount > 0) _kv('Discount${d.discountReason.isEmpty ? '' : ' · ${d.discountReason}'}', '-${_n(t.discount)}'),
      if (l.billSplitGst) ...[
        _kv('CGST @2.5%', _n(t.tax / 2)),
        _kv('SGST @2.5%', _n(t.tax / 2)),
      ] else
        _kv('GST @5%', _n(t.tax)),
      if (d.fee > 0) _kv('Delivery charge', _n(d.fee)),
      if (l.billShowRoundOff) _kv('Round off', '${t.round >= 0 ? '+' : '-'}${_n(t.round.abs())}'),
      const _Dash(),
      _kv('TOTAL', inr(t.total, decimals: true), s: 18, w: FontWeight.w700),
      const _Dash(),
      if (d.payments.isNotEmpty) ...[
        for (final p in d.payments) _kv('Paid · ${p.method}', _n(p.amount)),
        if (t.tendered > 0) ...[_kv('Cash tendered', _n(t.tendered)), _kv('Change returned', _n(t.change), w: FontWeight.w700)],
      ] else if (l.billShowQr && l.billUpi != null) ...[
        const SizedBox(height: 6),
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(2),
            child: QrImageView(
                data: l.billUpi!.uri(t.total.roundToDouble(), note: 'Bill ${d.no}'),
                size: _narrow ? 120 : 150,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        _c('Scan to pay ${inr(t.total, decimals: true)}', _m(11, FontWeight.w600)),
        _c(l.billUpi!.vpa, _m(10)),
      ],
      const SizedBox(height: 14),
      for (final f in PrintLayout.linesOf(l.billFooter)) _c(f, _m(12, FontWeight.w600)),
      if (d.type == OrderType.takeaway)
        for (final f in PrintLayout.linesOf(l.billFooterTakeaway)) _c(f, _m(12, FontWeight.w600)),
      if (l.billShowWords) _c('Rupees ${_words(t.total.round())} Only', grey.copyWith(fontSize: _narrow ? 9 : 10)),
    ];
  }
}

/// Bill arithmetic shared by the preview and the ESC/POS renderer. Mirrors
/// Order's own getters (lib/models.dart) exactly — tax and total are
/// computed on the subtotal *after* discount, same as what's charged/synced.
class BillTotals {
  final int items;
  final double sub, discount, tax, total, round, tendered, change;
  const BillTotals._(this.items, this.sub, this.discount, this.tax, this.total, this.round, this.tendered, this.change);

  factory BillTotals.of(ReceiptData d) {
    final sub = d.lines.fold<double>(0, (a, l) => a + l.qty * l.rate);
    final discount = d.discount.clamp(0, sub).toDouble();
    final discountedSub = sub - discount;
    final tax = discountedSub * .05, raw = discountedSub + tax + d.fee, total = raw.roundToDouble();
    final cash = d.payments.where((p) => p.method == 'Cash' && p.tendered > 0).toList();
    return BillTotals._(
      d.lines.fold<int>(0, (a, l) => a + l.qty),
      sub,
      discount,
      tax,
      total,
      total - raw,
      cash.fold<double>(0, (a, p) => a + p.tendered),
      cash.fold<double>(0, (a, p) => a + p.change),
    );
  }
}

/// Thermal printers run a single-byte code page, so anything outside ASCII is mapped or dropped.
String _ascii(String s) => s
    .replaceAll('·', '-')
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('₹', 'Rs.')
    .replaceAll(RegExp(r'[^\x20-\x7E]'), '');

/// Renders [d] as ESC/POS bytes, mirroring [ReceiptView]'s layout. Repeats the
/// ticket [PrintLayout.billCopies] / [PrintLayout.kotCopies] times.
Future<List<int>> receiptBytes(ReceiptData d, {PrintLayout? layout}) async {
  final l = layout ?? PrintLayout();
  final paper = l.paperMm == 58 ? esc.PaperSize.mm58 : esc.PaperSize.mm80;
  final t = await esc.Ticket.create(paper);
  const b = esc.PrintTextStyle(bold: true);
  const big = esc.PrintTextStyle(bold: true, height: esc.TextSize.size2, width: esc.TextSize.size2);
  const tall = esc.PrintTextStyle(bold: true, height: esc.TextSize.size2);
  final dash = '-' * (paper == esc.PaperSize.mm58 ? 32 : 48);
  void c(String s, [esc.PrintTextStyle st = const esc.PrintTextStyle()]) => t.text(_ascii(s), align: esc.PrintAlign.center, style: st);
  String n(double v, [bool dec = true]) => inr(v, decimals: dec).substring(1);

  // Every line goes out as ONE plain text command, padded with spaces to the
  // paper width. The library's table rows (t.row) position each column and,
  // for bold columns, go back with a carriage return and print the text again
  // to darken it; 2-inch printers that treat that CR as a line feed print every
  // bold line twice (KOT items came out doubled). Plain padded lines behave the
  // same on every printer, and bold on a full line uses the normal ESC E.
  final chars = paper == esc.PaperSize.mm58 ? 32 : 48;
  int width(esc.PrintTextStyle st) => st.width == esc.TextSize.size2 ? chars ~/ 2 : chars;

  /// Word-wraps [s] into lines of at most [w] characters (long words are cut).
  List<String> wrap(String s, int w) {
    final out = <String>[];
    var cur = '';
    for (var word in s.split(RegExp(r'\s+')).where((x) => x.isNotEmpty)) {
      while (word.length > w) {
        if (cur.isNotEmpty) {
          out.add(cur);
          cur = '';
        }
        out.add(word.substring(0, w));
        word = word.substring(w);
      }
      if (cur.isEmpty) {
        cur = word;
      } else if (cur.length + 1 + word.length <= w) {
        cur = '$cur $word';
      } else {
        out.add(cur);
        cur = word;
      }
    }
    if (cur.isNotEmpty || out.isEmpty) out.add(cur);
    return out;
  }

  /// Label on the left, value on the right of the same line.
  void kv(String a, String v, [esc.PrintTextStyle st = const esc.PrintTextStyle()]) {
    final w = width(st);
    a = _ascii(a);
    v = _ascii(v);
    if (a.length + 1 + v.length <= w) {
      t.text('$a${' ' * (w - a.length - v.length)}$v', style: st);
    } else {
      for (final x in wrap(a, w)) {
        t.text(x, style: st);
      }
      t.text(v.padLeft(w), style: st);
    }
  }

  /// A table line: [first] on the left (wrapping onto following lines), then
  /// right-aligned columns of fixed [right] widths.
  void cols(String first, List<(String, int)> right, [esc.PrintTextStyle st = const esc.PrintTextStyle()]) {
    final fw = width(st) - right.fold<int>(0, (a, c) => a + c.$2);
    final parts = wrap(_ascii(first), fw - 1);
    t.text(parts.first.padRight(fw) + right.map((c) => _ascii(c.$1).padLeft(c.$2)).join(), style: st);
    for (final p in parts.skip(1)) {
      t.text(p, style: st);
    }
  }

  /// [prefix] then [s], with wrapped lines hanging under the text at [indent].
  void hang(String prefix, String s, int indent, [esc.PrintTextStyle st = const esc.PrintTextStyle()]) {
    final parts = wrap(_ascii(s), width(st) - indent);
    for (var i = 0; i < parts.length; i++) {
      t.text((i == 0 ? _ascii(prefix).padRight(indent) : ' ' * indent) + parts[i], style: st);
    }
  }
  final where = switch (d.type) {
    OrderType.dineIn => 'DINE IN - ${d.where}',
    OrderType.takeaway => 'TAKEAWAY - ${d.where}',
    OrderType.delivery => 'DELIVERY - ${d.where}',
  };
  final items = d.lines.fold<int>(0, (a, x) => a + x.qty);
  final copies = d.isKot ? l.kotCopies : l.billCopies;

  for (var copy = 0; copy < copies; copy++) {
    t.feed(l.topLines(d.isKot));
    if (d.isKot) {
      final server = l.kotShowServer && d.server.isNotEmpty ? 'Server: ${d.server}' : '';
      final pax = l.kotShowPax && d.pax > 0 ? 'Pax: ${d.pax}' : '';
      final itemStyle = l.kotLargeItems ? tall : b;
      final alert = switch (d.kind) { KotKind.order => '', KotKind.cancel => l.kotCancelTitle.trim(), KotKind.modify => l.kotModifyTitle.trim() };
      int count(List<ReceiptLine> x) => x.fold<int>(0, (a, e) => a + e.qty);
      void item(ReceiptLine line, String sign) {
        final qty = '$sign${line.qty}x';
        final indent = qty.length + 1 < 4 ? 4 : qty.length + 1;
        hang(qty, l.kotUppercase ? line.name.toUpperCase() : line.name, indent, itemStyle);
        if (l.kotShowMods) {
          for (final m in line.mods) {
            hang('', m, indent);
          }
        }
        if (l.kotShowNotes && line.note.isNotEmpty) hang('', '** ${line.note} **', indent, b);
      }

      if (l.kotTitle.trim().isNotEmpty) c(l.kotTitle.trim());
      c('KOT #${d.no}', big);
      if (l.kotShowGroup && d.group.isNotEmpty) c(d.group.toUpperCase(), big);
      if (l.kotShowSplit && d.parts > 1) {
        c('KOT ${d.part} OF ${d.parts}', esc.PrintTextStyle(bold: true, reverse: true, height: esc.TextSize.size2));
        c(_ascii('Also: ${d.others.map((x) => x.toUpperCase()).join(', ')}'), b);
      }
      if (alert.isNotEmpty) c('*** $alert ***', esc.PrintTextStyle(bold: true, reverse: true, height: esc.TextSize.size2));
      if (l.kotShowBanner) c(where, esc.PrintTextStyle(bold: true, reverse: true, height: esc.TextSize.size2));
      t.text(dash);
      kv(_d(d.at), _t(d.at));
      if (!l.kotShowBanner) t.text(_ascii(where), style: b);
      if (server.isNotEmpty || pax.isNotEmpty) kv(server, pax);
      if (l.kotShowCustomer && d.customer.isNotEmpty && d.type != OrderType.dineIn) t.text(_ascii('Customer: ${d.customer}'));
      if (d.reprint) c('*** REPRINT ***', b);
      t.text(dash);
      if (d.voided.isNotEmpty) {
        t.text(d.kind == KotKind.modify ? 'REMOVE' : 'DO NOT MAKE', style: b);
        for (final line in d.voided) {
          item(line, '-');
        }
      }
      if (d.voided.isNotEmpty && d.lines.isNotEmpty) {
        t.text(dash);
        t.text('MAKE INSTEAD', style: b);
      }
      for (final line in d.lines) {
        item(line, d.kind == KotKind.modify ? '+' : '');
      }
      if (l.kotShowReason && (d.reason.isNotEmpty || d.by.isNotEmpty)) {
        t.text(dash);
        if (d.reason.isNotEmpty) t.text(_ascii('Reason: ${d.reason}'), style: b);
        if (d.by.isNotEmpty) t.text(_ascii('By: ${d.by}'));
      }
      t.text(dash);
      if (l.kotShowTotal) {
        if (d.voided.isNotEmpty) kv('Items cancelled', '${count(d.voided)}', b);
        if (d.kind != KotKind.cancel) kv(d.kind == KotKind.modify ? 'Items to make' : 'Total items', '${count(d.lines)}', b);
      }
      if (l.kotShowSplit && d.parts > 1) c('** ${d.parts - 1} more KOT${d.parts > 2 ? 's' : ''} for this order **', b);
      for (final f in PrintLayout.linesOf(l.kotFooter)) {
        c(f);
      }
      if (l.kotShowOutlet && d.businessName.isNotEmpty) c('- ${d.businessName} -');
    } else {
      final tot = BillTotals.of(d);
      final name = l.billName.trim().isNotEmpty ? l.billName.trim() : d.businessName;
      final server = l.billShowServer && d.server.isNotEmpty ? 'Server: ${d.server}' : '';
      final pax = l.billShowPax && d.pax > 0 ? 'Pax: ${d.pax}' : '';
      final title = (d.payments.isNotEmpty ? l.billTitlePaid : l.billTitleUnpaid).trim();
      if (l.billShowName && name.isNotEmpty) c(name, tall);
      if (l.billShowAddress && d.businessAddress.isNotEmpty) c(d.businessAddress);
      if (l.billShowPhone && d.businessPhone.isNotEmpty) c('Ph: ${d.businessPhone}');
      for (final h in PrintLayout.linesOf(l.billHeader)) {
        c(h);
      }
      if (title.isNotEmpty) c(title, b);
      t.text(dash);
      kv('Bill No: ${d.no}', _d(d.at));
      kv(where, _t(d.at));
      if (server.isNotEmpty || pax.isNotEmpty) kv(server, pax);
      if (l.billShowCustomer && d.customer.isNotEmpty) t.text(_ascii('Customer: ${d.customer}'));
      t.text(dash);
      // Number columns, in characters: QTY, RATE, AMT (fits 12,345.00 on 58 mm).
      final (qw, rw, aw) = chars == 32 ? (4, 7, 9) : (5, 9, 11);
      cols('ITEM', [('QTY', qw), if (l.billShowRate) ('RATE', rw), ('AMT', aw)], b);
      t.text(dash);
      for (final line in d.lines) {
        cols(line.name, [
          ('${line.qty}', qw),
          if (l.billShowRate) (n(line.rate, false), rw),
          (n(line.qty * line.rate), aw),
        ]);
        if (l.billShowMods) {
          for (final m in line.mods) {
            t.text(_ascii('  $m'));
          }
        }
      }
      t.text(dash);
      kv('Subtotal ($items items)', n(tot.sub));
      if (tot.discount > 0) kv('Discount${d.discountReason.isEmpty ? '' : ' · ${d.discountReason}'}', '-${n(tot.discount)}');
      if (l.billSplitGst) {
        kv('CGST @2.5%', n(tot.tax / 2));
        kv('SGST @2.5%', n(tot.tax / 2));
      } else {
        kv('GST @5%', n(tot.tax));
      }
      if (d.fee > 0) kv('Delivery charge', n(d.fee));
      if (l.billShowRoundOff) kv('Round off', '${tot.round >= 0 ? '+' : '-'}${n(tot.round.abs())}');
      t.text(dash);
      kv('TOTAL', 'Rs.${n(tot.total)}', tall);
      t.text(dash);
      for (final p in d.payments) {
        kv('Paid - ${p.method}', n(p.amount));
      }
      if (tot.tendered > 0) {
        kv('Cash tendered', n(tot.tendered));
        kv('Change returned', n(tot.change), b);
      }
      final upi = l.billUpi;
      if (d.payments.isEmpty && l.billShowQr && upi != null) {
        t.feed();
        t.qrcode(upi.uri(tot.total.roundToDouble(), note: 'Bill ${d.no}'),
            size: paper == esc.PaperSize.mm58 ? esc.QRSize.size5 : esc.QRSize.size6, cor: esc.QRCorrection.M);
        c('Scan to pay Rs.${n(tot.total)}', b);
        c(upi.vpa);
      }
      t.feed();
      for (final f in PrintLayout.linesOf(l.billFooter)) {
        c(f, b);
      }
      if (d.type == OrderType.takeaway) {
        for (final f in PrintLayout.linesOf(l.billFooterTakeaway)) {
          c(f, b);
        }
      }
      if (l.billShowWords) c('Rupees ${_words(tot.total.round())} Only');
    }
    t.cut(linesBefore: l.bottomLines(d.isKot));
  }
  return t.bytes;
}

/// Prints [d] for real: a KOT goes to its KOT group's printers (see Settings › KOT groups), a bill to the
/// first "Print bills" printer. Returns the printer names that printed, or throws with the
/// reason when none did.
Future<List<String>> printReceipt(Store s, ReceiptData d, {PrintLayout? layout}) async {
  final targets = d.isKot ? s.kotPrintersFor(d.groupId) : s.billPrinters.take(1).toList();
  if (targets.isEmpty) throw 'No ${d.isKot ? 'KOT' : 'bill'} printer set up · see Settings › Printers';
  final bytes = await receiptBytes(d, layout: layout ?? s.printLayout);
  final ok = <String>[], errors = <String>[];
  for (final p in targets) {
    final err = await s.sendToPrinter(p, bytes);
    err == null ? ok.add(p.name) : errors.add('${p.name}: $err');
  }
  if (ok.isEmpty) throw errors.join('\n');
  return ok;
}

/// Prints [d] without any preview and reports the outcome as a toast.
Future<bool> printReceiptWithToast(BuildContext context, Store s, ReceiptData d) async {
  final what = d.isKot ? 'KOT #${d.no}' : 'Bill ${d.no}';
  try {
    final sentTo = await printReceipt(s, d);
    if (context.mounted) toast(context, '$what printed · ${sentTo.join(', ')}');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$what not printed · $e', error: true);
    return false;
  }
}

/// Shows KOT and/or bill. Returns true if Print was tapped and the ticket printed.
Future<bool> showPrintPreview(BuildContext context,
    {ReceiptData? kot, ReceiptData? bill, bool billFirst = false, String subtitle = '', String? printLabel, bool canPrint = true, String? skipLabel, VoidCallback? onSkip}) async {
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
            final candidates = isBill ? s.billPrinters : s.kotPrintersFor(d.groupId);
            final printer = candidates.isEmpty ? null : candidates.first;
            Future<void> doPrint() async {
              if (!canPrint || printer == null || sending) return;
              set(() => sending = true);
              try {
                sentTo = (await printReceipt(s, d)).join(', ');
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                set(() => sending = false);
                if (ctx.mounted) toast(ctx, 'Not printed · $e', error: true);
              }
            }

            return KeyScope(
                autofocus: true,
                keys: [
                  Hotkey(const SingleActivator(LogicalKeyboardKey.enter), doPrint),
                  Hotkey(const SingleActivator(LogicalKeyboardKey.numpadEnter), doPrint),
                  Hotkey(const SingleActivator(LogicalKeyboardKey.keyP, control: true), doPrint),
                  if (both) ...[
                    Hotkey(const SingleActivator(LogicalKeyboardKey.keyK, alt: true), () => set(() => isBill = false)),
                    Hotkey(const SingleActivator(LogicalKeyboardKey.keyB, alt: true), () => set(() => isBill = true)),
                  ],
                ],
                child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16), child: Center(child: ReceiptView(d, layout: s.printLayout))),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          !canPrint
                              ? 'Printing happens at the main POS'
                              : printer == null
                                  ? 'No ${isBill ? 'bill' : 'KOT'} printer set up · see Settings'
                                  : 'Printer · ${printer.name}',
                          maxLines: 2,
                          style: ts(13, c: canPrint && printer == null ? C.red : C.muted))),
                  Btn.outline('Close', height: 48, onTap: () => Navigator.pop(ctx, false)),
                  if (skipLabel != null && onSkip != null) ...[
                    const SizedBox(width: 10),
                    Btn.outline(skipLabel, height: 48, onTap: () {
                      Navigator.pop(ctx, false);
                      onSkip();
                    }),
                  ],
                  if (canPrint) ...[
                    const SizedBox(width: 10),
                  Btn(sending ? 'Sending…' : (printLabel ?? (isBill ? 'Print bill' : 'Print KOT')),
                      icon: sending ? null : Icons.print_outlined,
                      height: 48,
                      onTap: printer == null || sending ? null : doPrint),
                  ],
                ]),
              ),
            ]));
          }));
  if (r == true && context.mounted) toast(context, '${isBill ? 'Bill' : 'KOT'} sent to ${sentTo ?? 'printer'}');
  return r == true;
}

/// Prints several KOTs (one order split across KOT groups) and reports them in
/// one toast: which went out, and which failed and why.
Future<bool> printKotsWithToast(BuildContext context, Store s, List<ReceiptData> kots) async {
  if (kots.isEmpty) return true;
  final ok = <String>[], failed = <String>[];
  for (final d in kots) {
    final what = 'KOT #${d.no}${d.group.isEmpty ? '' : ' ${d.group}'}';
    try {
      final to = await printReceipt(s, d);
      ok.add('$what → ${to.join(', ')}');
    } catch (e) {
      failed.add('$what: $e');
    }
  }
  if (context.mounted) {
    toast(context, failed.isEmpty ? 'Printed · ${ok.join(' · ')}' : 'Not printed · ${failed.join(' · ')}', error: failed.isNotEmpty);
  }
  return failed.isEmpty;
}

/// "Bread #13" for a sibling KOT, or "#13" when it has no group.
String _kotLabel(Store s, int no) {
  for (final k in s.kots) {
    if (k.no == no) {
      final g = s.kotGroup(k.group);
      return g == null ? '#$no' : '${g.name} #$no';
    }
  }
  return '#$no';
}
