import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../link/link_models.dart';
import '../store.dart';
import '../sync/web_order_api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/printer_status.dart';
import '../widgets/keys.dart';
import '../widgets/receipt.dart';
import 'kitchen_screen.dart';
import 'order_taking.dart';
import 'orders_screen.dart';
import 'payments_screen.dart';
import 'payment.dart';
import 'settings_screen.dart';
import 'tables_screen.dart';

class PosShell extends StatefulWidget {
  const PosShell({super.key});
  @override
  State<PosShell> createState() => _PosShellState();
}

class _PosShellState extends State<PosShell> {
  int tab = 0;
  Order? target;
  OrderType _startType = OrderType.dineIn;
  int _gen = 0;
  StreamSubscription<(String, bool)>? _notices;
  int _requestsSeen = 0;
  int _webSeen = 0;
  final _webBusy = <String>{};
  String? _lastServed;

  @override
  void initState() {
    super.initState();
    final s = StoreScope.read(context);
    // Work done for captains in the background (their KOT printing, bill
    // requests) reports here.
    _notices = s.notices.listen((n) {
      if (mounted) toast(context, n.$1, error: n.$2);
    });
    _requestsSeen = s.billRequests.length;
    _webSeen = s.webOrders.length;
    s.pollWebOrders();
    _lastServed = s.servedNotices.isEmpty ? null : s.servedNotices.last.id;
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
  }

