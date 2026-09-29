import 'package:bistro_pos/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toast sits bottom centre, hugs its text, then goes away', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 800));
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));

    toast(ctx, 'KOT #12 printed');
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final box = t.getRect(find.ancestor(of: find.text('KOT #12 printed'), matching: find.byType(Material)).first);
    expect(box.width, lessThan(300)); // hugs the text, not full width
    expect(box.center.dx, closeTo(600, 1)); // centred
    expect(box.bottom, closeTo(800 - 24, 1)); // bottom

    toast(ctx, 'Second'); // replaces the first
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('KOT #12 printed'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });
}
