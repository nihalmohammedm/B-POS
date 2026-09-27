import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'kitchen_screen.dart';
import 'order_taking.dart';
import 'orders_screen.dart';
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

  void openOrderTaking(Order o) => setState(() {
        target = o;
        tab = 0;
        _gen++;
      });

  @override
  Widget build(BuildContext context) {
    final body = switch (tab) {
      0 => OrderTakingScreen(key: ValueKey('ot$_gen'), target: target, onDone: () => target = null),
      1 => TablesScreen(onAddItems: openOrderTaking),
      2 => OrdersScreen(onAddItems: openOrderTaking),
      _ => const KitchenScreen(),
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(color: C.blueDeep, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.line)),
                      child: Row(children: [
                        const CircleAvatar(
                            radius: 19,
                            backgroundColor: C.sky,
                            child: Text('B', style: TextStyle(color: Colors.white, fontWeight: w5))),
                        const SizedBox(width: 10),
                        Text('Bistro 21 · Downtown', style: ts(16, w: w5)),
                        const SizedBox(width: 10),
                        const Pill('OPEN', fg: C.greenInk, leading: Dot(color: Color(0xFF34A853), size: 6)),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Seg<int>(
                      height: 40,
                      fontSize: 15,
                      items: const [(0, 'New order'), (1, 'Tables'), (2, 'Orders'), (3, 'Kitchen')],
                      value: tab,
                      onChanged: (v) => setState(() {
                        tab = v;
                        if (v != 0) target = null;
                      }),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              RoundIcon(Icons.settings_outlined,
                  size: 44,
                  tooltip: 'Settings',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              const SizedBox(width: 12),
              const CircleAvatar(
                  radius: 25,
                  backgroundColor: Color(0xFFFFD9A8),
                  child: Text('SK', style: TextStyle(color: Color(0xFF7A4A0C), fontWeight: w5))),
            ]),
            const SizedBox(height: 18),
            Expanded(child: body),
          ]),
        ),
      ),
    );
  }
}
