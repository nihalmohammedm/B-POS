import 'dart:convert';
import 'package:flutter/material.dart';
import '../models.dart';
import '../print_layout.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/receipt.dart';

/// Settings › Print layout: edit what the invoice and KOT show, with a live
/// preview of the exact ticket the printer will get.
class PrintLayoutScreen extends StatefulWidget {
  const PrintLayoutScreen({super.key});
  @override
  State<PrintLayoutScreen> createState() => _PrintLayoutScreenState();
}

class _PrintLayoutScreenState extends State<PrintLayoutScreen> {
  late PrintLayout l;
  bool kot = false; // false = invoice tab
  bool showPreview = false; // narrow screens only
  bool samplePaid = false, printing = false;
  _SampleKot sampleKot = _SampleKot.first;
  OrderType sampleType = OrderType.dineIn;
  final _c = <String, TextEditingController>{};

  static const _fields = ['billName', 'billHeader', 'billTitlePaid', 'billTitleUnpaid', 'billFooter', 'kotTitle', 'kotCancelTitle', 'kotModifyTitle', 'kotFooter'];

  @override
  void initState() {
    super.initState();
    l = StoreScope.read(context).printLayout.copy();
    final j = l.toJson();
    for (final f in _fields) {
      _c[f] = TextEditingController(text: j[f] as String);
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _dirty(Store s) => jsonEncode(l.toJson()) != jsonEncode(s.printLayout.toJson());

  void _edit(void Function() f) => setState(f);

  void _save(Store s) {
    s.setPrintLayout(l);
    toast(context, 'Print layout saved');
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(context,
        title: 'Reset ${kot ? 'KOT' : 'invoice'} layout?',
        body: 'Puts every ${kot ? 'KOT' : 'invoice'} option back to the default. Nothing is saved until you tap Save.',
        ok: 'Reset',
        okColor: C.red);
    if (!ok) return;
    final def = PrintLayout().toJson();
    final j = l.toJson()..addAll({for (final e in def.entries) if (e.key.startsWith(kot ? 'kot' : 'bill')) e.key: e.value});
    setState(() {
      l = PrintLayout.fromJson(j);
      for (final f in _fields) {
        _c[f]!.text = j[f] as String;
      }
    });
  }

  ReceiptData _sample(Store s) {
    final at = DateTime.now();
    final where = switch (sampleType) { OrderType.dineIn => '12', OrderType.takeaway => 'TA-7', OrderType.delivery => '#1042' };
    if (kot) {
      final cancel = sampleKot == _SampleKot.cancel, modify = sampleKot == _SampleKot.modify;
      return ReceiptData(
        isKot: true,
        no: '${s.nextKotNo}',
        type: sampleType,
        where: where,
        server: 'Captain 1',
        pax: sampleType == OrderType.dineIn ? 4 : 0,
        at: at,
        customer: sampleType == OrderType.dineIn ? '' : 'Rahul · 98470 12345',
        businessName: s.outletName,
        reprint: sampleKot == _SampleKot.reprint,
        kind: cancel ? KotKind.cancel : (modify ? KotKind.modify : KotKind.order),
        reason: cancel ? 'Customer changed mind' : (modify ? 'Wrong item entered' : ''),
        by: cancel || modify ? (s.sessionFullName ?? 'Cashier') : '',
        group: 'Grill',
        // A plain new KOT is shown as the first of a split order, to preview the marker.
        part: !cancel && !modify ? 1 : 0,
        parts: !cancel && !modify ? 3 : 0,
        others: !cancel && !modify ? ['Bread #${s.nextKotNo + 1}', 'Drinks #${s.nextKotNo + 2}'] : const [],
        voided: [
          if (cancel) ReceiptLine(2, 'Shawarma', 120, ['+ Garlic sauce'], ''),
          if (modify) ReceiptLine(1, 'Alfaham', 300, ['> 1 Half', '+ Mayo'], ''),
        ],
        lines: [
          if (modify) ReceiptLine(1, 'Alfaham', 550, ['> 1 Full', '+ Mayo'], 'Extra spicy'),
          if (!cancel && !modify) ...[
            ReceiptLine(1, 'Alfaham 1 Half', 300, ['Mayo', 'Extra spicy'], ''),
            ReceiptLine(2, 'Shawarma', 120, ['+ Garlic sauce'], 'Less spicy'),
          ],
        ],
      );
    }
    final lines = [
      ReceiptLine(1, 'Alfaham 1 Half', 300, ['Mayo'], ''),
      ReceiptLine(2, 'Porotta', 20, [], ''),
      ReceiptLine(1, 'Chicken Fried Rice', 180, [], ''),
      ReceiptLine(1, 'Fresh Lime', 60, ['No sugar'], ''),
    ];
    final fee = sampleType == OrderType.delivery ? 40.0 : 0.0;
    final total = BillTotals.of(ReceiptData(
            isKot: false, no: '', type: sampleType, where: '', server: '', pax: 0, at: at, lines: lines, fee: fee))
        .total;
    return ReceiptData(
      isKot: false,
      no: 'B101',
      type: sampleType,
      where: where,
      server: 'Captain 1',
      pax: sampleType == OrderType.dineIn ? 4 : 0,
      at: at,
      customer: sampleType == OrderType.dineIn ? '' : 'Rahul · 98470 12345',
      businessName: s.outletName.isEmpty ? 'Your Restaurant' : s.outletName,
      businessAddress: s.outletAddress.isEmpty ? 'Street, City' : s.outletAddress,
      businessPhone: s.outletPhone.isEmpty ? '00000 00000' : s.outletPhone,
      fee: fee,
      payments: samplePaid ? [Payment('Cash', total, (total / 100).ceil() * 100.0)] : const [],
      lines: lines,
    );
  }

  Future<void> _testPrint(Store s) async {
    setState(() => printing = true);
    try {
      final sent = await printReceipt(s, _sample(s), layout: l);
      if (mounted) toast(context, 'Sample ${kot ? 'KOT' : 'invoice'} printed · ${sent.join(', ')}');
    } catch (e) {
      if (mounted) toast(context, 'Not printed · $e', error: true);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final dirty = _dirty(s);
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(context,
            title: 'Discard changes?', body: 'Your print layout changes have not been saved.', ok: 'Discard', okColor: C.red);
        // Navigator.pop skips PopScope, unlike the back button's maybePop.
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: LayoutBuilder(builder: (context, cons) {
              final wide = cons.maxWidth >= 900;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(s, dirty, wide),
                const SizedBox(height: 16),
                Expanded(
                  child: wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: _form()),
                          const SizedBox(width: 16),
                          SizedBox(width: 440, child: _preview(s)),
                        ])
                      : (showPreview ? _preview(s) : _form()),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _header(Store s, bool dirty, bool wide) => Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            RoundIcon(Icons.arrow_back, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Back'),
            const SizedBox(width: 14),
            Text('Print layout', style: ts(22, w: w5)),
            if (dirty) ...[const SizedBox(width: 10), const Pill('UNSAVED', bg: C.amberTint, fg: C.amberInk, size: 11)],
          ]),
          Seg<bool>(
              height: 40,
              fontSize: 15,
              items: const [(false, 'Invoice'), (true, 'KOT')],
              value: kot,
              onChanged: (v) => setState(() => kot = v)),
          if (!wide)
            Seg<bool>(
                height: 40,
                fontSize: 15,
                items: const [(false, 'Edit'), (true, 'Preview')],
                value: showPreview,
                onChanged: (v) => setState(() => showPreview = v)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Btn.outline('Reset', icon: Icons.restart_alt, height: 44, onTap: _reset),
            const SizedBox(width: 10),
            Btn('Save', icon: Icons.check, height: 44, onTap: dirty ? () => _save(s) : null),
          ]),
        ],
      );

