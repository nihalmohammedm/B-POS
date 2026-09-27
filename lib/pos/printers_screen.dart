import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

IconData _connIcon(PrinterConn c) => switch (c) {
      PrinterConn.usb => Icons.usb,
      PrinterConn.bluetooth => Icons.bluetooth,
      PrinterConn.lan => Icons.wifi,
    };

class PrintersScreen extends StatefulWidget {
  const PrintersScreen({super.key});
  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  Future<void> _testPrint(Store s, PosPrinter p) async {
    toast(context, 'Sending test ticket to ${p.name}…');
    final ok = await s.testPrint(p);
    if (!mounted) return;
    toast(context, ok ? 'Test ticket sent to ${p.name}' : 'Could not reach ${p.name}', error: !ok);
  }

  Future<void> _delete(Store s, PosPrinter p) async {
    final ok = await confirmDialog(context,
        title: 'Remove ${p.name}?', body: 'Any KOTs or bills assigned to this printer will need a new printer picked.', ok: 'Remove', okColor: C.red);
    if (ok) s.removePrinter(p.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              RoundIcon(Icons.arrow_back, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Back'),
              const SizedBox(width: 14),
              Expanded(child: Text('Printers', style: ts(22, w: w5))),
              Btn('Add printer', icon: Icons.add, onTap: () => showEditPrinterSheet(context, s)),
            ]),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (s.printers.isEmpty)
                        Panel(
                          child: Column(children: [
                            const SizedBox(height: 8),
                            Icon(Icons.print_outlined, size: 32, color: C.faint),
                            const SizedBox(height: 10),
                            Text('No printers set up yet', style: ts(15, w: w5)),
                            const SizedBox(height: 4),
                            Text('Add one over USB, Bluetooth or your network.', style: ts(13, c: C.muted)),
                            const SizedBox(height: 8),
                          ]),
                        )
                      else
                        for (final p in s.printers) ...[_printerCard(s, p), const SizedBox(height: 12)],
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _printerCard(Store s, PosPrinter p) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: C.soft, borderRadius: BorderRadius.circular(14)),
              child: Icon(_connIcon(p.conn), size: 20, color: C.ink2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: ts(16, w: w5)),
                const SizedBox(height: 2),
                Text('${p.conn.label} · ${p.connSummary}${p.station.isEmpty ? '' : ' · ${p.station}'}',
                    style: ts(13, c: C.muted)),
              ]),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: C.ink2),
              onSelected: (v) => v == 'edit' ? showEditPrinterSheet(context, s, existing: p) : _delete(s, p),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Remove')),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            if (p.forBill) const Pill('Bill', bg: C.skyTint, fg: C.skyInk),
            if (p.forBill && p.forKot) const SizedBox(width: 8),
            if (p.forKot) const Pill('KOT', bg: C.amberTint, fg: C.amberInk),
            if (!p.forBill && !p.forKot) const Pill('Not assigned', bg: C.soft, fg: C.muted),
            const Spacer(),
            if (p.lastTestAt != null)
              Row(children: [
                Dot(color: p.lastTestOk == true ? C.green : C.red, size: 7),
                const SizedBox(width: 6),
                Text('Tested ${elapsed(p.lastTestAt!)} ago', style: ts(12, c: C.muted)),
                const SizedBox(width: 12),
              ]),
            Btn.outline('Test print', height: 38, fontSize: 13, onTap: () => _testPrint(s, p)),
          ]),
        ]),
      );
}

