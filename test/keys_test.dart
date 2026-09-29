import 'package:bistro_pos/widgets/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final log = <String>[];
  final field = TextEditingController();

  Widget app() => MaterialApp(
        home: Scaffold(
          body: KeyScope(
            keys: [
              Hotkey(const SingleActivator(LogicalKeyboardKey.f2), () => log.add('outer F2')),
              Hotkey(const SingleActivator(LogicalKeyboardKey.f3), () => log.add('outer F3')),
            ],
            child: KeyScope(
              autofocus: true,
              keys: [
                Hotkey(const SingleActivator(LogicalKeyboardKey.f3), () => log.add('inner F3')),
                Hotkey(const CharacterActivator('+'), () => log.add('plus')),
                Hotkey(const SingleActivator(LogicalKeyboardKey.enter, control: true), () => log.add('ctrl enter')),
                Hotkey(const SingleActivator(LogicalKeyboardKey.enter), () => log.add('never'), when: () => false),
              ],
              child: TextField(controller: field),
            ),
          ),
        ),
      );

  setUp(() {
    log.clear();
    field.clear();
  });

  testWidgets('screen keys work once the screen opens; inner screen overrides the app bar', (t) async {
    await t.pumpWidget(app());
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.f2);
    await t.sendKeyEvent(LogicalKeyboardKey.f3);
    expect(log, ['outer F2', 'inner F3']);
  });

  testWidgets('plain keys are left alone while typing; modifier keys still work', (t) async {
    await t.pumpWidget(app());
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.equal, character: '+');
    expect(log, ['plus']); // not typing yet: shortcut

    await t.tap(find.byType(TextField));
    await t.pump();
    expect(isTyping(), isTrue);
    log.clear();
    await t.sendKeyEvent(LogicalKeyboardKey.equal, character: '+');
    expect(log, isEmpty); // typing: left to the text field
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(log, ['ctrl enter']);
  });

  testWidgets('Esc leaves the text field; a switched-off key falls through', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(isTyping(), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(isTyping(), isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(log, isEmpty);
  });
}