  // ---------- form ----------

  Widget _form() => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _section('Paper', [
            Row(children: [
              Expanded(child: Text('Paper width', style: ts(15, w: w5))),
              Seg<int>(
                  height: 38,
                  items: const [(58, '58 mm'), (80, '80 mm')],
                  value: l.paperMm,
                  onChanged: (v) => _edit(() => l.paperMm = v)),
            ]),
            const SizedBox(height: 4),
            Text('Applies to both invoices and KOTs.', style: ts(12, c: C.muted)),
            const Divider(height: 28),
            _copies(kot ? l.kotCopies : l.billCopies, (v) => _edit(() => kot ? l.kotCopies = v : l.billCopies = v)),
          ]),
          const SizedBox(height: 14),
          _section('Spacing', [
            _lines('Top margin', 'Blank lines before the ${kot ? 'KOT' : 'invoice'} starts', kot ? l.kotTopLines : l.billTopLines,
                (v) => _edit(() => kot ? l.kotTopLines = v : l.billTopLines = v)),
            const Divider(height: 24),
            _lines('Space before cut', 'Blank lines after the last line, before the paper is cut',
                kot ? l.kotBottomLines : l.billBottomLines, (v) => _edit(() => kot ? l.kotBottomLines = v : l.billBottomLines = v)),
          ]),
          const SizedBox(height: 14),
          ...(kot ? _kotForm() : _billForm()),
        ]),
      );

  List<Widget> _billForm() => [
        _section('When to print', [
          _switch('Takeaway: print bill with the KOT', l.takeawayBillWithKot, (v) => l.takeawayBillWithKot = v,
              sub: 'Bill prints right after the kitchen tickets and waits on Payments until collected'),
        ]),
        const SizedBox(height: 14),
        _section('Header', [
          _switch('Restaurant name', l.billShowName, (v) => l.billShowName = v),
          if (l.billShowName) _field('billName', 'Name on invoice', hint: 'Blank = outlet name from backoffice'),
          _switch('Address', l.billShowAddress, (v) => l.billShowAddress = v),
          _switch('Phone number', l.billShowPhone, (v) => l.billShowPhone = v),
          _field('billHeader', 'Extra header lines', hint: 'GSTIN: 32ABCDE1234F1Z5\nFSSAI: 11234567000123', lines: 3),
          _field('billTitlePaid', 'Title when paid', hint: 'TAX INVOICE'),
          _field('billTitleUnpaid', 'Title before payment', hint: 'BILL · NOT PAID'),
        ]),
        const SizedBox(height: 14),
        _section('Order details', [
          _switch('Server / captain', l.billShowServer, (v) => l.billShowServer = v),
          _switch('Pax', l.billShowPax, (v) => l.billShowPax = v),
          _switch('Customer name & phone', l.billShowCustomer, (v) => l.billShowCustomer = v),
        ]),
        const SizedBox(height: 14),
        _section('Items & totals', [
          _switch('Rate column', l.billShowRate, (v) => l.billShowRate = v),
          _switch('Modifiers under items', l.billShowMods, (v) => l.billShowMods = v),
          _switch('Split GST into CGST + SGST', l.billSplitGst, (v) => l.billSplitGst = v),
          _switch('Round-off line', l.billShowRoundOff, (v) => l.billShowRoundOff = v,
              sub: 'Only hides the line; the total is still rounded'),
          _switch('Pay QR on unpaid bills', l.billShowQr, (v) => l.billShowQr = v),
        ]),
        const SizedBox(height: 14),
        _section('Footer', [
          _field('billFooter', 'Footer lines', hint: 'Thank you! Visit again', lines: 3),
          _switch('Amount in words', l.billShowWords, (v) => l.billShowWords = v),
        ]),
      ];

  List<Widget> _kotForm() => [
        _section('Header', [
          _field('kotTitle', 'Title', hint: 'KITCHEN ORDER TICKET'),
          _switch('KOT group name', l.kotShowGroup, (v) => l.kotShowGroup = v, sub: 'Grill, Bread, Drinks… under the KOT number'),
          _switch('Split marker', l.kotShowSplit, (v) => l.kotShowSplit = v,
              sub: '"KOT 1 of 3 · Also: Bread, Drinks" when an order prints on several KOTs'),
          _switch('Order type banner', l.kotShowBanner, (v) => l.kotShowBanner = v, sub: 'Black DINE IN / TAKEAWAY strip'),
          _switch('Server / captain', l.kotShowServer, (v) => l.kotShowServer = v),
          _switch('Pax', l.kotShowPax, (v) => l.kotShowPax = v),
          _switch('Customer (takeaway / delivery)', l.kotShowCustomer, (v) => l.kotShowCustomer = v),
        ]),
        const SizedBox(height: 14),
        _section('Items', [
          _switch('Large item text', l.kotLargeItems, (v) => l.kotLargeItems = v, sub: 'Double-height on the printer'),
          _switch('Item names in CAPITALS', l.kotUppercase, (v) => l.kotUppercase = v),
          _switch('Modifiers', l.kotShowMods, (v) => l.kotShowMods = v),
          _switch('Kitchen notes', l.kotShowNotes, (v) => l.kotShowNotes = v),
        ]),
        const SizedBox(height: 14),
        _section('Cancelled / changed items', [
          Text('Printed when a sent item is cancelled or edited. Preview with the Cancelled / Changed buttons.',
              style: ts(12, c: C.muted)),
          _field('kotCancelTitle', 'Cancellation heading', hint: 'CANCELLED'),
          _field('kotModifyTitle', 'Changed-item heading', hint: 'ITEM CHANGED'),
          _switch('Reason and who did it', l.kotShowReason, (v) => l.kotShowReason = v),
        ]),
        const SizedBox(height: 14),
        _section('Footer', [
          _switch('Total item count', l.kotShowTotal, (v) => l.kotShowTotal = v),
          _field('kotFooter', 'Footer lines', hint: 'Optional', lines: 2),
          _switch('Outlet name', l.kotShowOutlet, (v) => l.kotShowOutlet = v),
        ]),
      ];

  Widget _section(String title, List<Widget> kids) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: ts(17, w: w5)),
          const SizedBox(height: 10),
          ...kids,
        ]),
      );

  Widget _switch(String label, bool value, void Function(bool) set, {String? sub}) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _edit(() => set(!value)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: ts(15, w: w5)),
                if (sub != null) Text(sub, style: ts(12, c: C.muted)),
              ]),
            ),
            const SizedBox(width: 12),
            Toggle(value: value, scale: .8, onChanged: (v) => _edit(() => set(v))),
          ]),
        ),
      );

  Widget _field(String key, String label, {String hint = '', int lines = 1}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Label(label),
          const SizedBox(height: 6),
          TextField(
            controller: _c[key],
            style: ts(14),
            minLines: lines,
            maxLines: lines,
            decoration: InputDecoration(hintText: hint),
            onChanged: (v) => _edit(() => l = PrintLayout.fromJson(l.toJson()..[key] = v)),
          ),
        ]),
      );

  Widget _copies(int value, void Function(int) set) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Copies per ${kot ? 'KOT' : 'invoice'}', style: ts(15, w: w5)),
            Text('Printed back to back, each with its own cut', style: ts(12, c: C.muted)),
          ]),
        ),
        QtyStepper(value: value, onDec: value > 1 ? () => set(value - 1) : null, onInc: value < 3 ? () => set(value + 1) : null),
      ]);

  Widget _lines(String label, String sub, int value, void Function(int) set) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: ts(15, w: w5)),
            Text(sub, style: ts(12, c: C.muted)),
          ]),
        ),
        const SizedBox(width: 12),
        QtyStepper(
            value: value,
            suffix: ' ln',
            onDec: value > 0 ? () => set(value - 1) : null,
            onInc: value < PrintLayout.maxFeedLines ? () => set(value + 1) : null),
      ]);

  // ---------- preview ----------

  Widget _preview(Store s) {
    final printers = kot ? s.kotPrinters : s.billPrinters.take(1).toList();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: const Color(0xFFE2E2E2), borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Seg<OrderType>(
                height: 34,
                fontSize: 13,
                items: const [(OrderType.dineIn, 'Dine in'), (OrderType.takeaway, 'Takeaway'), (OrderType.delivery, 'Delivery')],
                value: sampleType,
                onChanged: (v) => setState(() => sampleType = v)),
            if (kot)
              Seg<_SampleKot>(
                  height: 34,
                  fontSize: 13,
                  items: const [
                    (_SampleKot.first, 'New'),
                    (_SampleKot.reprint, 'Reprint'),
                    (_SampleKot.cancel, 'Cancelled'),
                    (_SampleKot.modify, 'Changed'),
                  ],
                  value: sampleKot,
                  onChanged: (v) => setState(() => sampleKot = v))
            else
              Seg<bool>(
                  height: 34,
                  fontSize: 13,
                  items: const [(false, 'Unpaid'), (true, 'Paid')],
                  value: samplePaid,
                  onChanged: (v) => setState(() => samplePaid = v)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Center(child: ReceiptView(_sample(s), layout: l)),
          ),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Text(
                printers.isEmpty
                    ? 'No ${kot ? 'KOT' : 'bill'} printer set up'
                    : 'Sample data · prints to ${printers.map((p) => p.name).join(', ')}',
                maxLines: 2,
                style: ts(13, c: printers.isEmpty ? C.red : C.muted),
              ),
            ),
            const SizedBox(width: 10),
            Btn(printing ? 'Printing…' : 'Test print',
                icon: printing ? null : Icons.print_outlined,
                height: 46,
                onTap: printers.isEmpty || printing ? null : () => _testPrint(s)),
          ]),
        ),
      ]),
    );
  }
}

enum _SampleKot { first, reprint, cancel, modify }
