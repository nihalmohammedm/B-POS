import 'dart:io';

import 'package:BPOS/models.dart';
import 'package:BPOS/pos/tables_screen.dart';
import 'package:BPOS/store.dart';
import 'package:BPOS/theme.dart';
import 'package:BPOS/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real Floor screen: the table that is dragged is the table that moves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dragging a table in edit mode moves that table only', (t) async {
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) onError?.call(d);
    };
    final docs = Directory.systemTemp.createTempSync('bpos_drag');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => docs.path);
    m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    m.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, __) {}));
    await t.binding.setSurfaceSize(const Size(1600, 1000));

    late Store s;
    await t.runAsync(() async {
      s = Store();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    s.permissions = {'settings.manage'};
    s.tables
      ..clear()
      ..addAll([for (final id in ['T1', 'T2', 'T3']) TableModel(id, 'Tables', 4)]);

    await t.pumpWidget(StoreScope(store: s, child: MaterialApp(theme: buildTheme(), home: Scaffold(body: TablesScreen(onAddItems: (_) {})))));
    await t.pump();
    expect([for (final x in s.tables) (x.gx, x.gy)], [(0, 0), (1, 0), (2, 0)]);

    expect(find.text('Edit layout'), findsNothing, reason: 'no edit button any more');
    const grey = Offset(600, 800); // empty space inside the grey floor area

    // A short hold does nothing...
    var hold = await t.startGesture(grey);
    await t.pump(const Duration(seconds: 1));
    await hold.up();
    await t.pump();
    expect(find.text('Done'), findsNothing);

    // ...a managers-only gesture: without the permission 3 seconds still does nothing...
    s.permissions = {};
    s.setAutoSync(true); // any change notifies: the screen rebuilds like it does after a login
    await t.pump();
    hold = await t.startGesture(grey);
    await t.pump(const Duration(milliseconds: 3200));
    await hold.up();
    await t.pump();
    expect(find.text('Done'), findsNothing);

    // ...and with it, holding for 3 seconds turns editing on.
    s.permissions = {'settings.manage'};
    s.setAutoSync(true);
    await t.pump();
    hold = await t.startGesture(grey);
    await t.pump(const Duration(milliseconds: 2500));
    expect(find.text('Done'), findsNothing, reason: 'not yet at 2.5s');
    await t.pump(const Duration(milliseconds: 700));
    await hold.up();
    await t.pump();
    expect(find.text('Done'), findsOneWidget);

    // Drag T2 two cells down and one to the right (cell pitch is 174 x 152 on an unscaled plan).
    // Like a finger: the screen rebuilds between every event (this is what exposed the wrong table moving).
    final g = await t.startGesture(t.getCenter(find.text('T2')));
    await t.pump();
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(174 / 8, 304 / 8));
      await t.pump();
    }
    await g.up();
    await t.pump();

    expect((s.table('T1').gx, s.table('T1').gy), (0, 0));
    expect((s.table('T3').gx, s.table('T3').gy), (2, 0));
    expect((s.table('T2').gx, s.table('T2').gy), (2, 2));
    await t.pumpWidget(const SizedBox());
    s.dispose();
    FlutterError.onError = onError;
    await t.binding.setSurfaceSize(null);
  });
}
