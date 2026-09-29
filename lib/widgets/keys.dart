import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// One keyboard shortcut. Keys with Ctrl/Alt/Meta, function keys and Escape
/// work even while typing in a field; plain keys (Enter, arrows, digits, + / -)
/// are skipped while a text field has focus so they never eat typed text,
/// unless [whileTyping] says otherwise. [when] can switch a key off for the
/// moment (e.g. nothing selected) so it falls through to an outer scope.
class Hotkey {
  final ShortcutActivator key;
  final VoidCallback? action;
  final bool? whileTyping;
  final bool Function()? when;
  const Hotkey(this.key, this.action, {this.whileTyping, this.when});

  bool get _worksWhileTyping {
    if (whileTyping != null) return whileTyping!;
    final k = key;
    if (k is! SingleActivator) return false;
    if (k.control || k.alt || k.meta) return true;
    return k.trigger == LogicalKeyboardKey.escape || _fKeys.contains(k.trigger);
  }
}

final _fKeys = {
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
};

/// True while the keyboard focus is in a text field.
bool isTyping() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText || ctx.findAncestorStateOfType<EditableTextState>() != null;
}

/// Runs [keys] for key presses anywhere inside [child]. Key presses travel up
/// from the focused widget, so an inner scope (a screen) sees a key before an
/// outer one (the app bar) and can override it. Dialogs sit outside the
/// screen's tree, so screen shortcuts pause while a dialog is open.
///
/// With [autofocus] the scope takes the keyboard when it appears, so its keys
/// work straight away. Esc inside a text field hands the keyboard back to the
/// scope (leaving the search box without clicking).
class KeyScope extends StatefulWidget {
  final List<Hotkey> keys;
  final Widget child;
  final bool autofocus;
  const KeyScope({super.key, required this.keys, required this.child, this.autofocus = false});
  @override
  State<KeyScope> createState() => _KeyScopeState();
}

class _KeyScopeState extends State<KeyScope> {
  final _node = FocusNode(debugLabel: 'KeyScope');

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !isTyping()) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _node,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          final typing = isTyping();
          for (final h in widget.keys) {
            if (h.action == null || !h.key.accepts(e, HardwareKeyboard.instance)) continue;
            if (typing && !h._worksWhileTyping) continue;
            if (h.when != null && !h.when!()) continue;
            h.action!();
            return KeyEventResult.handled;
          }
          if (typing && e.logicalKey == LogicalKeyboardKey.escape && widget.autofocus) {
            _node.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: widget.child,
      );
}

/// Physical keyboards are the norm on desktop/web tills; on phones and tablets
/// the hints would just be noise.
bool get hasKeyboard =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

// ---------------------------------------------------------------------------
// Help sheet: the single list of every shortcut, grouped by where it works.

const shortcutHelp = <(String, List<(String, String)>)>[
  (
    'Anywhere on the POS',
    [
      ('F1 – F5', 'New order · Tables · Orders · Payments · Kitchen'),
      ('Ctrl + 1 – 5', 'Same as F1 – F5'),
      ('Ctrl + ,', 'Settings'),
      ('Ctrl + Shift + P', 'Printer status'),
      ('F12  or  ?', 'This list of shortcuts'),
      ('Esc', 'Leave the search box / close a dialog'),
    ]
  ),
  (
    'New order',
    [
      ('/  or  Ctrl + F', 'Search items (name or code)'),
      ('Enter (in search)', 'Add the first match, clear the search for the next code'),
      ('Alt + 1 / 2 / 3', 'Dine in · Takeaway · Delivery'),
      ('Ctrl + T', 'Pick table'),
      ('Page Up / Page Down', 'Previous / next category'),
      ('Alt + V', 'Veg only on/off'),
      ('+  /  -', 'More / fewer of the last item in the cart'),
      ('Delete', 'Remove the last item in the cart'),
      ('Ctrl + Delete', 'Clear the cart'),
      ('Ctrl + Enter', 'Send: print KOT (and bill for takeaway)'),
      ('Ctrl + Shift + Enter', 'Takeaway: take payment now, then print'),
    ]
  ),
  (
    'Orders & Payments',
    [
      ('↑ / ↓', 'Select previous / next'),
      ('/  or  Ctrl + F', 'Search'),
      ('Alt + 0 / 1 / 2 / 3', 'All · Dine in · Takeaway · Delivery'),
      ('Enter', 'Orders: main action (Mark ready, Settle…) · Payments: Collect'),
      ('Ctrl + P', 'Print / reprint the bill'),
      ('Ctrl + K', 'Orders: reprint the last KOT'),
      ('Insert', 'Orders: add items'),
      ('Ctrl + R', 'Reopen the bill'),
      ('Ctrl + Delete', 'Orders: cancel the order'),
    ]
  ),
  (
    'Tables',
    [
      ('← → ↑ ↓', 'Select a table'),
      ('Page Up / Page Down', 'Previous / next floor'),
      ('Enter', 'Open the table (add items to its running order)'),
    ]
  ),
  (
    'Kitchen',
    [
      ('← → ↑ ↓', 'Select a ticket'),
      ('Enter  or  Space', 'Ticket action (Start · Mark ready · Served)'),
      ('Backspace', 'Recall a ready ticket'),
      ('Alt + R', 'Active / Ready tickets'),
      ('Alt + 0 / 1 / 2 / 3', 'All · Dine in · Takeaway · Delivery'),
    ]
  ),
  (
    'Dialogs',
    [
      ('Enter  or  Ctrl + Enter', 'Confirm (Complete payment, Print, Add, Save…)'),
      ('Ctrl + S', 'Payment: split into another method'),
      ('1 – 9', 'Pick a size / cancellation reason by position'),
      ('+  /  -', 'Quantity up / down'),
      ('Alt + K / Alt + B', 'Print preview: show KOT / Bill'),
      ('Esc', 'Close without doing anything'),
    ]
  ),
];

