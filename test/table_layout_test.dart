import 'dart:io';

import 'package:BPOS/models.dart';
import 'package:BPOS/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Store s;

  setUp(() async {
    final docs = Directory.systemTemp.createTempSync('bpos_layout');
    final b = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    b.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => docs.path);
    b.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    b.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, __) {}));
    s = Store();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    s.tables
      ..clear()
      ..addAll([TableModel('T1', 'Tables', 4), TableModel('T2', 'Tables', 4), TableModel('T3', 'Tables', 8, w: 2), TableModel('T4', 'Tables', 4)]);
  });

  (int?, int?) at(String id) => (s.table(id).gx, s.table(id).gy);

  test('unplaced tables flow into rows without overlapping', () {
    s.placeUnplaced('Tables', 3);
    expect([at('T1'), at('T2'), at('T3'), at('T4')], [(0, 0), (1, 0), (0, 1), (2, 0)]);
  });

  test('moving onto another table lands on the nearest free cell, and positions persist', () {
    s.placeUnplaced('Tables', 3);
    s.moveTable(s.table('T4'), 5, 5);
    expect(at('T4'), (5, 5));
    s.moveTable(s.table('T4'), 1, 0); // T2 sits there
    final (x, y) = at('T4');
    expect((x, y), isNot((1, 0)));
    expect((x! - 1).abs() + y!.abs(), 1, reason: 'one cell away from the wanted spot');
    s.moveTable(s.table('T1'), -3, -3);
    expect(at('T1'), (0, 0), reason: 'clamped to the plan');

    final back = TableModel.fromJson(s.table('T4').toJson());
    expect(at('T4'), (back.gx, back.gy));

    s.resetLayout('Tables');
    expect(at('T4'), (null, null));
  });

  test('a move stays inside the visible plan', () {
    s.placeUnplaced('Tables', 3);
    s.moveTable(s.table('T4'), 9, 9, cols: 3, rows: 2);
    expect(at('T4'), (2, 1));
    s.moveTable(s.table('T3'), 2, 0, cols: 3, rows: 2); // 2 wide: clamps to x 1, taken -> nearest free
    final (x, y) = at('T3');
    expect(x! + 2 <= 3 && y! + 1 <= 2, isTrue);
    s.moveTable(s.table('T1'), 1, 0, cols: 3, rows: 2);
    for (final id in ['T1', 'T2', 'T3', 'T4']) {
      final t = s.table(id);
      expect(t.gx! + t.w <= 3 && t.gy! + t.h <= 2, isTrue, reason: id);
    }
  });
}
