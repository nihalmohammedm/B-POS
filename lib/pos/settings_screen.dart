import 'package:flutter/material.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'printers_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url, _key, _outlet;

  @override
  void initState() {
    super.initState();
    final s = StoreScope.read(context);
    _url = TextEditingController(text: s.backofficeUrl);
    _key = TextEditingController(text: s.backofficeKey);
    _outlet = TextEditingController(text: s.backofficeOutletCode);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _outlet.dispose();
    super.dispose();
  }

  void _saveConnection(Store s) {
    s.setBackofficeConfig(url: _url.text.trim(), key: _key.text.trim(), outletCode: _outlet.text.trim());
    toast(context, 'Backoffice connection saved');
  }

  Future<void> _sync(Store s) async {
    try {
      final r = await s.syncMenu();
      if (!mounted) return;
      toast(
        context,
        r.changed == 0
            ? 'Menu is already up to date'
            : 'Menu synced · ${[
                if (r.added > 0) '${r.added} new',
                if (r.updated > 0) '${r.updated} updated',
                if (r.removed > 0) '${r.removed} removed',
              ].join(' · ')}',
      );
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Sync failed · ${s.lastSyncError ?? e}', error: true);
    }
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
              Text('Settings', style: ts(22, w: w5)),
            ]),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _connectionPanel(s),
                      const SizedBox(height: 16),
                      _syncPanel(s),
                      const SizedBox(height: 16),
                      _printersPanel(s),
                      const SizedBox(height: 16),
                      _overviewPanel(s),
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

  Widget _connectionPanel(Store s) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Backoffice connection', style: ts(17, w: w5)),
          const SizedBox(height: 4),
          Text('Where this till pulls its menu, prices and availability from.', style: ts(13, c: C.muted, h: 1.4)),
          const SizedBox(height: 18),
          const Label('Backoffice URL'),
          const SizedBox(height: 6),
          TextField(controller: _url, style: ts(14), decoration: const InputDecoration(hintText: 'https://backoffice.example.com')),
          const SizedBox(height: 14),
          const Label('API key'),
          const SizedBox(height: 6),
          TextField(controller: _key, style: ts(14), obscureText: true, decoration: const InputDecoration(hintText: 'API key')),
          const SizedBox(height: 14),
          const Label('Outlet code'),
          const SizedBox(height: 6),
          TextField(controller: _outlet, style: ts(14), decoration: const InputDecoration(hintText: 'e.g. BOLGATTY')),
          const SizedBox(height: 16),
          Row(children: [
            Dot(color: s.lastSyncError == null ? C.green : C.red),
            const SizedBox(width: 8),
            Expanded(child: Text(s.lastSyncError == null ? 'Connected' : 'Last sync failed', style: ts(13, c: C.ink2))),
            Btn.outline('Save', onTap: () => _saveConnection(s)),
          ]),
        ]),
      );

  Widget _syncPanel(Store s) {
    final last = s.lastMenuSync;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Menu sync', style: ts(17, w: w5)),
              const SizedBox(height: 4),
              Text(last == null ? 'Never synced' : 'Last synced ${elapsed(last)} ago', style: ts(13, c: C.muted)),
            ]),
          ),
          Btn(
            s.syncingMenu ? 'Syncing…' : 'Sync now',
            icon: s.syncingMenu ? null : Icons.sync,
            onTap: s.syncingMenu ? null : () => _sync(s),
          ),
        ]),
        if (s.syncingMenu) ...[
          const SizedBox(height: 16),
          const ClipRRect(borderRadius: BorderRadius.all(Radius.circular(999)), child: LinearProgressIndicator(minHeight: 4)),
        ],
        if (s.lastSyncResult != null && !s.syncingMenu) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Pill('${s.menu.length} items total', bg: C.soft),
            if (s.lastSyncResult!.added > 0) Pill('+${s.lastSyncResult!.added} new', bg: C.greenTint, fg: C.greenInk),
            if (s.lastSyncResult!.updated > 0) Pill('${s.lastSyncResult!.updated} updated', bg: C.skyTint, fg: C.skyInk),
            if (s.lastSyncResult!.removed > 0) Pill('${s.lastSyncResult!.removed} removed', bg: C.redTint, fg: C.redInk),
            if (s.lastSyncResult!.changed == 0) const Pill('Up to date', bg: C.soft),
          ]),
        ],
      ]),
    );
  }

  Widget _printersPanel(Store s) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Printers', style: ts(17, w: w5)),
                const SizedBox(height: 4),
                Text('USB, Bluetooth or network — for bills and kitchen tickets.', style: ts(13, c: C.muted, h: 1.4)),
              ]),
            ),
            Btn.outline('Manage',
                icon: Icons.chevron_right,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintersScreen()))),
          ]),
          if (s.printers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in s.printers)
                Pill('${p.name} · ${[if (p.forBill) 'Bill', if (p.forKot) 'KOT'].join('/')}', bg: C.soft),
            ]),
          ],
        ]),
      );

  Widget _overviewPanel(Store s) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Menu overview', style: ts(17, w: w5)),
          const SizedBox(height: 4),
          Text('${s.menu.length} items across ${s.categories.length} categories', style: ts(13, c: C.muted)),
          const SizedBox(height: 16),
          for (final c in s.categories) _catRow(s, c),
        ]),
      );

  Widget _catRow(Store s, String c) {
    final color = colorForCategory(c).$1;
    final count = s.itemsIn(c).length;
    final off = s.catOff.contains(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Dot(color: off ? C.faint : color, size: 10),
        const SizedBox(width: 10),
        Expanded(child: Text(c, style: ts(14, w: w5, c: off ? C.muted : C.ink))),
        Text('$count items', style: ts(13, c: C.muted)),
        if (off) ...[const SizedBox(width: 8), const Pill('OFF', bg: C.soft, fg: C.ink2, size: 11)],
      ]),
    );
  }
}