  /// "Web order #4 · Arun · Takeaway · 3 items · ₹450" with Accept / Reject. Accepting makes it a
  /// real takeaway order and prints its KOTs; nothing reaches the kitchen before that.
  Widget _webOrder(Store s, WebOrder w) {
    final busy = _webBusy.contains(w.id);
    final items = w.lines.map((l) => '${l.qty}× ${l.name}${l.variant == null ? '' : ' (${l.variant})'}').join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(color: C.blueDeep, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.language, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: 'Web order #${w.number} · ', style: ts(16, w: w5, c: Colors.white)),
              TextSpan(text: '${w.customer} · ${w.phone}', style: ts(16, w: w7, c: Colors.white)),
              TextSpan(
                  text: ' · ${w.dineIn ? 'Dine in${w.table.isEmpty ? '' : ' · Table ${w.table}'}' : 'Takeaway'} · ${inr(w.total)}',
                  style: ts(15, c: Colors.white)),
              TextSpan(text: '  ${elapsed(w.at)} ago', style: ts(13, c: const Color(0xDDFFFFFF))),
            ])),
            Text(w.notes.isEmpty ? items : '$items · Note: ${w.notes}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(14, c: const Color(0xDDFFFFFF))),
          ]),
        ),
        const SizedBox(width: 8),
        Btn('Accept & print KOT', icon: Icons.check, height: 44, bg: Colors.white, fg: C.ink, onTap: busy ? null : () => _acceptWeb(s, w)),
        const SizedBox(width: 8),
        RoundIcon(Icons.close, size: 40, bg: const Color(0x33FFFFFF), fg: Colors.white, border: null, tooltip: 'Reject',
            onTap: busy ? null : () => _rejectWeb(s, w)),
      ]),
    );
  }

  Future<void> _acceptWeb(Store s, WebOrder w) async {
    setState(() => _webBusy.add(w.id));
    try {
      final r = await s.acceptWebOrder(w);
      if (!mounted) return;
      if (r == null) {
        toast(context, 'Web order #${w.number} was already handled on another device');
        return;
      }
      await printKotsWithToast(context, s, [for (final k in r.$2) ReceiptData.kot(s, r.$1, k)]);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _webBusy.remove(w.id));
    }
  }

  Future<void> _rejectWeb(Store s, WebOrder w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject web order #${w.number}?'),
        content: Text('${w.customer} will see that the restaurant could not take this order.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _webBusy.add(w.id));
    try {
      await s.rejectWebOrder(w);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _webBusy.remove(w.id));
    }
  }

  /// "Arun is asking for the bill · Table 12" with Print bill / Dismiss.
  Widget _billRequest(Store s, BillRequest r) {
    final o = s.orderById(r.orderId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.notifications_active, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${r.captain} is asking for the bill · ', style: ts(16, w: w5, c: Colors.white)),
              TextSpan(text: r.label, style: ts(16, w: w7, c: Colors.white)),
              TextSpan(text: '  ${elapsed(r.at)} ago', style: ts(13, c: const Color(0xDDFFFFFF))),
            ]),
          ),
        ),
        if (o != null && !o.billed)
          Btn('Print bill', icon: Icons.print_outlined, height: 44, bg: Colors.white, fg: C.ink, onTap: () => printBillFlow(context, o)),
        const SizedBox(width: 8),
        RoundIcon(Icons.close, size: 40, bg: const Color(0x33FFFFFF), fg: Colors.white, border: null, tooltip: 'Dismiss',
            onTap: () => s.dismissBillRequest(r.id)),
      ]),
    );
  }

  /// "Grill ready · Table 12 · 1× Alfaham" from a kitchen display.
  Widget _served(Store s, ServedNotice n, {int clearAll = 0}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.room_service, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${n.station} ready · ', style: ts(16, w: w5, c: Colors.white)),
                TextSpan(text: n.label, style: ts(16, w: w7, c: Colors.white)),
                if (n.items.isNotEmpty) TextSpan(text: ' · ${n.items}', style: ts(15, c: Colors.white)),
                TextSpan(text: '  ${elapsed(n.at)} ago', style: ts(13, c: const Color(0xDDFFFFFF))),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (clearAll > 0) ...[
            const SizedBox(width: 8),
            Btn('Clear all $clearAll', height: 40, fontSize: 13, bg: const Color(0x33FFFFFF), onTap: s.dismissAllServed),
          ],
          const SizedBox(width: 8),
          RoundIcon(Icons.close, size: 40, bg: const Color(0x33FFFFFF), fg: Colors.white, border: null, tooltip: 'Dismiss',
              onTap: () => s.dismissServed(n.id)),
        ]),
      );

  void openOrderTaking(Order o) => setState(() {
        target = o;
        _startType = o.type;
        tab = 0;
        _gen++;
      });

  /// Counter sale, no table: lands directly on Takeaway with a fresh cart,
  /// skipping the "New order opens on Dine-in, then switch type" detour.
  void fastBilling() => setState(() {
        target = null;
        _startType = OrderType.takeaway;
        tab = 0;
        _gen++;
      });

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    // A new bill request: an audible nudge for the cashier.
    if (s.billRequests.length > _requestsSeen) SystemSound.play(SystemSoundType.alert);
    _requestsSeen = s.billRequests.length;
    if (s.webOrders.length > _webSeen) SystemSound.play(SystemSoundType.alert);
    _webSeen = s.webOrders.length;
    final served = s.servedNotices.where((n) => s.orderById(n.orderId) != null).toList();
    if (served.isNotEmpty && served.last.id != _lastServed) SystemSound.play(SystemSoundType.alert);
    _lastServed = served.isEmpty ? null : served.last.id;
    final body = switch (tab) {
      0 => OrderTakingScreen(key: ValueKey('ot$_gen'), target: target, startType: _startType, onDone: () => target = null),
      1 => TablesScreen(onAddItems: openOrderTaking),
      2 => OrdersScreen(onAddItems: openOrderTaking),
      3 => const PaymentsScreen(),
      _ => const KitchenScreen(),
    };
    void go(int v) => setState(() {
          tab = v;
          if (v != 0) {
            target = null;
          } else {
            _startType = OrderType.dineIn;
          }
        });
    // Desktop/tablet-landscape keeps the top tab strip; narrow screens get the bottom bar.
    final wide = MediaQuery.of(context).size.width >= 900;
    void settings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    final tabKeys = [LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3, LogicalKeyboardKey.f4, LogicalKeyboardKey.f5];
    final digitKeys = [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5];
    return KeyScope(
      autofocus: true,
      keys: [
        for (var i = 0; i < 5; i++) ...[
          Hotkey(SingleActivator(tabKeys[i]), () => go(i)),
          Hotkey(SingleActivator(digitKeys[i], control: true), () => go(i)),
        ],
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyB, alt: true), fastBilling),
        Hotkey(const SingleActivator(LogicalKeyboardKey.comma, control: true), settings),
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true), () => showPrinterStatus(context)),
        Hotkey(const SingleActivator(LogicalKeyboardKey.f12), () => showShortcutHelp(context)),
        Hotkey(const CharacterActivator('?'), () => showShortcutHelp(context)),
      ],
      child: Scaffold(
      bottomNavigationBar: wide ? null : _NavBar(
        value: tab,
        onChanged: go,
        items: [
          (Icons.add_circle_outline, Icons.add_circle, 'New order', 0),
          (Icons.table_restaurant_outlined, Icons.table_restaurant, 'Tables', 0),
          (Icons.receipt_long_outlined, Icons.receipt_long, 'Orders', 0),
          (Icons.payments_outlined, Icons.payments, 'Payments', s.awaitingPayment.length),
          (Icons.soup_kitchen_outlined, Icons.soup_kitchen, 'Kitchen', 0),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.line)),
                      child: Row(children: [
                        CircleAvatar(
                            radius: 19,
                            backgroundColor: C.sky,
                            child: Text(s.outletName.isEmpty ? '·' : s.outletName[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: w5))),
                        const SizedBox(width: 10),
                        Text(s.outletName.isEmpty ? 'Loading…' : s.outletName, style: ts(16, w: w5)),
                        const SizedBox(width: 10),
                        const Pill('OPEN', fg: C.greenInk, leading: Dot(color: Color(0xFF34A853), size: 6)),
                      ]),
                    ),
                    if (wide) ...[
                      const SizedBox(width: 14),
                      Seg<int>(
                        height: 40,
                        fontSize: 15,
                        items: [
                          (0, 'New order'),
                          (1, 'Tables'),
                          (2, 'Orders'),
                          (3, s.awaitingPayment.isEmpty ? 'Payments' : 'Payments · ${s.awaitingPayment.length}'),
                          (4, 'Kitchen'),
                        ],
                        value: tab,
                        onChanged: go,
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Btn('Fast billing', icon: Icons.bolt, height: 40, bg: C.amber, fg: C.amberInk, onTap: fastBilling),
              const SizedBox(width: 12),
              const PrinterStatusChip(),
              const SizedBox(width: 12),
              RoundIcon(Icons.settings_outlined,
                  size: 44,
                  tooltip: 'Settings',
                  onTap: settings),
              if (hasKeyboard) ...[
                const SizedBox(width: 12),
                RoundIcon(Icons.keyboard_outlined, size: 44, tooltip: 'Keyboard shortcuts (F12)', onTap: () => showShortcutHelp(context)),
              ],
              const SizedBox(width: 12),
              const CircleAvatar(
                  radius: 25,
                  backgroundColor: Color(0xFFFFD9A8),
                  child: Icon(Icons.person_outline, color: Color(0xFF7A4A0C))),
            ]),
            const SizedBox(height: 18),
            for (final w in s.webOrders) _webOrder(s, w),
            for (final r in s.billRequests) _billRequest(s, r),
            // Newest two in full; the rest fold into "Clear all" so the screen stays usable.
            for (final (i, n) in served.reversed.take(2).indexed) _served(s, n, clearAll: i == 1 && served.length > 2 ? served.length : 0),
            Expanded(child: body),
          ]),
        ),
      ),
    ),
    );
  }
}

/// Mobile-style bottom navigation: icon over label, filled icon + tinted pill on the
/// active tab, optional count badge.
class _NavBar extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final List<(IconData, IconData, String, int)> items;
  const _NavBar({required this.value, required this.onChanged, required this.items});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Stack(clipBehavior: Clip.none, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 3),
                        decoration: BoxDecoration(
                            color: i == value ? C.sky.withValues(alpha: .18) : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                        child: Icon(i == value ? items[i].$2 : items[i].$1, size: 24, color: i == value ? C.blueDeep : C.ink2),
                      ),
                      if (items[i].$4 > 0)
                        Positioned(
                            right: 6,
                            top: -3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(999)),
                              child: Text('${items[i].$4}', style: ts(11, w: w5, c: Colors.white)),
                            )),
                    ]),
                    const SizedBox(height: 2),
                    Text(items[i].$3, style: ts(12, w: i == value ? w6 : w5, c: i == value ? C.blueDeep : C.ink2)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
