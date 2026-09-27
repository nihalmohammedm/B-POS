import 'package:flutter/material.dart' hide Thumb;
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/receipt.dart';
import 'dialogs.dart';

class OrderTakingScreen extends StatefulWidget {
  final Order? target;
  final VoidCallback? onDone;
  const OrderTakingScreen({super.key, this.target, this.onDone});
  @override
  State<OrderTakingScreen> createState() => _OrderTakingState();
}

class _OrderTakingState extends State<OrderTakingScreen> {
  String? cat;
  String query = '';
  bool vegOnly = false;
  OrderType type = OrderType.dineIn;
  String? tableId, partyKey;
  bool tableError = false;
  Order? existing;
  bool _sheetOpen = false;
  final nameC = TextEditingController(), phoneC = TextEditingController(), addrC = TextEditingController();
  final cart = <OrderLine>[];
  final _tick = ValueNotifier(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _tick.value++;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.target;
    if (t != null) {
      type = t.type;
      if (t.type == OrderType.dineIn) {
        tableId = t.tableId;
        partyKey = t.partyKey;
      } else {
        existing = t;
        nameC.text = t.customer;
        phoneC.text = t.phone;
        addrC.text = t.address;
      }
    }
  }

  @override
  void dispose() {
    nameC.dispose();
    phoneC.dispose();
    addrC.dispose();
    _tick.dispose();
    super.dispose();
  }

  Future<void> add(MenuItem m) async {
    final s = StoreScope.read(context);
    if (s.offReason(m) != null) return;
    if (m.customizable) {
      final l = await showCustomizeDialog(context, m);
      if (l != null) setState(() => _merge(l));
    } else {
      setState(() => _merge(OrderLine(item: m)));
    }
  }

  void _merge(OrderLine l) {
    for (final c in cart) {
      if (c.sameConfig(l)) {
        c.qty += l.qty;
        return;
      }
    }
    cart.add(l);
  }

  Future<void> editLine(OrderLine l) async {
    final r = l.item.customizable ? await showCustomizeDialog(context, l.item, initial: l) : await showNoteDialog(context, l);
    if (r != null) {
      setState(() {
        final i = cart.indexOf(l);
        if (i >= 0) cart[i] = r;
      });
    }
  }

  Future<void> pickTable() async {
    final r = await showTablePicker(context);
    if (r != null) {
      setState(() {
        tableId = r.$1;
        partyKey = r.$2;
        tableError = false;
      });
    }
  }

