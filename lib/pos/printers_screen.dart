import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart' as esc;
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/printer_status.dart';

IconData _connIcon(PrinterConn c) => switch (c) {
      PrinterConn.usb => Icons.usb,
      PrinterConn.bluetooth => Icons.bluetooth,
      PrinterConn.lan => Icons.wifi,
    };

class _Found {
  final String name;
  final String detail;
  final String? ip, btAddress, usbIdentifier;
  const _Found({required this.name, required this.detail, this.ip, this.btAddress, this.usbIdentifier});
}

/// Real device discovery via `unified_esc_pos_printer`'s [esc.PrinterManager]:
/// a genuine TCP port-9100 subnet sweep for LAN, classic-Bluetooth + BLE device
/// discovery for Bluetooth, and OS-level USB/serial enumeration for USB. No
/// canned results — an empty list means nothing was actually found.
///
/// Bluetooth (classic SPP) only works at runtime on Android; USB works on
/// Android (OTG) and desktop. On unsupported platforms the underlying
/// connector just yields no devices rather than throwing.
final _printerManager = esc.PrinterManager();

Future<List<_Found>> _scanFor(PrinterConn conn) async {
  final types = switch (conn) {
    PrinterConn.lan => const {esc.PrinterConnectionType.network},
    PrinterConn.bluetooth => const {esc.PrinterConnectionType.bluetooth, esc.PrinterConnectionType.ble},
    PrinterConn.usb => const {esc.PrinterConnectionType.usb},
  };
  List<esc.PrinterDevice> devices;
  try {
    devices = await _printerManager.scanPrinters(timeout: const Duration(seconds: 5), types: types);
  } catch (_) {
    devices = const [];
  }
  return [
    for (final d in devices)
      if (d is esc.NetworkPrinterDevice)
        _Found(name: d.name, detail: '${d.host} · port ${d.port}', ip: d.host)
      else if (d is esc.BluetoothPrinterDevice)
        _Found(name: d.name, detail: 'Bluetooth · ${d.address}', btAddress: d.address)
      else if (d is esc.BlePrinterDevice)
        _Found(name: d.name, detail: 'BLE · ${d.deviceId}', btAddress: d.deviceId)
      else if (d is esc.UsbPrinterDevice)
        _Found(name: d.name, detail: 'USB · ${d.identifier}', usbIdentifier: d.identifier),
  ];
}

class PrintersScreen extends StatefulWidget {
  const PrintersScreen({super.key});
  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  Future<void> _testPrint(Store s, PosPrinter p) async {
    toast(context, 'Sending test ticket to ${p.name}…');
    final err = await s.testPrint(p);
    if (!mounted) return;
    toast(context, err == null ? 'Test ticket sent to ${p.name}' : 'Could not print to ${p.name}: $err', error: err != null);
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
              if (s.printers.isNotEmpty) ...[
                Btn.outline(s.checkingPrinters ? 'Checking…' : 'Check all',
                    icon: s.checkingPrinters ? null : Icons.refresh, onTap: s.checkingPrinters ? null : () => s.checkPrinters()),
                const SizedBox(width: 10),
              ],
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
            Btn.outline('Check',
                height: 38,
                fontSize: 13,
                onTap: s.statusOf(p).health == PrinterHealth.checking ? null : () => s.checkPrinters(only: p)),
            const SizedBox(width: 8),
            Btn.outline('Test print', height: 38, fontSize: 13, onTap: () => _testPrint(s, p)),
          ]),
          const SizedBox(height: 12),
          Builder(builder: (_) {
            final st = s.statusOf(p);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 5), child: Dot(color: printerHealthLook(st).$1, size: 8)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(printerStatusLine(st),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ts(13, c: st.health == PrinterHealth.offline ? C.redInk : C.ink2))),
            ]);
          }),
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
      var scanning = false;
      var hasScanned = false;
      List<_Found> found = [];

      return StatefulBuilder(builder: (ctx, set) {
        Future<void> scan() async {
          set(() {
            scanning = true;
            hasScanned = false;
            found = [];
          });
          final r = await _scanFor(conn);
          set(() {
            scanning = false;
            hasScanned = true;
            found = r;
          });
        }

        void pick(_Found f) => set(() {
              nameC.text = f.name;
              ipC.text = f.ip ?? ipC.text;
              btC.text = f.btAddress ?? btC.text;
              usbC.text = f.usbIdentifier ?? usbC.text;
              if (f.ip != null) portC.text = '9100';
              found = [];
            });

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
              onChanged: (v) => set(() {
                conn = v;
                found = [];
                hasScanned = false;
              }),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: switch (conn) {
                  PrinterConn.lan => const Label('IP address'),
                  PrinterConn.bluetooth => const Label('Paired device name / MAC address'),
                  PrinterConn.usb => const Label('USB device name / port'),
                },
              ),
              Btn.outline(scanning ? 'Scanning…' : 'Scan',
                  icon: scanning ? null : Icons.search, height: 30, fontSize: 12, onTap: scanning ? null : scan),
            ]),
            const SizedBox(height: 6),
            if (conn == PrinterConn.lan) ...[
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(controller: ipC, style: ts(14), decoration: const InputDecoration(hintText: '192.168.1.50')),
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
              TextField(controller: btC, style: ts(14), decoration: const InputDecoration(hintText: 'e.g. BT-Printer-04:56')),
            ] else ...[
              TextField(
                controller: usbC,
                style: ts(14),
                decoration: InputDecoration(
                  hintText: defaultTargetPlatform == TargetPlatform.windows
                      ? 'Windows printer name, e.g. POS-80C'
                      : 'e.g. /dev/ttyUSB0',
                ),
              ),
            ],
            if (scanning) ...[
              const SizedBox(height: 10),
              const ClipRRect(borderRadius: BorderRadius.all(Radius.circular(999)), child: LinearProgressIndicator(minHeight: 3)),
            ],
            if (hasScanned && found.isEmpty) ...[
              const SizedBox(height: 10),
              Text(
                conn == PrinterConn.bluetooth &&
                        defaultTargetPlatform != TargetPlatform.android &&
                        defaultTargetPlatform != TargetPlatform.windows
                    ? 'No Bluetooth printers found · classic Bluetooth scanning only works on Android and Windows'
                    : 'No printers found on this connection',
                style: ts(12, c: C.muted),
              ),
            ],
            if (found.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(14)),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (var i = 0; i < found.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    InkWell(
                      onTap: () => pick(found[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Icon(_connIcon(conn), size: 18, color: C.ink2),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(found[i].name, style: ts(14, w: w5)),
                              Text(found[i].detail, style: ts(12, c: C.muted)),
                            ]),
                          ),
                          Text('Use', style: ts(13, w: w5, c: C.blue)),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ),
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
