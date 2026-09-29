import 'package:flutter/material.dart';
import '../models.dart';
import '../pos/printers_screen.dart';
import '../theme.dart';
import 'common.dart';

(Color, String) printerHealthLook(PrinterStatus st) => switch (st.health) {
      PrinterHealth.online => (C.green, 'Online'),
      PrinterHealth.offline => (C.red, 'Offline'),
      PrinterHealth.checking => (C.amber, 'Checking…'),
      PrinterHealth.unknown => (C.faint, 'Not checked'),
    };

String printerStatusLine(PrinterStatus st) {
  final (_, label) = printerHealthLook(st);
  final when = st.at == null ? '' : ' · ${minsSince(st.at!) < 1 ? 'just now' : '${elapsed(st.at!)} ago'}';
  return st.health == PrinterHealth.offline && st.error != null ? '$label$when · ${st.error}' : '$label$when';
}

/// Header chip: are the printers reachable? Green when every printer answered,
/// red naming how many didn't. Tap for details and a re-check.
class PrinterStatusChip extends StatelessWidget {
  const PrinterStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    if (s.printers.isEmpty) return const SizedBox.shrink();
    final off = s.offlinePrinters.length;
    final checking = s.printers.any((p) => s.statusOf(p).health == PrinterHealth.checking);
    final allOk = s.printers.every((p) => s.statusOf(p).health == PrinterHealth.online);
    // Quiet when all is well (icon + green dot); loud and red when a printer is down.
    final Widget status = off > 0
        ? Text('$off printer${off == 1 ? '' : 's'} offline', style: ts(14, w: w6, c: Colors.white))
        : checking
            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
            : Dot(color: allOk ? C.green : C.faint);
    return Tooltip(
      message: off > 0 ? 'Printer offline · tap for details' : (allOk ? 'All printers online' : 'Printer status'),
      child: Material(
        color: off > 0 ? C.red : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: off > 0 ? C.red : C.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showPrinterStatus(context),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(off > 0 ? Icons.print_disabled_outlined : Icons.print_outlined, size: 18, color: off > 0 ? Colors.white : C.ink2),
              const SizedBox(width: 8),
              status,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Every printer with its last check, a per-printer retry, and "Check all".
Future<void> showPrinterStatus(BuildContext context) => showPanelDialog(context,
    maxWidth: 520,
    builder: (ctx) {
      final s = StoreScope.of(ctx);
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
          child: Row(children: [
            Expanded(child: Text('Printers', style: ts(20, w: w5))),
            RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(ctx)),
          ]),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8), children: [
            for (final p in s.printers)
              Builder(builder: (_) {
                final st = s.statusOf(p);
                final (color, _) = printerHealthLook(st);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 6), child: Dot(color: color, size: 10)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: ts(15, w: w5)),
                        Text('${p.conn.label} · ${p.connSummary}', style: ts(12, c: C.muted)),
                        const SizedBox(height: 2),
                        Text(printerStatusLine(st),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: ts(13, c: st.health == PrinterHealth.offline ? C.redInk : C.ink2)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Btn.outline('Retry',
                        height: 38,
                        fontSize: 13,
                        onTap: st.health == PrinterHealth.checking ? null : () => s.checkPrinters(only: p)),
                  ]),
                );
              }),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Btn.outline('Manage printers', expand: true, onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintersScreen()));
              }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Btn(s.checkingPrinters ? 'Checking…' : 'Check all',
                  icon: s.checkingPrinters ? null : Icons.refresh,
                  expand: true,
                  onTap: s.checkingPrinters ? null : () => s.checkPrinters()),
            ),
          ]),
        ),
      ]);
    });
