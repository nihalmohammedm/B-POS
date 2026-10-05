import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../link/captain_link.dart';
import '../link/link_models.dart';
import '../theme.dart';
import '../updater.dart';
import '../widgets/common.dart';
import 'captain.dart';

/// Captain app root: pair with the main POS first, then the captain screens
/// with a strip that says when the POS can't be reached.
class CaptainGate extends StatelessWidget {
  const CaptainGate({super.key});
  @override
  Widget build(BuildContext context) {
    final link = CaptainLinkScope.maybeOf(context)!;
    if (link.state == LinkState.unpaired) return const PairScreen();
    return Column(children: [
      const _LinkStrip(),
      const Expanded(child: CaptainFrame()),
    ]);
  }
}

class _LinkStrip extends StatelessWidget {
  const _LinkStrip();
  @override
  Widget build(BuildContext context) {
    final link = CaptainLinkScope.maybeOf(context)!;
    if (link.online) return const SizedBox.shrink();
    final connecting = link.state == LinkState.connecting;
    return Material(
      color: connecting ? C.amber : C.red,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: link.reconnect,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(children: [
              Icon(connecting ? Icons.sync : Icons.wifi_off, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    connecting ? 'Connecting to the POS…' : 'Not connected to the POS · orders can\'t be sent · retrying',
                    style: ts(13, w: w6, c: Colors.white)),
              ),
              if (!connecting) Text('Retry', style: ts(13, w: w7, c: Colors.white, deco: TextDecoration.underline)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Status of the link to the POS, with Reconnect and Unpair.
Future<void> showConnectionSheet(BuildContext context) {
  final link = CaptainLinkScope.read(context);
  if (link == null) return Future.value();
  return showSheet(context, (ctx) {
    final l = CaptainLinkScope.maybeOf(ctx)!;
    final (color, label) = switch (l.state) {
      LinkState.online => (C.green, 'Connected'),
      LinkState.connecting => (C.amber, 'Connecting…'),
      LinkState.offline => (C.red, 'Not connected'),
      LinkState.unpaired => (C.faint, 'Not paired'),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Main POS', style: ts(20, w: w5)),
        const SizedBox(height: 12),
        Row(children: [
          Dot(color: color, size: 10),
          const SizedBox(width: 8),
          Text(label, style: ts(16, w: w5)),
        ]),
        const SizedBox(height: 10),
        Text('${l.outletName.isEmpty ? 'POS' : l.outletName} · ${l.host ?? '—'}:${l.port}', style: ts(14, c: C.ink2)),
        Text('Signed in as ${l.captainName}', style: ts(14, c: C.ink2)),
        if (l.lastSnapshotAt != null) Text('Last update ${elapsed(l.lastSnapshotAt!)} ago', style: ts(13, c: C.muted)),
        if (!l.online && l.lastError != null) ...[
          const SizedBox(height: 6),
          Text(l.lastError!, style: ts(13, c: C.redInk)),
        ],
        const SizedBox(height: 18),
        Btn('Reconnect now', icon: Icons.sync, expand: true, onTap: l.reconnect),
        const SizedBox(height: 10),
        Btn.outline('Unpair this phone', expand: true, fg: C.redInk, onTap: () async {
          final ok = await confirmDialog(ctx,
              title: 'Unpair from the POS?',
              body: 'This phone will stop receiving orders. Pair again from the POS to reconnect.',
              ok: 'Unpair',
              okColor: C.red);
          if (!ok) return;
          await l.unpair();
          if (ctx.mounted) Navigator.pop(ctx);
        }),
      ]),
    );
  });
}

bool get _canScan =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

/// Pair with the main POS: scan the QR it shows, or type its address and code.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key});
  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final nameC = TextEditingController(), hostC = TextEditingController(), codeC = TextEditingController();
  bool busy = false, typing = !_canScan;
  String? error;

  @override
  void dispose() {
    nameC.dispose();
    hostC.dispose();
    codeC.dispose();
    super.dispose();
  }

  bool get _kitchen => CaptainLinkScope.read(context)!.kind == deviceKitchen;
  String get _nameFirst => _kitchen
      ? 'Name this station first · e.g. Grill or Main kitchen'
      : 'Enter your name first · it goes on every order you take';

  Future<void> _pair(List<String> hosts, int port, String secret) async {
    final name = nameC.text.trim();
    if (name.isEmpty) {
      setState(() => error = _nameFirst);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final err = await CaptainLinkScope.read(context)!.pair(hosts: hosts, port: port, secret: secret, name: name);
    if (mounted) {
      setState(() {
        busy = false;
        error = err;
      });
    }
  }

  Future<void> _scan() async {
    if (nameC.text.trim().isEmpty) {
      setState(() => error = _nameFirst);
      return;
    }
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _Scanner()));
    if (raw == null || !mounted) return;
    final t = PairTarget.parse(raw);
    if (t == null) {
      setState(() => error = 'That isn\'t a BPOS pairing code · open Settings › Captains › Pair on the POS');
      return;
    }
    await _pair(t.hosts, t.port, t.secret);
  }

  void _typed() {
    final h = hostC.text.trim();
    final (host, port) = h.contains(':') ? (h.split(':').first, int.tryParse(h.split(':').last) ?? linkPort) : (h, linkPort);
    if (host.isEmpty || normalizeCode(codeC.text).length != 8) {
      setState(() => error = 'Enter the POS address and the 8-character code shown on the POS');
      return;
    }
    _pair([host], port, codeC.text);
  }

  @override
  Widget build(BuildContext context) {
    final link = CaptainLinkScope.maybeOf(context)!;
    final kitchen = link.kind == deviceKitchen;
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(kitchen ? Icons.soup_kitchen_outlined : Icons.phonelink_ring_outlined, size: 44, color: C.blueDeep),
                const SizedBox(height: 12),
                Text(kitchen ? 'Pair this kitchen display' : 'Pair with the main POS',
                    textAlign: TextAlign.center, style: ts(22, w: w6)),
                const SizedBox(height: 6),
                Text('On the POS open Settings › Captains › Pair a captain. Both devices must be on the restaurant Wi-Fi.',
                    textAlign: TextAlign.center, style: ts(14, c: C.muted, h: 1.4)),
                if (link.lastError != null && error == null) ...[
                  const SizedBox(height: 12),
                  Text(link.lastError!, textAlign: TextAlign.center, style: ts(13, c: C.redInk)),
                ],
                const SizedBox(height: 22),
                Label(kitchen ? 'Station name' : 'Your name'),
                const SizedBox(height: 6),
                TextField(
                    controller: nameC,
                    textCapitalization: TextCapitalization.words,
                    style: ts(16),
                    decoration: InputDecoration(hintText: kitchen ? 'e.g. Grill' : 'e.g. Arun')),
                const SizedBox(height: 18),
                if (!typing) ...[
                  Btn('Scan the QR on the POS', icon: Icons.qr_code_scanner, height: 60, expand: true, onTap: busy ? null : _scan),
                  const SizedBox(height: 10),
                  TextButton(onPressed: () => setState(() => typing = true), child: const Text('Type the code instead')),
                ] else ...[
                  const Label('POS address'),
                  const SizedBox(height: 6),
                  TextField(
                      controller: hostC,
                      keyboardType: TextInputType.url,
                      style: ts(16),
                      decoration: const InputDecoration(hintText: 'e.g. 192.168.1.20')),
                  const SizedBox(height: 12),
                  const Label('Pairing code'),
                  const SizedBox(height: 6),
                  TextField(
                      controller: codeC,
                      textCapitalization: TextCapitalization.characters,
                      style: ts(18, w: w6, ls: 2),
                      decoration: const InputDecoration(hintText: 'ABCD-EFGH'),
                      onSubmitted: (_) => _typed()),
                  const SizedBox(height: 16),
                  Btn(busy ? 'Pairing…' : 'Pair', icon: busy ? null : Icons.link, height: 56, expand: true, onTap: busy ? null : _typed),
                  if (_canScan) TextButton(onPressed: () => setState(() => typing = false), child: const Text('Scan the QR instead')),
                ],
                if (busy) ...[
                  const SizedBox(height: 14),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (Updater.supported) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                      onPressed: () => showUpdateSheet(context),
                      icon: const Icon(Icons.system_update, size: 18),
                      label: const Text('Check for app update')),
                ],
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.redTint, borderRadius: BorderRadius.circular(12)),
                    child: Text(error!, style: ts(14, c: C.redInk, h: 1.35)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Scanner extends StatefulWidget {
  const _Scanner();
  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> {
  bool _done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Scan the POS pairing QR')),
        body: MobileScanner(
          onDetect: (capture) {
            final v = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (v == null || _done) return;
            _done = true;
            Navigator.pop(context, v);
          },
          errorBuilder: (c, e) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Camera not available: ${e.errorCode.name}. Go back and type the code instead.',
                  textAlign: TextAlign.center, style: ts(15, c: Colors.white)),
            ),
          ),
        ),
      );
}