Future<void> showShortcutHelp(BuildContext context) => showPanelDialog(context,
    maxWidth: 820,
    builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 14, 12),
            child: Row(children: [
              const Icon(Icons.keyboard_outlined, color: C.ink2),
              const SizedBox(width: 10),
              Expanded(child: Text('Keyboard shortcuts', style: ts(20, w: w5))),
              RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(ctx)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: LayoutBuilder(builder: (c, cons) {
                final w = cons.maxWidth >= 700 ? (cons.maxWidth - 24) / 2 : cons.maxWidth;
                return Wrap(spacing: 24, runSpacing: 20, children: [
                  for (final (title, rows) in shortcutHelp)
                    SizedBox(
                      width: w,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Label(title),
                        const SizedBox(height: 8),
                        for (final (k, what) in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              SizedBox(width: 170, child: KeyCap(k)),
                              Expanded(child: Text(what, style: ts(13, c: C.ink2, h: 1.35))),
                            ]),
                          ),
                      ]),
                    ),
                ]);
              }),
            ),
          ),
        ]));

/// A key label drawn like a key cap.
class KeyCap extends StatelessWidget {
  final String text;
  const KeyCap(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: C.soft,
            borderRadius: BorderRadius.circular(6),
            border: const Border(
              top: BorderSide(color: C.line),
              left: BorderSide(color: C.line),
              right: BorderSide(color: C.line),
              bottom: BorderSide(color: C.faint, width: 2),
            ),
          ),
          child: Text(text, style: ts(12, w: w6, c: C.ink).copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Consolas', 'Menlo'])),
        ),
      );
}

/// ↑/↓ selection, `/` or Ctrl+F for search and Alt+0–3 type filters, shared by
/// the list screens (Orders, Payments).
List<Hotkey> listKeys<T>({
  required List<T> items,
  required T? selected,
  required ValueChanged<T> select,
  FocusNode? search,
  ValueChanged<OrderType?>? filter,
}) {
  void step(int d) {
    if (items.isEmpty) return;
    final i = selected == null ? -1 : items.indexOf(selected);
    select(items[(i + d).clamp(0, items.length - 1)]);
  }

  return [
    Hotkey(const SingleActivator(LogicalKeyboardKey.arrowDown), () => step(1)),
    Hotkey(const SingleActivator(LogicalKeyboardKey.arrowUp), () => step(-1)),
    if (search != null) ...[
      Hotkey(const CharacterActivator('/'), search.requestFocus),
      Hotkey(const SingleActivator(LogicalKeyboardKey.keyF, control: true), search.requestFocus),
    ],
    if (filter != null)
      for (final (k, t) in [
        (LogicalKeyboardKey.digit0, null),
        (LogicalKeyboardKey.digit1, OrderType.dineIn),
        (LogicalKeyboardKey.digit2, OrderType.takeaway),
        (LogicalKeyboardKey.digit3, OrderType.delivery),
      ])
        Hotkey(SingleActivator(k, alt: true), () => filter(t)),
  ];
}