  void confirm() {
    final s = StoreScope.read(context);
    if (cart.isEmpty) return;
    Order o;
    if (type == OrderType.dineIn) {
      final p = tableId == null || partyKey == null ? null : s.party(tableId!, partyKey!);
      if (p == null) {
        setState(() => tableError = true);
        pickTable();
        return;
      }
      o = s.ensurePartyOrder(s.table(tableId!), p);
      if (o.billed) {
        toast(context, 'Bill already printed · reopen ${s.labelOf(o)} from Tables first');
        return;
      }
    } else {
      if (type == OrderType.delivery && (phoneC.text.trim().isEmpty || addrC.text.trim().isEmpty)) {
        toast(context, 'Add phone and address for delivery');
        return;
      }
      o = existing ?? s.draft(type);
      o
        ..customer = nameC.text.trim()
        ..phone = phoneC.text.trim()
        ..address = addrC.text.trim();
    }
    final k = s.sendKot(o, cart);
    final kotData = ReceiptData.kot(s, o, k);
    final billData = type != OrderType.dineIn ? ReceiptData.bill(s, o) : null;
    if (_sheetOpen) Navigator.of(context).pop();
    setState(() {
      cart.clear();
      existing = null;
      tableId = null;
      partyKey = null;
      nameC.clear();
      phoneC.clear();
      addrC.clear();
    });
    widget.onDone?.call();
    showPrintPreview(context, kot: kotData, bill: billData, subtitle: '${s.labelOf(o)} · sent to kitchen');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return LayoutBuilder(builder: (c, cons) {
      final wide = cons.maxWidth >= 980;
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _menu(s, true)),
          const SizedBox(width: 20),
          SizedBox(width: 390, child: _cartPanel(s)),
        ]);
      }
      return Stack(children: [
        Positioned.fill(child: _menu(s, false)),
        if (cart.isNotEmpty) Positioned(left: 0, right: 0, bottom: 8, child: _cartBar()),
      ]);
    });
  }

  // ---------------- menu ----------------
  Widget _menu(Store s, bool wide) {
    final q = query.trim().toLowerCase();
    final items = s.menu
        .where((m) =>
            (cat == null || m.cat == cat) &&
            (!vegOnly || m.veg) &&
            (q.isEmpty || m.name.toLowerCase().contains(q) || m.code.startsWith(q)))
        .toList();
    final qtyBy = <String, int>{};
    for (final l in cart) {
      qtyBy[l.item.id] = (qtyBy[l.item.id] ?? 0) + l.qty;
    }
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Menu', style: ts(22, w: w5)),
          SizedBox(
            width: 280,
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(hintText: 'Search items or code', prefixIcon: Icon(Icons.search, size: 20)),
            ),
          ),
          FilterChip(
            label: const Text('Veg only'),
            selected: vegOnly,
            onSelected: (v) => setState(() => vegOnly = v),
            avatar: const Dot(color: C.green, square: true),
          ),
          Text('Long-press an item or category to turn it off', style: ts(12, c: C.muted)),
        ]),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200, mainAxisExtent: 104, crossAxisSpacing: 12, mainAxisSpacing: 12),
        delegate: SliverChildListDelegate([_catTile(s, null), for (final c in s.categories) _catTile(s, c)]),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
          child: Row(children: [
            Text(cat ?? 'All items', style: ts(18, w: w5)),
            const SizedBox(width: 8),
            Text('${items.length}', style: ts(14, c: C.muted)),
          ]),
        ),
      ),
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 250, mainAxisExtent: 176, crossAxisSpacing: 12, mainAxisSpacing: 12),
        delegate: SliverChildBuilderDelegate((c, i) => _itemCard(s, items[i], qtyBy[items[i].id] ?? 0), childCount: items.length),
      ),
      if (items.isEmpty)
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.all(40), child: Center(child: Text('No items match', style: ts(14, c: C.muted))))),
      SliverToBoxAdapter(child: SizedBox(height: wide ? 12 : 96)),
    ]);
  }

  Widget _catTile(Store s, String? c) {
    final on = cat == c;
    final off = c != null && s.catOff.contains(c);
    final color = c == null ? C.ink : (off ? const Color(0xFFB5B5B5) : colorForCategory(c).$1);
    final count = c == null ? s.menu.length : s.itemsIn(c).length;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => cat = on ? null : c),
        onLongPress: c == null ? null : () => showCategoryManage(context, c, onAdd: add),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18), border: Border.all(color: on ? Colors.white : Colors.transparent, width: 3)),
          child: Column(mainAxisSize: MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                child: Text((c ?? 'All')[0], style: ts(13, w: w6, c: Colors.white)),
              ),
              const Spacer(),
              if (off)
                const Pill('OFF', bg: Colors.white, fg: C.ink2, size: 11)
              else if (on)
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
            ]),
            const Spacer(),
            Text(c ?? 'All', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(17, w: w5, c: Colors.white)),
            Text('$count items', style: ts(12, c: const Color(0xDDFFFFFF))),
          ]),
        ),
      ),
    );
  }

  Widget _itemCard(Store s, MenuItem m, int qty) {
    final reason = s.offReason(m);
    return Opacity(
      opacity: reason != null ? .5 : 1,
      child: Material(
        color: reason != null ? C.soft : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: reason != null ? null : () => add(m),
          onLongPress: () => showItemManage(context, m, onAdd: () => add(m)),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: qty > 0 ? C.sky : C.line, width: qty > 0 ? 2 : 1)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Thumb(m, size: 44),
                const Spacer(),
                if (reason != null)
                  Pill(reason, bg: Colors.white, fg: C.ink2, size: 11, border: C.line)
                else if (qty > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 26),
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: C.sky, borderRadius: BorderRadius.circular(999)),
                    child: Text('$qty', style: ts(13, w: w6, c: Colors.white)),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(15, w: w5, h: 1.25)),
              const SizedBox(height: 4),
              Row(children: [
                Dot(color: m.veg ? C.green : C.red, square: true),
                const SizedBox(width: 6),
                Flexible(child: Text(m.cat, overflow: TextOverflow.ellipsis, style: ts(12, c: C.muted))),
                if (m.customizable) ...[
                  const SizedBox(width: 6),
                  Pill(m.variants.isNotEmpty ? '${m.variants.length} sizes' : 'Add-ons',
                      bg: C.skyTint, fg: C.blueDeep, size: 11, pad: const EdgeInsets.symmetric(horizontal: 7, vertical: 2)),
                ],
              ]),
              const Spacer(),
              Row(children: [
                Text('${m.variants.isNotEmpty ? 'from ' : ''}${inr(m.fromPrice)}', style: ts(15, w: w6)),
                const Spacer(),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.line)),
                  child: const Icon(Icons.add, size: 18),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------- cart ----------------
  Widget _cartBar() {
    final n = cart.fold<int>(0, (a, l) => a + l.qty);
    final sub = cart.fold<double>(0, (a, l) => a + l.total);
    return Material(
      color: C.ink,
      elevation: 6,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _openCartSheet,
        child: Container(
          height: 64,
          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          child: Row(children: [
            CircleAvatar(radius: 16, backgroundColor: C.blue, child: Text('$n', style: ts(13, w: w6, c: Colors.white))),
            const SizedBox(width: 12),
            Expanded(child: Text('Current order · ${inr(sub)}', style: ts(15, w: w5, c: Colors.white))),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(16)),
              child: Text('Review', style: ts(15, w: w5, c: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openCartSheet() async {
    _sheetOpen = true;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * .88,
          child: ValueListenableBuilder<int>(valueListenable: _tick, builder: (c, _, __) => _cartPanel(StoreScope.of(c))),
        ),
      ),
    );
    _sheetOpen = false;
  }

  Widget _cartPanel(Store s) {
    final sub = cart.fold<double>(0, (a, l) => a + l.total);
    final fee = type == OrderType.delivery ? 40.0 : 0.0;
    final tax = sub * .05;
    final total = (sub + tax + fee).roundToDouble();
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Current order', style: ts(20, w: w5)),
              const Spacer(),
              Pill('KOT #${s.nextKotNo}', bg: Colors.white, border: C.line),
            ]),
            const SizedBox(height: 14),
            Seg<OrderType>(
              expand: true,
              items: const [(OrderType.dineIn, 'Dine in'), (OrderType.takeaway, 'Takeaway'), (OrderType.delivery, 'Delivery')],
              value: type,
              onChanged: (v) => setState(() {
                type = v;
                existing = null;
              }),
            ),
            const SizedBox(height: 14),
            _typeFields(s),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.receipt_long_outlined, color: C.faint, size: 36),
                  const SizedBox(height: 8),
                  Text('No items yet', style: ts(15, w: w5)),
                  const SizedBox(height: 4),
                  Text('Tap an item to add it to the order', style: ts(13, c: C.muted)),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  itemCount: cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) => _lineRow(cart[i]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                SumRow('Subtotal', inr(sub, decimals: true)),
                SumRow('Tax (5%)', inr(tax, decimals: true)),
                if (fee > 0) SumRow('Delivery fee', inr(fee, decimals: true)),
                const SizedBox(height: 4),
                SumRow('Total', inr(total), big: true),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Btn.outline('Clear', onTap: cart.isEmpty ? null : () => setState(cart.clear)),
              const SizedBox(width: 10),
              Expanded(
                  child: Btn('Confirm & Print KOT', icon: Icons.print_outlined, expand: true, onTap: cart.isEmpty ? null : confirm)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _typeFields(Store s) {
    if (type == OrderType.dineIn) {
      String label = 'Select table', sub = '';
      if (tableId != null && partyKey != null) {
        final t = s.table(tableId!);
        final p = s.party(tableId!, partyKey!);
        if (p != null) {
          final running = s.orderOfParty(t, p)?.lines.isNotEmpty == true;
          label = 'Table ${s.partyLabel(t, p.key)}';
          sub = '${p.pax} pax · ${t.floor}${running ? ' · adding to running order' : ''}';
        }
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: pickTable,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tableError ? C.red : C.line)),
            child: Row(children: [
              const Icon(Icons.table_restaurant_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: ts(15, w: w5, c: sub.isEmpty ? C.muted : C.ink)),
                if (sub.isNotEmpty) Text(sub, overflow: TextOverflow.ellipsis, style: ts(12, c: C.muted)),
              ])),
              Text(sub.isEmpty ? 'Choose' : 'Change', style: ts(13, w: w5, c: C.blueDeep)),
            ]),
          ),
        ),
        if (tableError)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Select a table before sending the KOT', style: ts(12, c: C.red))),
      ]);
    }
    return Column(children: [
      Row(children: [
        Expanded(child: TextField(controller: nameC, decoration: const InputDecoration(hintText: 'Customer name'))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: phoneC, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Phone'))),
      ]),
      if (type == OrderType.delivery) ...[
        const SizedBox(height: 8),
        TextField(controller: addrC, decoration: const InputDecoration(hintText: 'Delivery address')),
      ],
    ]);
  }

  Widget _lineRow(OrderLine l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(l.item.name, style: ts(15, w: w5))),
            Text(inr(l.total), style: ts(15, w: w5)),
          ]),
          if (l.optText.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 3), child: Text(l.optText, style: ts(13, c: C.skyInk))),
          if (l.note.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 3), child: Text('Note: ${l.note}', style: ts(13, c: C.amberInk))),
          const SizedBox(height: 8),
          Row(children: [
            QtyStepper(
              value: l.qty,
              size: 32,
              onDec: () => setState(() {
                l.qty--;
                if (l.qty <= 0) cart.remove(l);
              }),
              onInc: () => setState(() => l.qty++),
            ),
            const Spacer(),
            Text('${inr(l.unit)} ea', style: ts(12, c: C.muted)),
            const SizedBox(width: 8),
            RoundIcon(Icons.edit_outlined, size: 36, onTap: () => editLine(l), tooltip: 'Edit'),
            const SizedBox(width: 6),
            RoundIcon(Icons.delete_outline, size: 36, fg: C.red, onTap: () => setState(() => cart.remove(l)), tooltip: 'Delete'),
          ]),
        ]),
      );
}
