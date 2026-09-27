import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/receipt.dart';

const _captain = 'Arjun P.';

/// Hosts the captain app in its own navigator. On wide screens it is shown in a phone-sized frame.
class CaptainFrame extends StatelessWidget {
  const CaptainFrame({super.key});
  @override
  Widget build(BuildContext context) {
    final nav = Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const CaptainHome()));
    return Scaffold(
      backgroundColor: const Color(0xFFDADADA),
      body: LayoutBuilder(builder: (c, cons) {
        if (cons.maxWidth < 600) return nav;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: SizedBox(width: 420, height: math.min(cons.maxHeight - 48, 900), child: nav),
            ),
          ),
        );
      }),
    );
  }
}

// =====================================================================
// Home
// =====================================================================
class CaptainHome extends StatefulWidget {
  const CaptainHome({super.key});
  @override
  State<CaptainHome> createState() => _CaptainHomeState();
}

class _CaptainHomeState extends State<CaptainHome> {
  bool takeaway = false;
  String floor = 'Main hall';

  void _push(Order o) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaptainOrderScreen(order: o)));

  void openParty(TableModel t, Party p) {
    final s = StoreScope.read(context);
    final o = s.ensurePartyOrder(t, p, server: _captain);
    if (o.billed) {
      billingSheet(o);
      return;
    }
    _push(o);
  }

  void tapTable(Store s, TableModel t) {
    if (t.parties.length == 1 && t.free == 0) {
      openParty(t, t.parties.first);
      return;
    }
    seatSheet(t);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final runningDine = s.tables.where((t) => t.parties.isNotEmpty).length;
    final ta = s.activeOrders.where((o) => o.type == OrderType.takeaway).toList();
    final active = s.tables.fold<int>(0, (a, t) => a + t.parties.length) + ta.length;
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0xFFFFD9A8),
                    child: Text('AP', style: TextStyle(color: Color(0xFF7A4A0C), fontWeight: w5))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Captain · Bistro 21', style: ts(13, c: C.muted)),
                  Text(_captain, style: ts(20, w: w5)),
                ])),
                Pill('$active active',
                    bg: Colors.white, border: C.line, size: 13, leading: const Dot(color: C.sky, size: 7),
                    pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                const SizedBox(width: 6),
                RoundIcon(Icons.logout, size: 40, onTap: () => Navigator.of(context, rootNavigator: true).maybePop()),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _homeTab('Dine in', '$runningDine running', !takeaway, C.ink, () => setState(() => takeaway = false))),
                const SizedBox(width: 8),
                Expanded(child: _homeTab('Takeaway', '${ta.length} running', takeaway, C.purple, () => setState(() => takeaway = true))),
              ]),
              if (!takeaway) ...[
                const SizedBox(height: 12),
                Seg<String>(
                    expand: true,
                    items: [for (final f in Store.floors) (f, f)],
                    value: floor,
                    onChanged: (v) => setState(() => floor = v)),
              ],
            ]),
          ),
          Expanded(child: takeaway ? _takeawayList(s, ta) : _grid(s)),
        ]),
      ),
    );
  }

  Widget _homeTab(String name, String sub, bool on, Color color, VoidCallback onTap) => Material(
        color: on ? color : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: on ? color : C.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(name, style: ts(16, w: w5, c: on ? Colors.white : C.ink)),
              const SizedBox(width: 8),
              Text(sub, style: ts(13, c: on ? const Color(0xB3FFFFFF) : C.muted)),
            ]),
          ),
        ),
      );

  Widget _grid(Store s) => ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 40), children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisExtent: 112, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: s.tablesOn(floor).length,
          itemBuilder: (c, i) => _tableTile(s, s.tablesOn(floor)[i]),
        ),
        const SizedBox(height: 18),
        Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 6, children: [
          for (final (l, bg, border) in const [
            ('Free', Colors.white, Color(0xFFCFCFCF)),
            ('Running', C.sky, C.sky),
            ('Shared', C.skyTint, C.sky),
            ('Reserved', C.green, C.green),
            ('Billing', C.amber, C.amber),
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: border))),
              const SizedBox(width: 5),
              Text(l, style: ts(12, c: const Color(0xFF6B6B6B))),
            ]),
        ]),
      ]);

  Widget _tableTile(Store s, TableModel t) {
    final ps = t.parties;
    final allBilled = ps.isNotEmpty && ps.every((p) => s.orderOfParty(t, p)?.billed == true);
    final status = ps.isEmpty
        ? (t.reservedFor != null ? 'Reserved' : 'Free')
        : allBilled
            ? 'Billing'
            : (ps.length > 1 || t.free > 0 ? 'Shared' : 'Running');
    final (bg, fg, border) = switch (status) {
      'Running' => (C.sky, Colors.white, C.sky),
      'Shared' => (C.skyTint, C.skyInk, C.sky),
      'Reserved' => (C.green, Colors.white, C.green),
      'Billing' => (C.amber, Colors.white, C.amber),
      _ => (Colors.white, C.ink, C.line),
    };
    final total = ps.fold<double>(0, (a, p) => a + (s.orderOfParty(t, p)?.total ?? 0));
    final dots = <Color>[];
    for (var i = 0; i < ps.length; i++) {
      for (var j = 0; j < ps[i].pax; j++) {
        dots.add(status == 'Running' ? const Color(0xD9FFFFFF) : partyColors[i % partyColors.length]);
      }
    }
    for (var j = 0; j < t.free; j++) {
      dots.add(status == 'Running' ? const Color(0x59FFFFFF) : const Color(0xFFD6D6D6));
    }
    final line1 = switch (status) {
      'Free' => 'Free',
      'Reserved' => t.reservedFor!,
      _ => total > 0 ? inr(total) : 'Seated',
    };
    final line2 = switch (status) {
      'Shared' => '${ps.length} ${ps.length == 1 ? 'party' : 'parties'} · ${t.free} free',
      'Running' => elapsed(ps.first.seatedAt),
      'Billing' => 'Bill printed',
      'Free' => 'Tap to seat',
      _ => 'Reserved',
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => tapTable(s, t),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(t.id, style: ts(20, w: w6, c: fg)),
              const Spacer(),
              Text('${t.seats}p', style: ts(12, c: fg.withOpacity(.8))),
            ]),
            const Spacer(),
            if (t.seats <= 8 && status != 'Reserved' && status != 'Billing')
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(spacing: 3, runSpacing: 3, children: [for (final d in dots) Dot(color: d)]),
              ),
            Text(line1, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, w: w5, c: fg)),
            Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, c: fg.withOpacity(.8))),
          ]),
        ),
      ),
    );
  }

  Widget _takeawayList(Store s, List<Order> ta) => ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 40), children: [
        Material(
          color: C.purple,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _push(s.draft(OrderType.takeaway, server: _captain)),
            child: Container(
              height: 88,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const CircleAvatar(radius: 24, backgroundColor: Color(0x38FFFFFF), child: Icon(Icons.add, color: Colors.white)),
                const SizedBox(width: 14),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('New takeaway order', style: ts(18, w: w5, c: Colors.white)),
                  Text('Next token ${s.nextTaToken}', style: ts(13, c: const Color(0xD9FFFFFF))),
                ]),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Label('Running takeaways')),
        if (ta.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('No running takeaways', textAlign: TextAlign.center, style: ts(14, c: C.muted))),
        for (final o in ta) _taRow(s, o),
      ]);

  Widget _taRow(Store s, Order o) {
    final st = s.stageOf(o);
    final ready = st == OrderStage.ready;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _push(o),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
            child: Row(children: [
              Container(
                width: 56,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: C.purpleTint, borderRadius: BorderRadius.circular(14)),
                child: Text(o.token, style: ts(13, w: w6, c: C.purpleInk)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.customer.isEmpty ? 'Walk-in' : o.customer, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w: w5)),
                Text('${o.phone.isNotEmpty ? '${o.phone} · ' : ''}${elapsed(o.at)} · ${o.itemCount} items',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: C.muted)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(inr(o.total), style: ts(15, w: w5)),
                const SizedBox(height: 4),
                Pill(ready ? 'Ready' : st.label,
                    bg: ready ? C.greenTint : C.amberTint, fg: ready ? C.greenInk : C.amberInk,
                    pad: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------- seat / share sheet ----------------
  void seatSheet(TableModel t) {
    int pax = math.min(2, math.max(1, t.free));
    showSheet(
        context,
        (ctx) => StatefulBuilder(builder: (ctx, set) {
              final s = StoreScope.of(ctx);
              pax = math.max(1, math.min(pax, math.max(1, t.free)));
              final left = t.free - pax;
              final seats = <Widget>[];
              for (var i = 0; i < t.parties.length; i++) {
                final p = t.parties[i];
                final c = s.orderOfParty(t, p)?.billed == true ? C.amber : partyColors[i % partyColors.length];
                for (var j = 0; j < p.pax; j++) {
                  seats.add(_seat(c, p.key, Colors.white, null));
                }
              }
              for (var j = 0; j < t.free; j++) {
                seats.add(j < pax
                    ? _seat(partyColors[t.parties.length % partyColors.length], 'new', Colors.white, null)
                    : _seat(Colors.white, '', C.muted, C.faint));
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(t.parties.isEmpty ? 'Seat guests · ${t.id}' : 'Table ${t.id} · shared', style: ts(20, w: w5)),
                  const SizedBox(height: 2),
                  Text(
                      t.parties.isEmpty
                          ? '${t.seats} seats${t.reservedFor != null ? ' · reserved ${t.reservedFor}' : ''}'
                          : '${t.used} of ${t.seats} seats taken · ${t.free} free',
                      style: ts(14, c: C.muted)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFF6F6F6), borderRadius: BorderRadius.circular(20), border: Border.all(color: C.faint)),
                    child: GridView.count(
                      crossAxisCount: math.min(t.seats, 6),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 1.3,
                      children: seats,
                    ),
                  ),
                  if (t.parties.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Label('Seated'),
                    const SizedBox(height: 8),
                    for (var i = 0; i < t.parties.length; i++) _partyRow(ctx, s, t, t.parties[i], i),
                  ],
                  if (t.free > 0) ...[
                    const SizedBox(height: 16),
                    Label(t.parties.isEmpty ? 'How many people?' : 'Seat another party'),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.5,
                      children: [for (var n = 1; n <= t.free; n++) Choice('$n', on: n == pax, fontSize: 20, onTap: () => set(() => pax = n))],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: C.skyTint, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                          left == 0
                              ? (t.parties.isEmpty ? 'Whole table for this party' : 'Table will be full')
                              : '$left seat${left == 1 ? '' : 's'} stay open to share · up to ${t.parties.length + 1 + left} parties',
                          style: ts(13, c: C.skyInk)),
                    ),
                    const SizedBox(height: 14),
                    Btn('Start order · $pax pax', expand: true, height: 56, fontSize: 16, onTap: () {
                      Navigator.pop(ctx);
                      final np = s.seatParty(t, pax);
                      openParty(t, np);
                    }),
                  ] else ...[
                    const SizedBox(height: 14),
                    Text('All seats taken · free a party to seat new guests', textAlign: TextAlign.center, style: ts(14, c: C.muted)),
                  ],
                ]),
              );
            }));
  }

  Widget _seat(Color c, String t, Color fg, Color? border) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: c, borderRadius: BorderRadius.circular(12), border: border == null ? null : Border.all(color: border, width: 1.5)),
        child: Text(t, style: ts(13, w: w6, c: fg)),
      );

  Widget _partyRow(BuildContext ctx, Store s, TableModel t, Party p, int i) {
    final o = s.orderOfParty(t, p);
    final billed = o?.billed == true;
    final hasItems = o != null && o.lines.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.pop(ctx);
            openParty(t, p);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
            child: Row(children: [
              Dot(color: billed ? C.amber : partyColors[i % partyColors.length], size: 10),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.partyLabel(t, p.key), style: ts(16, w: w5)),
                Text('${p.pax} pax · ${billed ? 'Bill printed' : elapsed(p.seatedAt)}${hasItems ? ' · ${inr(o.total)}' : ''}',
                    style: ts(13, c: C.muted)),
              ])),
              if (!hasItems)
                TextButton(onPressed: () => s.freeParty(t, p), child: const Text('Free')),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: billed ? C.amber : C.ink, borderRadius: BorderRadius.circular(12)),
                child: Text(billed ? 'Billing' : 'Open', style: ts(14, w: w5, c: Colors.white)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------- billing (locked) sheet ----------------
  void billingSheet(Order o) {
    showSheet(context, (ctx) {
      final s = StoreScope.of(ctx);
      final lbl = s.labelOf(o);
      Widget action(IconData i, String t, VoidCallback f) => Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: f,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
                child: Row(children: [
                  Icon(i, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t, style: ts(16, w: w5))),
                  const Icon(Icons.chevron_right, color: C.faint),
                ]),
              ),
            ),
          );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(16)),
              child: Text(lbl, style: ts(14, w: w6, c: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Table $lbl · Billing', style: ts(20, w: w5)),
              Text('${o.itemCount} items · ${o.pax} pax · seated ${elapsed(o.at)}', style: ts(13, c: C.muted)),
            ])),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: const Color(0xFFFCF3E2), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bill ${o.billNo} printed', style: ts(14, w: w5, c: const Color(0xFF8A5A08))),
                Text('Awaiting payment at the main POS', style: ts(13, c: const Color(0xFFA8700F))),
              ])),
              Text(inr(o.total), style: ts(22, w: w6)),
            ]),
          ),
          const SizedBox(height: 16),
          action(Icons.receipt_long_outlined, 'View bill',
              () => showPrintPreview(ctx, bill: ReceiptData.bill(s, o), printLabel: 'Reprint bill')),
          const SizedBox(height: 10),
          action(Icons.add, 'Reopen to add items', () async {
            final ok = await confirmDialog(ctx,
                title: 'Reopen $lbl?',
                body: 'Bill ${o.billNo} (${inr(o.total)}) will be voided. Print a new bill after adding items.',
                ok: 'Reopen & add');
            if (!ok) return;
            final v = s.reopen(o);
            if (ctx.mounted) Navigator.pop(ctx);
            if (!mounted) return;
            toast(context, '$lbl reopened · bill $v voided');
            _push(o);
          }),
          const SizedBox(height: 14),
          Text('Mark as paid from the main POS', textAlign: TextAlign.center, style: ts(13, c: C.muted)),
        ]),
      );
    });
  }
}

