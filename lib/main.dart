import 'package:flutter/material.dart';
import 'captain/captain.dart';
import 'pos/pos_shell.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/common.dart';

void main() => runApp(const BistroApp());

class BistroApp extends StatefulWidget {
  const BistroApp({super.key});
  @override
  State<BistroApp> createState() => _BistroAppState();
}

class _BistroAppState extends State<BistroApp> {
  final store = Store();
  @override
  Widget build(BuildContext context) => StoreScope(
        store: store,
        child: MaterialApp(
          title: 'POS',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const Launcher(),
        ),
      );
}

class Launcher extends StatelessWidget {
  const Launcher({super.key});

  Widget _card(BuildContext context, IconData icon, String title, String sub, Color color, Widget Function() page) => SizedBox(
        width: 320,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page())),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: C.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 18),
                Text(title, style: ts(20, w: w5)),
                const SizedBox(height: 4),
                Text(sub, style: ts(14, c: C.muted, h: 1.4)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: C.blueDeep, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4))),
              ),
              const SizedBox(height: 14),
              Text(s.outletName.isEmpty ? 'Loading…' : s.outletName, style: ts(24, w: w5)),
              const SizedBox(height: 4),
              Text('Choose a workspace', style: ts(15, c: C.muted)),
              const SizedBox(height: 28),
              Wrap(spacing: 16, runSpacing: 16, alignment: WrapAlignment.center, children: [
                _card(context, Icons.point_of_sale, 'Main POS', 'Counter & tablet · order taking, tables, payments, orders, kitchen',
                    C.blue, () => const PosShell()),
                _card(context, Icons.phone_iphone, 'Captain app', 'Mobile · seat guests, share tables, type to add items, send KOT',
                    C.purple, () => const CaptainFrame()),
              ]),
            ]),
          ),
        ),
      );
  }
}
