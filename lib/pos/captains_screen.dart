import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../link/captain_link.dart';
import '../link/link_models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings › Captains: pair captain phones with this POS over the restaurant
/// Wi-Fi, see who's connected, and remove lost or replaced phones.
class CaptainsScreen extends StatefulWidget {
  const CaptainsScreen({super.key});
  @override
  State<CaptainsScreen> createState() => _CaptainsScreenState();
}

class _CaptainsScreenState extends State<CaptainsScreen> {
  Timer? _tick;
  int _knownDevices = 0;

  @override
  void initState() {
    super.initState();
    _knownDevices = StoreScope.read(context).captainDevices.length;
    // Countdown on the pairing code, and "last seen" times.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    // A new device appeared while the code was up: say who just paired.
    if (s.captainDevices.length > _knownDevices) {
      final d = s.captainDevices.last;
      WidgetsBinding.instance.addPostFrameCallback((_) => toast(context, '${d.name} paired'));
    }
    _knownDevices = s.captainDevices.length;
    final offer = s.pairing;
    if (offer != null && offer.expired) {
      WidgetsBinding.instance.addPostFrameCallback((_) => s.cancelPairing());
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              RoundIcon(Icons.arrow_back, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Back'),
              const SizedBox(width: 14),
              Expanded(child: Text('Captains', style: ts(22, w: w5))),
              if (s.linkRunning && offer == null) Btn('Pair a captain', icon: Icons.qr_code_2, onTap: s.startPairing),
            ]),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _status(s),
                      if (offer != null && !offer.expired) ...[const SizedBox(height: 16), _pairing(s, offer)],
                      const SizedBox(height: 16),
                      _devices(s),
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

  Widget _status(Store s) => Panel(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 5), child: Dot(color: s.linkRunning ? C.green : C.red, size: 10)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.linkRunning ? 'Accepting captains on the restaurant Wi-Fi' : 'Captains can\'t connect', style: ts(16, w: w5)),
              const SizedBox(height: 4),
              if (s.linkRunning)
                Text(
                    s.linkAddresses.isEmpty
                        ? 'Port $linkPort · no network address found · is Wi-Fi on?'
                        : 'Address ${s.linkAddresses.join(' or ')} · port $linkPort · works without internet',
                    style: ts(13, c: C.ink2, h: 1.4))
              else
                Text(s.linkError ?? 'Starting…', style: ts(13, c: C.redInk, h: 1.4)),
              const SizedBox(height: 4),
              Text('${s.connectedCaptains.length} of ${s.captainDevices.length} paired captains connected now',
                  style: ts(13, c: C.muted)),
            ]),
          ),
        ]),
      );

  Widget _pairing(Store s, PairingOffer offer) {
    final left = offer.expiresAt.difference(DateTime.now());
    final qr = PairTarget.encode(s.linkAddresses, linkPort, offer.token, s.outletName);
    final code = '${offer.code.substring(0, 4)}-${offer.code.substring(4)}';
    return Panel(
      child: Wrap(spacing: 24, runSpacing: 18, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
          child: QrImageView(data: qr, size: 220, backgroundColor: Colors.white),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Scan with the captain app', style: ts(18, w: w5)),
            const SizedBox(height: 6),
            Text('Open BPOS Captain on the phone, enter the captain\'s name, and scan this code. Both must be on this Wi-Fi.',
                style: ts(13, c: C.ink2, h: 1.4)),
            const SizedBox(height: 16),
            const Label('Or type'),
            const SizedBox(height: 6),
            Text('Address  ${s.linkAddresses.isEmpty ? '—' : s.linkAddresses.first}', style: ts(15, w: w5)),
            const SizedBox(height: 4),
            SelectableText(code, style: ts(30, w: w7, ls: 3)),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.timer_outlined, size: 16, color: C.muted),
              const SizedBox(width: 6),
              Text('Works once · expires in ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: ts(13, c: C.muted)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Btn.outline('Cancel', height: 44, onTap: s.cancelPairing),
              const SizedBox(width: 10),
              Btn.outline('New code', icon: Icons.refresh, height: 44, onTap: s.startPairing),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _devices(Store s) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Paired captains', style: ts(17, w: w5)),
          const SizedBox(height: 6),
          if (s.captainDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('None yet · tap Pair a captain', style: ts(14, c: C.muted)),
            ),
          for (final d in s.captainDevices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Dot(color: s.connectedCaptains.contains(d.id) ? C.green : C.faint, size: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.name, style: ts(16, w: w5)),
                    Text(
                        [
                          if (d.isKitchen) 'Kitchen display',
                          s.connectedCaptains.contains(d.id)
                              ? 'Connected'
                              : d.lastSeenAt == null
                                  ? 'Never connected'
                                  : 'Last seen ${elapsed(d.lastSeenAt!)} ago',
                          if (d.deviceInfo.isNotEmpty) d.deviceInfo,
                        ].join(' · '),
                        style: ts(13, c: C.muted)),
                  ]),
                ),
                Btn.outline('Remove', height: 40, fontSize: 13, fg: C.redInk, onTap: () async {
                  final ok = await confirmDialog(context,
                      title: 'Remove ${d.name}\'s phone?',
                      body: 'It is disconnected now and has to be paired again to take orders.',
                      ok: 'Remove',
                      okColor: C.red);
                  if (ok) s.removeCaptain(d.id);
                }),
              ]),
            ),
        ]),
      );
}