// =====================================================================
// Order screen (typing-first)
// =====================================================================
class CaptainOrderScreen extends StatefulWidget {
  final Order order;
  const CaptainOrderScreen({super.key, required this.order});
  @override
  State<CaptainOrderScreen> createState() => _CaptainOrderScreenState();
}

class _CaptainOrderScreenState extends State<CaptainOrderScreen> {
  static const popular = ['g1', 'm1', 'p1', 'v2', 'b1', 's2', 'v1', 'd1'];
  String cat = 'Popular';
  final cart = <OrderLine>[];
  bool sentOpen = false;
  final focus = FocusNode();
  final qC = TextEditingController();
  late final nameC = TextEditingController(text: widget.order.customer);
  late final phoneC = TextEditingController(text: widget.order.phone);
  final _tick = ValueNotifier(0);

  Order get o => widget.order;
  bool get isTA => o.type != OrderType.dineIn;
  String get q => qC.text.trim().toLowerCase();
  int get cartCount => cart.fold<int>(0, (a, l) => a + l.qty);
  double get cartTotal => cart.fold<double>(0, (a, l) => a + l.total);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _tick.value++;
  }

  @override
  void initState() {
    super.initState();
    focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    focus.dispose();
    qC.dispose();
    nameC.dispose();
    phoneC.dispose();
    _tick.dispose();
    super.dispose();
  }

  List<MenuItem> search(Store s) {
    final x = q;
    if (x.isEmpty) {
      return cat == 'Popular' ? popular.map(s.item).toList() : s.itemsIn(cat);
    }
    int score(MenuItem m) {
      final n = m.name.toLowerCase();
      if (m.code.startsWith(x)) return 0;
      if (m.searchInitials.startsWith(x)) return 1;
      if (n.startsWith(x)) return 2;
      if (n.split(RegExp(r'\s+')).any((w) => w.startsWith(x))) return 3;
      if (n.contains(x)) return 4;
      var i = 0;
      for (final ch in n.split('')) {
        if (i < x.length && ch == x[i]) i++;
      }
      return i == x.length ? 5 : 9;
    }

    final scored = s.menu.map((m) => (m, score(m))).where((e) => e.$2 < 9).toList()
      ..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1.code.compareTo(b.$1.code));
    return scored.map((e) => e.$1).toList();
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

  Future<void> tap(MenuItem m) async {
    final s = StoreScope.read(context);
    if (s.offReason(m) != null) return;
    if (m.customizable) {
      final l = await _optionSheet(m);
      if (l != null) {
        setState(() {
          _merge(l);
          qC.clear();
        });
      }
    } else {
      setState(() => _merge(OrderLine(item: m)));
    }
  }

  void dec(MenuItem m) => setState(() {
        final i = cart.lastIndexWhere((l) => l.item.id == m.id);
        if (i < 0) return;
        cart[i].qty--;
        if (cart[i].qty <= 0) cart.removeAt(i);
      });

  void sendKot() {
    final s = StoreScope.read(context);
    if (cart.isEmpty) return;
    if (o.billed) {
      toast(context, 'Bill printed · reopen the table first');
      return;
    }
    if (isTA) {
      o.customer = nameC.text.trim();
      o.phone = phoneC.text.trim();
    }
    final n = cartCount;
    final k = s.sendKot(o, cart);
    setState(() {
      cart.clear();
      qC.clear();
      sentOpen = true;
    });
    toast(context, 'KOT #${k.no} sent · ${s.labelOf(o)} · $n items');
  }

  Future<void> printBill() async {
    final s = StoreScope.read(context);
    if (o.lines.isEmpty) {
      toast(context, 'Nothing to bill yet');
      return;
    }
    final ok = await showPrintPreview(context,
        bill: ReceiptData.bill(s, o, no: s.previewBillNo(o)),
        subtitle: cart.isNotEmpty
            ? '$cartCount unsent items are not on this bill'
            : (isTA ? 'Payment at the main POS' : 'Printing locks ${s.labelOf(o)} until paid at the main POS'),
        printLabel: o.billed ? 'Reprint bill' : 'Print bill');
    if (!ok || !mounted) return;
    if (!isTA && !o.billed) {
      final no = s.printBill(o);
      toast(context, 'Bill $no printed · ${s.labelOf(o)} locked');
      Navigator.of(context).pop();
    }
  }

  Future<void> back() async {
    if (cart.isNotEmpty) {
      final ok = await confirmDialog(context,
          title: 'Discard new items?', body: '$cartCount unsent items will be removed.', ok: 'Discard', okColor: C.red, cancel: 'Keep');
      if (!ok) return;
    }
    if (isTA && StoreScope.read(context).orders.contains(o)) {
      o.customer = nameC.text.trim();
      o.phone = phoneC.text.trim();
      StoreScope.read(context).touch();
    }
    if (mounted) {
      cart.clear();
      Navigator.of(context).pop();
    }
  }

  Future<void> askClear() async {
    final ok = await confirmDialog(context,
        title: 'Clear new items?',
        body: '$cartCount unsent items (${inr(cartTotal)}) will be removed. Items already sent to the kitchen stay on the order.',
        ok: 'Clear items',
        okColor: C.red,
        cancel: 'Keep');
    if (ok) {
      setState(cart.clear);
      if (mounted) toast(context, 'New items cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final res = search(s);
    final qtyBy = <String, int>{};
    for (final l in cart) {
      qtyBy[l.item.id] = (qtyBy[l.item.id] ?? 0) + l.qty;
    }
    final t = isTA ? null : s.table(o.tableId!);
    final p = isTA ? null : s.party(o.tableId!, o.partyKey!);
    final title = isTA ? (o.token.isEmpty ? 'New takeaway · ${s.nextTaToken}' : 'Takeaway ${o.token}') : 'Table ${s.labelOf(o)}';
    final sub = isTA
        ? (o.lines.isEmpty ? 'New order' : '${elapsed(o.at)} · Running · ${inr(o.total)}')
        : '${t!.parties.length > 1 || t.free > 0 ? 'Shared · ${t.free} free' : '${t.seats} seats'} · ${o.lines.isEmpty ? 'New order' : 'Running · ${inr(o.total)}'}';
    final hasQ = q.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) back();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    RoundIcon(Icons.arrow_back_ios_new, size: 44, onTap: back),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(20, w: w6, h: 1.15)),
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: C.muted)),
                    ])),
                    if (!isTA && p != null)
                      QtyStepper(
                        value: p.pax,
                        size: 34,
                        suffix: ' pax',
                        onDec: p.pax > 1 ? () => s.setPax(t!, p, p.pax - 1) : null,
                        onInc: () {
                          if (!s.setPax(t!, p, p.pax + 1)) toast(context, 'No free seats on ${t.id}');
                        },
                      ),
                    if (isTA) const Pill('TAKEAWAY', bg: C.purpleTint, fg: C.purpleInk, weight: w6, pad: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  ]),
                  if (isTA) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextField(controller: nameC, decoration: const InputDecoration(hintText: 'Customer name'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: phoneC, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Phone'))),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: qC,
                    focusNode: focus,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (res.isNotEmpty) {
                        final m = res.first;
                        tap(m);
                        if (!m.customizable && s.offReason(m) == null) {
                          qC.clear();
                          toast(context, 'Added ${m.name}');
                        }
                        focus.requestFocus();
                      }
                    },
                    style: ts(17),
                    decoration: InputDecoration(
                      hintText: 'Type item name or code',
                      prefixIcon: const Icon(Icons.search),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.line)),
                      focusedBorder:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.blue, width: 2)),
                      suffixIcon: hasQ ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(qC.clear)) : null,
                    ),
                  ),
                  if (!hasQ) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final c in ['Popular', ...s.categories])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Material(
                              color: cat == c ? C.ink : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => setState(() => cat = c),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999), border: Border.all(color: cat == c ? C.ink : C.line)),
                                  child: Row(children: [
                                    Dot(color: c == 'Popular' ? C.amber : colorForCategory(c).$1, size: 7),
                                    const SizedBox(width: 6),
                                    Text(c, style: ts(14, w: w5, c: cat == c ? Colors.white : C.ink)),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ],
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 120), children: [
                  if (!hasQ && o.lines.isNotEmpty) _sentCard(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Label(hasQ ? '${res.length} match${res.length == 1 ? '' : 'es'} · enter adds top result' : cat),
                  ),
                  for (var i = 0; i < res.length; i++) _resultRow(s, res[i], qtyBy[res[i].id] ?? 0, hasQ && i == 0),
                  if (hasQ && res.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(children: [
                        Text('No match for “${qC.text}”', style: ts(16, w: w5)),
                        const SizedBox(height: 6),
                        Text('Try a code like 101, or initials like “cap”', style: ts(14, c: C.muted)),
                      ]),
                    ),
                ]),
              ),
            ]),
            Positioned(left: 12, right: 12, bottom: 16, child: _bottomBar()),
          ]),
        ),
      ),
    );
  }

  Widget _sentCard() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => sentOpen = !sentOpen),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Already ordered · ${o.itemCount} items', style: ts(14, w: w5))),
                  Text(inr(o.subtotal), style: ts(14, c: C.ink2)),
                  Icon(sentOpen ? Icons.expand_less : Icons.expand_more, size: 20, color: C.muted),
                ]),
                if (sentOpen)
                  for (final l in o.lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                            child: Text('${l.qty}× ${l.item.name}${l.optText.isNotEmpty ? '  ${l.optText}' : ''}',
                                style: ts(14, c: C.ink2))),
                        const SizedBox(width: 8),
                        Text(l.state.label, style: ts(12, c: lineStateColors(l.state).$2)),
                      ]),
                    ),
              ]),
            ),
          ),
        ),
      );

  Widget _resultRow(Store s, MenuItem m, int n, bool top) {
    final reason = s.offReason(m);
    final c = colorForCategory(m.cat);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: reason != null ? .5 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: top ? C.blue : C.line, width: top ? 2 : 1)),
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => tap(m),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.$2, borderRadius: BorderRadius.circular(14)),
                    child: Text(m.code, style: ts(13, w: w6, c: c.$1)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Dot(color: m.veg ? C.green : C.red, square: true),
                      const SizedBox(width: 6),
                      Flexible(child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w: w5))),
                    ]),
                    Text(
                        '${m.variants.isNotEmpty ? 'from ' : ''}${inr(m.fromPrice)}${m.customizable ? ' · ${m.variants.isNotEmpty ? '${m.variants.length} sizes' : 'add-ons'}' : ''}${q.isNotEmpty ? ' · ${m.cat}' : ''}',
                        style: ts(13, c: C.muted)),
                  ])),
                ]),
              ),
            ),
            if (reason != null)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(reason, style: ts(12, w: w5, c: C.muted)))
            else if (n > 0 && !m.customizable)
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: () => dec(m), icon: const Icon(Icons.remove, color: Colors.white)),
                  Text('$n', style: ts(16, w: w6, c: Colors.white)),
                  IconButton(onPressed: () => tap(m), icon: const Icon(Icons.add, color: Colors.white)),
                ]),
              )
            else
              Material(
                color: C.blue,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => tap(m),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: n > 0
                        ? Center(child: Text('+$n', style: ts(14, w: w6, c: Colors.white)))
                        : const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    if (cart.isNotEmpty) {
      return Row(children: [
        Material(
          color: Colors.white,
          elevation: 6,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: askClear,
            child: const SizedBox(width: 64, height: 64, child: Icon(Icons.delete_outline, color: C.redInk)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Material(
            color: C.ink,
            elevation: 6,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _cartSheet,
              child: Container(
                height: 64,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(children: [
                  CircleAvatar(radius: 16, backgroundColor: C.blue, child: Text('$cartCount', style: ts(13, w: w6, c: Colors.white))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('New items', style: ts(15, w: w5, c: Colors.white)),
                    Text(inr(cartTotal), style: ts(13, c: const Color(0xFFBDBDBD))),
                  ])),
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(16)),
                    child: Text('Review · KOT', style: ts(15, w: w5, c: Colors.white)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]);
    }
    if (o.lines.isEmpty || (focus.hasFocus && q.isNotEmpty)) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: C.line),
          boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 30, offset: Offset(0, 10))]),
      child: Row(children: [
        Expanded(child: Btn.outline(o.billed ? 'Reprint bill' : 'Print bill', icon: Icons.print_outlined, expand: true, onTap: printBill)),
        const SizedBox(width: 8),
        Expanded(
            child: Btn('+ Add new items', expand: true, onTap: () {
          setState(() {
            qC.clear();
            sentOpen = false;
          });
          focus.requestFocus();
        })),
      ]),
    );
  }

  Future<OrderLine?> _optionSheet(MenuItem m) {
    String? variant = m.variants.isNotEmpty ? m.variants.first.name : null;
    final addons = <String>{};
    int qty = 1;
    return showSheet<OrderLine>(
        context,
        (ctx) => StatefulBuilder(builder: (ctx, set) {
              final line = OrderLine(item: m, variant: variant, addons: addons.toList(), qty: qty);
              final c = colorForCategory(m.cat);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.$2, borderRadius: BorderRadius.circular(14)),
                      child: Text(m.code, style: ts(13, w: w6, c: c.$1)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(m.name, style: ts(19, w: w5, h: 1.25))),
                  ]),
                  if (m.variants.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Label('Size'),
                    const SizedBox(height: 8),
                    Row(children: [
                      for (var i = 0; i < m.variants.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: Material(
                            color: variant == m.variants[i].name ? Colors.white : C.soft2,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => set(() => variant = m.variants[i].name),
                              child: Container(
                                height: 64,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: variant == m.variants[i].name ? C.ink : C.line,
                                        width: variant == m.variants[i].name ? 2 : 1)),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text(m.variants[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w: w5)),
                                  Text(inr(m.variants[i].price), style: ts(13, c: const Color(0xFF6B6B6B))),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ],
                  if (m.addons.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Label('Add-ons'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final a in m.addons)
                        Builder(builder: (_) {
                          final on = addons.contains(a.name);
                          return Material(
                            color: on ? const Color(0xFFEEF6FE) : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => set(() => on ? addons.remove(a.name) : addons.add(a.name)),
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999), border: Border.all(color: on ? C.blue : C.line)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text('${on ? '✓' : '+'} ${a.name} ${inr(a.price)}', style: ts(14, w: w5, c: on ? C.skyInk : C.ink)),
                                ]),
                              ),
                            ),
                          );
                        }),
                    ]),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    QtyStepper(value: qty, size: 44, onDec: qty > 1 ? () => set(() => qty--) : null, onInc: () => set(() => qty++)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Btn('Add · ${inr(line.total)}', expand: true, height: 54, fontSize: 16, onTap: () => Navigator.pop(ctx, line))),
                  ]),
                ]),
              );
            }));
  }

  void _cartSheet() {
    showSheet(
        context,
        (ctx) => ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (c, _, __) {
              final s = StoreScope.of(c);
              if (cart.isEmpty) {
                return Padding(
                    padding: const EdgeInsets.all(32), child: Text('No new items', textAlign: TextAlign.center, style: ts(15, c: C.muted)));
              }
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Row(children: [
                    Expanded(child: Text('New KOT · ${s.labelOf(o)}', style: ts(20, w: w5))),
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await askClear();
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: C.redInk, side: const BorderSide(color: Color(0xFFF0D0D2))),
                      child: const Text('Clear all'),
                    ),
                  ]),
                ),
                Flexible(
                  child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 18), children: [
                    for (final l in cart)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.soft))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.item.name, style: ts(16, w: w5)),
                              if (l.optText.isNotEmpty) Text(l.optText, style: ts(13, c: C.skyInk)),
                              Text(inr(l.total), style: ts(13, c: C.muted)),
                            ])),
                            QtyStepper(
                              value: l.qty,
                              size: 38,
                              onDec: () => setState(() {
                                l.qty--;
                                if (l.qty <= 0) cart.remove(l);
                              }),
                              onInc: () => setState(() => l.qty++),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: l.note,
                            onChanged: (v) => l.note = v,
                            decoration: const InputDecoration(hintText: 'Add kitchen note', fillColor: C.soft2),
                          ),
                        ]),
                      ),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text('$cartCount items', style: ts(15, c: const Color(0xFF6B6B6B)))),
                      Text(inr(cartTotal), style: ts(15, w: w6)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Btn.outline('Add more', height: 56, onTap: () => Navigator.pop(ctx)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Btn('Send KOT to kitchen', expand: true, height: 56, fontSize: 16, onTap: () {
                        Navigator.pop(ctx);
                        sendKot();
                      })),
                    ]),
                  ]),
                ),
              ]);
            }));
  }
}
