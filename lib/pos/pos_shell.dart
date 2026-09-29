import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../link/link_models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/printer_status.dart';
import '../widgets/keys.dart';
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
  int _gen = 0;
  StreamSubscription<(String, bool)>? _notices;
  int _requestsSeen = 0;
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
    _lastServed = s.servedNotices.isEmpty ? null : s.servedNotices.last.id;
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
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

  /// "Grill marked served · Table 12 · 1× Alfaham" from a kitchen display.
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
                TextSpan(text: '${n.station} ${n.handedOver ? 'handed over' : 'served'} · ', style: ts(16, w: w5, c: Colors.white)),
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
        tab = 0;
        _gen++;
      });

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    // A new bill request: an audible nudge for the cashier.
    if (s.billRequests.length > _requestsSeen) SystemSound.play(SystemSoundType.alert);
    _requestsSeen = s.billRequests.length;
    final served = s.servedNotices.where((n) => s.orderById(n.orderId) != null).toList();
    if (served.isNotEmpty && served.last.id != _lastServed) SystemSound.play(SystemSoundType.alert);
    _lastServed = served.isEmpty ? null : served.last.id;
    final body = switch (tab) {
      0 => OrderTakingScreen(key: ValueKey('ot$_gen'), target: target, onDone: () => target = null),
      1 => TablesScreen(onAddItems: openOrderTaking),
      2 => OrdersScreen(onAddItems: openOrderTaking),
      3 => const PaymentsScreen(),
      _ => const KitchenScreen(),
    };
    void go(int v) => setState(() {
          tab = v;
          if (v != 0) target = null;
        });
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
        Hotkey(const SingleActivator(LogicalKeyboardKey.comma, control: true), settings),
        Hotkey(const SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true), () => showPrinterStatus(context)),
        Hotkey(const SingleActivator(LogicalKeyboardKey.f12), () => showShortcutHelp(context)),
        Hotkey(const CharacterActivator('?'), () => showShortcutHelp(context)),
      ],
      child: Scaffold(
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
                  ]),
                ),
              ),
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
