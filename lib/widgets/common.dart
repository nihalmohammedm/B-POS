import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'keys.dart';

class StoreScope extends InheritedNotifier<Store> {
  const StoreScope({super.key, required Store store, required super.child}) : super(notifier: store);
  static Store of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
  static Store read(BuildContext context) => context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

/// Indian-grouped rupees: 1,23,456 / 1,23,456.50
String inr(num v, {bool decimals = false}) {
  final neg = v < 0;
  final cents = (v.abs() * 100).round();
  final whole = decimals ? cents ~/ 100 : v.abs().round();
  var s = whole.toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last3';
  }
  if (decimals) s += '.${(cents % 100).toString().padLeft(2, '0')}';
  return '${neg ? '-' : ''}₹$s';
}

int minsSince(DateTime at) => DateTime.now().difference(at).inMinutes;
String elapsed(DateTime at) {
  final m = minsSince(at);
  return m < 60 ? '$m min' : '${m ~/ 60}h ${m % 60}m';
}

TextStyle ts(double size, {FontWeight w = FontWeight.w400, Color c = C.ink, double? h, double? ls, TextDecoration? deco}) =>
    TextStyle(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls, decoration: deco);

const w5 = FontWeight.w500;
const w6 = FontWeight.w600;
const w7 = FontWeight.w700;

Color typeColor(OrderType t) => switch (t) { OrderType.dineIn => C.sky, OrderType.takeaway => C.purple, OrderType.delivery => C.amber };
(Color, Color) typeTint(OrderType t) => switch (t) {
      OrderType.dineIn => (C.skyTint, C.skyInk),
      OrderType.takeaway => (C.purpleTint, C.purpleInk),
      OrderType.delivery => (const Color(0xFFFCF3E2), const Color(0xFFA8700F)),
    };
Color stageColor(OrderStage s) => switch (s) {
      OrderStage.placed => const Color(0xFFB8B8B8),
      OrderStage.preparing => C.amber,
      OrderStage.ready => C.green,
      OrderStage.served => C.sky,
      OrderStage.outForDelivery => C.sky,
      OrderStage.billing => C.purple,
    };
(Color, Color) lineStateColors(LineState s) => switch (s) {
      LineState.queued => (C.soft, const Color(0xFF6B6B6B)),
      LineState.preparing => (C.amberTint, C.amberInk),
      LineState.ready => (C.greenTint, C.greenInk),
      LineState.served => (Colors.white, C.ink2),
    };

class Dot extends StatelessWidget {
  final Color color;
  final double size;
  final bool square;
  const Dot({super.key, required this.color, this.size = 8, this.square = false});
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: color,
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square ? BorderRadius.circular(2) : null));
}

class Pill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  final Color? border;
  final double size;
  final EdgeInsets pad;
  final Widget? leading;
  final FontWeight weight;
  const Pill(this.text,
      {super.key,
      this.bg = C.soft,
      this.fg = C.ink,
      this.border,
      this.size = 12,
      this.pad = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      this.leading,
      this.weight = w5});
  @override
  Widget build(BuildContext context) => Container(
        padding: pad,
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(999), border: border == null ? null : Border.all(color: border!)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(size, w: weight, c: fg))),
        ]),
      );
}

class Seg<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final double height, fontSize;
  final bool expand;
  const Seg(
      {super.key, required this.items, required this.value, required this.onChanged, this.height = 40, this.expand = false, this.fontSize = 14});
  @override
  Widget build(BuildContext context) {
    final kids = items.map((it) {
      final on = it.$1 == value;
      final btn = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(it.$1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null),
          child: Text(it.$2,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(fontSize, w: w5, c: on ? C.ink : const Color(0xFF7A7A7A))),
        ),
      );
      return expand ? Expanded(child: btn) : btn;
    }).toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.track, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: kids),
    );
  }
}

class Toggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double scale;
  const Toggle({super.key, required this.value, this.onChanged, this.scale = 1});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Opacity(
          opacity: onChanged == null ? .45 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 58 * scale,
            height: 34 * scale,
            padding: EdgeInsets.all(2 * scale),
            decoration: BoxDecoration(color: value ? C.sky : const Color(0xFFD6D6D6), borderRadius: BorderRadius.circular(999)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                  width: 30 * scale,
                  height: 30 * scale,
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))])),
            ),
          ),
        ),
      );
}

class QtyStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onDec, onInc;
  final double size;
  final String suffix;
  const QtyStepper({super.key, required this.value, this.onDec, this.onInc, this.size = 40, this.suffix = ''});
  Widget _b(IconData i, VoidCallback? f) => Material(
      color: C.soft,
      shape: const CircleBorder(),
      child: InkWell(
          customBorder: const CircleBorder(),
          onTap: f,
          child: SizedBox(width: size, height: size, child: Icon(i, size: 18, color: f == null ? C.faint : C.ink))));
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _b(Icons.remove, onDec),
          SizedBox(
              width: suffix.isEmpty ? size * .9 : size * 1.6,
              child: Text('$value$suffix', textAlign: TextAlign.center, style: ts(15, w: w5))),
          _b(Icons.add, onInc),
        ]),
      );
}

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color bg, fg;
  final Color? border;
  final double height, fontSize;
  final IconData? icon;
  final bool expand;
  const Btn(this.label,
      {super.key,
      this.onTap,
      this.bg = C.blue,
      this.fg = Colors.white,
      this.border,
      this.height = 52,
      this.fontSize = 15,
      this.icon,
      this.expand = false});
  const Btn.outline(this.label,
      {super.key, this.onTap, this.fg = C.ink, this.height = 52, this.fontSize = 15, this.icon, this.expand = false})
      : bg = Colors.white,
        border = C.line;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Material(
          color: bg,
          shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border!)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
                    Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(fontSize, w: w5, c: fg))),
                  ]),
            ),
          ),
        ),
      );
}

class RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color bg, fg;
  final Color? border;
  final String? tooltip;
  const RoundIcon(this.icon,
      {super.key, this.onTap, this.size = 44, this.bg = Colors.white, this.fg = C.ink, this.border = C.line, this.tooltip});
  @override
  Widget build(BuildContext context) {
    final w = Material(
      color: bg,
      shape: CircleBorder(side: border == null ? BorderSide.none : BorderSide(color: border!)),
      child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: size * .42, color: fg))),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.radius = 20, this.color = Colors.white});
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), border: Border.all(color: C.line)),
      child: child);
}

class Thumb extends StatelessWidget {
  final MenuItem item;
  final double size;
  final double? radius;
  const Thumb(this.item, {super.key, this.size = 48, this.radius});
  @override
  Widget build(BuildContext context) {
    final c = colorForCategory(item.cat);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.$2, borderRadius: BorderRadius.circular(radius ?? size * .29)),
      child: Text(item.initials, style: ts(size * .3, w: w6, c: c.$1)),
    );
  }
}

class Label extends StatelessWidget {
  final String text;
  const Label(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: ts(12, c: C.muted, ls: .4));
}

class Choice extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  final double height, width;
  final double fontSize;
  const Choice(this.label, {super.key, required this.on, required this.onTap, this.height = 52, this.width = 56, this.fontSize = 18});
  @override
  Widget build(BuildContext context) => Material(
        color: on ? C.ink : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: height,
            constraints: BoxConstraints(minWidth: width),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? C.ink : C.line)),
            child: Text(label, style: ts(fontSize, w: w5, c: on ? Colors.white : C.ink)),
          ),
        ),
      );
}

OverlayEntry? _toastEntry;

/// Short status message, bottom centre, as wide as its text. Drawn on the root
/// overlay and ignoring touches, so it never blocks the buttons underneath and
/// stays put across dialogs and page changes. A new toast replaces the old one.
void toast(BuildContext context, String msg, {bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastEntry?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      msg: msg,
      error: error,
      onDone: () {
        if (_toastEntry == entry) _toastEntry = null;
        entry.remove();
      },
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String msg;
  final bool error;
  final VoidCallback onDone;
  const _Toast({required this.msg, required this.error, required this.onDone});
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))..forward();
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    // Errors stay up a little longer: they usually name a printer to go check.
    Future.delayed(Duration(milliseconds: widget.error ? 4000 : 2400), () async {
      if (!mounted) return;
      await _a.reverse();
      if (mounted && !_gone) {
        _gone = true;
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom + 24;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(CurvedAnimation(parent: _a, curve: Curves.easeOut)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  color: C.ink,
                  shape: const StadiumBorder(),
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Dot(color: widget.error ? C.red : const Color(0xFF34A853)),
                      const SizedBox(width: 10),
                      Flexible(child: Text(widget.msg, style: ts(14, c: Colors.white, h: 1.3))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
              // Shrink with the keyboard so a focused field is never pushed under it on short phones.
              constraints: BoxConstraints(
                  maxHeight: (MediaQuery.of(ctx).size.height * .86).clamp(0.0, MediaQuery.of(ctx).size.height - MediaQuery.of(ctx).viewInsets.bottom - MediaQuery.of(ctx).padding.top - 8)),
              child: _BuildOnce(builder: builder)),
        ),
      ),
    );

/// Runs [builder] exactly once per sheet. A modal bottom sheet re-invokes its builder whenever
/// the keyboard changes `viewInsets` (every focus move on Android), and sheets that create their
/// TextEditingControllers inside the builder would otherwise lose what was typed.
class _BuildOnce extends StatefulWidget {
  final WidgetBuilder builder;
  const _BuildOnce({required this.builder});
  @override
  State<_BuildOnce> createState() => _BuildOnceState();
}

class _BuildOnceState extends State<_BuildOnce> {
  Widget? _child;
  @override
  Widget build(BuildContext context) => _child ??= widget.builder(context);
}

Future<T?> showPanelDialog<T>(BuildContext context, {required WidgetBuilder builder, double maxWidth = 520}) =>
    showDialog<T>(
      context: context,
      barrierColor: const Color(0x59141414),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.of(ctx).size.height * .92),
          child: builder(ctx),
        ),
      ),
    );

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String body, String ok = 'Confirm', Color okColor = C.blue, String cancel = 'Cancel'}) async {
  final r = await showPanelDialog<bool>(context,
      maxWidth: 420,
      builder: (ctx) => KeyScope(
          autofocus: true,
          keys: [
            Hotkey(const SingleActivator(LogicalKeyboardKey.enter), () => Navigator.pop(ctx, true)),
            Hotkey(const SingleActivator(LogicalKeyboardKey.numpadEnter), () => Navigator.pop(ctx, true)),
          ],
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: ts(20, w: w5)),
              const SizedBox(height: 8),
              Text(body, style: ts(15, c: C.ink2, h: 1.45)),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: Btn.outline(cancel, expand: true, onTap: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(child: Btn(ok, bg: okColor, expand: true, onTap: () => Navigator.pop(ctx, true))),
              ]),
            ]),
          )));
  return r ?? false;
}

class SumRow extends StatelessWidget {
  final String a, b;
  final bool big;
  const SumRow(this.a, this.b, {super.key, this.big = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: big ? ts(17, w: w6) : ts(14, c: C.ink2))),
          Text(b, style: big ? ts(17, w: w6) : ts(14, c: C.ink2)),
        ]),
      );
}