Future<void> showEditPrinterSheet(BuildContext context, Store s, {PosPrinter? existing}) => showSheet(context, (ctx) {
      final nameC = TextEditingController(text: existing?.name ?? '');
      final stationC = TextEditingController(text: existing?.station ?? '');
      final ipC = TextEditingController(text: existing?.ip ?? '');
      final portC = TextEditingController(text: '${existing?.port ?? 9100}');
      final btC = TextEditingController(text: existing?.btAddress ?? '');
      final usbC = TextEditingController(text: existing?.usbIdentifier ?? '');
      var conn = existing?.conn ?? PrinterConn.lan;
      var forBill = existing?.forBill ?? false;
      var forKot = existing?.forKot ?? false;

      return StatefulBuilder(builder: (ctx, set) {
        void save() {
          final name = nameC.text.trim();
          if (name.isEmpty) {
            toast(context, 'Give the printer a name', error: true);
            return;
          }
          if (!forBill && !forKot) {
            toast(context, 'Pick at least one of Bill or KOT', error: true);
            return;
          }
          final p = PosPrinter(
            id: existing?.id ?? s.nextPrinterId(),
            name: name,
            conn: conn,
            station: stationC.text.trim(),
            forBill: forBill,
            forKot: forKot,
            ip: ipC.text.trim(),
            port: int.tryParse(portC.text.trim()) ?? 9100,
            btAddress: btC.text.trim(),
            usbIdentifier: usbC.text.trim(),
            lastTestAt: existing?.lastTestAt,
            lastTestOk: existing?.lastTestOk,
          );
          existing == null ? s.addPrinter(p) : s.updatePrinter(p);
          Navigator.pop(ctx);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existing == null ? 'Add printer' : 'Edit printer', style: ts(20, w: w5)),
            const SizedBox(height: 18),
            const Label('Name'),
            const SizedBox(height: 6),
            TextField(controller: nameC, style: ts(14), decoration: const InputDecoration(hintText: 'e.g. Kitchen (TM-T82)')),
            const SizedBox(height: 14),
            const Label('Connection'),
            const SizedBox(height: 8),
            Seg<PrinterConn>(
              expand: true,
              items: const [(PrinterConn.usb, 'USB'), (PrinterConn.bluetooth, 'Bluetooth'), (PrinterConn.lan, 'LAN')],
              value: conn,
              onChanged: (v) => set(() => conn = v),
            ),
            const SizedBox(height: 14),
            if (conn == PrinterConn.lan) ...[
              Row(children: [
                Expanded(
                  flex: 2,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Label('IP address'),
                    const SizedBox(height: 6),
                    TextField(controller: ipC, style: ts(14), decoration: const InputDecoration(hintText: '192.168.1.50')),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Label('Port'),
                    const SizedBox(height: 6),
                    TextField(controller: portC, style: ts(14), keyboardType: TextInputType.number),
                  ]),
                ),
              ]),
            ] else if (conn == PrinterConn.bluetooth) ...[
              const Label('Paired device name / MAC address'),
              const SizedBox(height: 6),
              TextField(controller: btC, style: ts(14), decoration: const InputDecoration(hintText: 'e.g. BT-Printer-04:56')),
              const SizedBox(height: 6),
              Text('Device scanning needs the Android app — enter it manually for now.', style: ts(12, c: C.muted)),
            ] else ...[
              const Label('USB device name / port'),
              const SizedBox(height: 6),
              TextField(controller: usbC, style: ts(14), decoration: const InputDecoration(hintText: 'e.g. /dev/usb/lp0')),
              const SizedBox(height: 6),
              Text('Device picking needs the Android app — enter it manually for now.', style: ts(12, c: C.muted)),
            ],
            const SizedBox(height: 14),
            const Label('Station (optional)'),
            const SizedBox(height: 6),
            TextField(controller: stationC, style: ts(14), decoration: const InputDecoration(hintText: 'e.g. Counter, Grill, Bar')),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Text('Print bills', style: ts(15))),
              Toggle(value: forBill, onChanged: (v) => set(() => forBill = v)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('Print KOTs', style: ts(15))),
              Toggle(value: forKot, onChanged: (v) => set(() => forKot = v)),
            ]),
            const SizedBox(height: 22),
            Btn(existing == null ? 'Add printer' : 'Save changes', expand: true, onTap: save),
          ]),
        );
      });
    });
