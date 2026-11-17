import 'package:flutter/material.dart';
import '../plain_error.dart';
import '../sync/device_api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings → Main POS devices: every Main POS registered for this outlet (bpos.pos_devices) with
/// whether it is running right now (heartbeat in the last 3 minutes), its app version and last sync.
class DevicesPanel extends StatefulWidget {
  const DevicesPanel({super.key});
  @override
  State<DevicesPanel> createState() => _DevicesPanelState();
}

class _DevicesPanelState extends State<DevicesPanel> {
  List<PosDeviceInfo>? _devices;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = StoreScope.read(context);
    setState(() => _busy = true);
    try {
      await s.heartbeat();
      final list = await s.fetchPosDevices();
      if (mounted) setState(() => (_devices = list, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = plainError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) toast(context, done);
      await _load();
    } catch (e) {
      if (mounted) toast(context, plainError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = _devices;
    final running = list?.where((d) => d.online).length ?? 0;
    final canManage = s.can('device.manage');
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Main POS devices', style: ts(17, w: w5))),
          Btn.outline(_busy ? 'Refreshing…' : 'Refresh', icon: Icons.refresh, height: 40, onTap: _busy ? null : _load),
        ]),
        const SizedBox(height: 4),
        Text(
            list == null
                ? 'Every Main POS of this outlet shows up here once it has signed in.'
                : '$running of ${list.length} running now',
            style: ts(13, c: C.muted, h: 1.4)),
        if (s.deviceRemoved) ...[
          const SizedBox(height: 10),
          Pill('This POS was removed from the outlet by a manager', bg: C.redTint, fg: C.redInk, size: 13),
        ],
        const SizedBox(height: 14),
        if (s.heartbeatError != null) ...[
          Text('This POS could not register: ${s.heartbeatError}', style: ts(13, c: C.redInk, h: 1.4)),
          const SizedBox(height: 10),
        ],
        if (_error != null)
          Text(_error!, style: ts(13, c: C.redInk))
        else if (list == null)
          Text('Loading…', style: ts(13, c: C.muted))
        else if (list.isEmpty)
          Text('No devices registered yet.', style: ts(13, c: C.muted)),
        for (final d in list ?? const <PosDeviceInfo>[])
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
                color: d.code == s.posId ? C.skyTint : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.line)),
            child: Row(children: [
              Dot(color: d.online ? C.green : C.faint, size: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(d.name, style: ts(15, w: w5)),
                    if (d.code == s.posId) const Pill('THIS DEVICE', bg: C.blue, fg: Colors.white, size: 10),
                    if (d.isPrimary) const Pill('PRIMARY', bg: C.ink, fg: Colors.white, size: 10),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                      [
                        d.online ? 'Running' : d.lastSeen == null ? 'Never seen' : 'Offline · last seen ${elapsed(d.lastSeen!)} ago',
                        if (d.platform != null) d.platform!,
                        if (d.appVersion != null) 'v${d.appVersion}',
                      ].join(' · '),
                      style: ts(12, c: C.ink2)),
                  if (d.lastSync != null) Text('Last synced ${elapsed(d.lastSync!)} ago', style: ts(12, c: C.muted)),
                ]),
              ),
              if (canManage && !d.isPrimary && d.isActive)
                RoundIcon(Icons.star_outline,
                    size: 40, tooltip: 'Make primary', onTap: () => _act(() => s.makePosPrimary(d.id), '${d.name} is now primary')),
              if (canManage && d.code != s.posId) ...[
                const SizedBox(width: 6),
                RoundIcon(Icons.delete_outline, size: 40, fg: C.red, tooltip: 'Remove', onTap: () async {
                  final ok = await confirmDialog(context,
                      title: 'Remove ${d.name}?',
                      body: 'It stays in the history but no longer counts as a running POS.',
                      ok: 'Remove',
                      okColor: C.red);
                  if (ok && mounted) _act(() => s.removePosDevice(d.id), '${d.name} removed');
                }),
              ],
            ]),
          ),
      ]),
    );
  }
}
