import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/printer_status.dart';
import 'printers_screen.dart';

/// Settings › KOT groups: the kitchen sections from the menu, and which
/// printer each one prints on. Groups and item routing come from the
/// backoffice; the printer mapping is per device.
class KotGroupsScreen extends StatefulWidget {
  const KotGroupsScreen({super.key});
  @override
  State<KotGroupsScreen> createState() => _KotGroupsScreenState();
}

class _KotGroupsScreenState extends State<KotGroupsScreen> {
  final _open = <String>{};

  @override
  void initState() {
    super.initState();
    // Show live printer health while picking routes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.of(context).checkPrinters();
    });
  }

  Future<void> _sync(Store s) async {
    try {
      await s.syncMenu();
      if (mounted) toast(context, 'Menu synced · ${s.kotGroups.length} KOT groups');
    } catch (e) {
      if (mounted) toast(context, 'Sync failed · ${s.lastSyncError ?? e}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final ungrouped = s.itemsInGroup(null);
    final rows = <(String?, String, String)>[
      for (final g in s.kotGroups) (g.id, g.name, g.code),
      if (ungrouped > 0 || s.kotGroups.isEmpty) (null, 'No group', 'Items with no KOT group on the menu'),
    ];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                RoundIcon(Icons.arrow_back, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Back'),
                const SizedBox(width: 14),
                Text('KOT groups', style: ts(22, w: w5)),
              ]),
              Btn.outline(s.syncingMenu ? 'Syncing…' : 'Sync menu',
                  icon: s.syncingMenu ? null : Icons.sync, height: 44, onTap: s.syncingMenu ? null : () => _sync(s)),
              Btn.outline(s.checkingPrinters ? 'Checking…' : 'Check printers',
                  icon: s.checkingPrinters ? null : Icons.wifi_tethering,
                  height: 44,
                  onTap: s.checkingPrinters || s.printers.isEmpty ? null : () => s.checkPrinters()),
              Btn.outline('Printers',
                  icon: Icons.print_outlined,
                  height: 44,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintersScreen()))),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                    Text(
                        'Each order is split into one KOT per group. Groups and which items belong to them come from the menu; '
                        'pick the one printer each group prints on here. One printer can take several groups.',
                        style: ts(13, c: C.muted, h: 1.45)),
                    const SizedBox(height: 14),
                    if (s.printers.isEmpty) ...[
                      _warn('No printers set up yet. Add one under Printers, then pick it for each group.'),
                      const SizedBox(height: 14),
                    ],
                    if (s.kotGroups.isEmpty) ...[
                      _warn('The menu has no KOT groups. Create them in the backoffice (kot_groups), assign products, then Sync menu.'),
                      const SizedBox(height: 14),
                    ],
                    for (final r in rows) ...[_group(s, r.$1, r.$2, r.$3), const SizedBox(height: 12)],
                    if (s.printers.isNotEmpty && s.kotGroups.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _byPrinter(s),
                    ],
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _warn(String t) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.amberTint, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.info_outline, color: C.amberInk, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: ts(13, c: C.amberInk, h: 1.4))),
        ]),
      );

  Widget _group(Store s, String? id, String name, String sub) {
    final key = id ?? Store.noGroupKey;
    final picked = s.kotRoutes[key] ?? const <String>{};
    final routed = s.isRouted(id);
    final targets = s.kotPrintersFor(id);
    final count = s.itemsInGroup(id);
    final open = _open.contains(key);
    final assigned = s.printers.where((p) => picked.contains(p.id)).toList();
    final down = assigned.where((p) => s.statusOf(p).health == PrinterHealth.offline).toList();
    final String status;
    final Color tone, ink;
    if (!routed) {
      status = targets.isEmpty
          ? 'No printer assigned · this KOT will not print'
          : 'No printer assigned · prints on ${_fallbackName(s)} until you pick one';
      (tone, ink) = targets.isEmpty ? (C.red, C.redInk) : (C.amber, C.amberInk);
    } else if (down.length == assigned.length) {
      status = '${down.map((p) => p.name).join(', ')} offline · this KOT will not print';
      (tone, ink) = (C.red, C.redInk);
    } else {
      status = 'Prints on ${assigned.map((p) => p.name).join(', ')}'
          '${down.isEmpty ? '' : ' · ${down.map((p) => p.name).join(', ')} offline'}';
      (tone, ink) = down.isEmpty ? (C.green, C.greenInk) : (C.amber, C.amberInk);
    }
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Dot(color: tone, size: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: ts(17, w: w5, c: id == null ? C.ink2 : C.ink)),
              if (sub.isNotEmpty && sub != name) Text(sub, style: ts(12, c: C.muted)),
              const SizedBox(height: 4),
              Text(status, style: ts(13, c: ink, h: 1.35)),
            ]),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() => open ? _open.remove(key) : _open.add(key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('$count items', style: ts(13, c: C.muted)),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 20, color: C.muted),
              ]),
            ),
          ),
        ]),
        if (s.printers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in s.printers) _printerChip(s, p, picked.contains(p.id), (on) => s.setKotRoute(id, p.id, on)),
          ]),
        ],
        if (open) ...[
          const Divider(height: 28),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in s.menu)
              for (final label in _itemLabels(m, id)) Pill(label, bg: C.soft, size: 12),
          ]),
        ],
      ]),
    );
  }

  /// Where unassigned groups print: the counter (bill) printer, else every KOT printer.
  String _fallbackName(Store s) {
    final f = s.kotFallbackPrinters;
    if (f.isEmpty) return 'no printer';
    return s.billPrinters.isNotEmpty
        ? 'the counter printer (${f.first.name})'
        : 'every KOT printer (${f.map((p) => p.name).join(', ')})';
  }

  /// Menu entries that route to [groupId]: the whole item, or just the sizes
  /// that override the item's group.
  List<String> _itemLabels(MenuItem m, String? groupId) {
    if (!m.variants.any((v) => v.kotGroup != null)) return m.kotGroup == groupId ? [m.name] : const [];
    final hits = m.variants.where((v) => (v.kotGroup ?? m.kotGroup) == groupId).toList();
    if (hits.isEmpty) return const [];
    return hits.length == m.variants.length ? [m.name] : [for (final v in hits) '${m.name} · ${v.name}'];
  }

  /// One printer the group can be assigned to, with its live health. Picking
  /// it replaces the group's current printer; tapping it again unassigns.
  Widget _printerChip(Store s, PosPrinter p, bool on, ValueChanged<bool> set) {
    final st = s.statusOf(p);
    final (health, label) = printerHealthLook(st);
    final offline = st.health == PrinterHealth.offline;
    final edge = on ? (offline ? C.red : C.ink) : (offline ? C.red : C.line);
    return Tooltip(
      message: '${p.name} · ${printerStatusLine(st)}',
      child: Material(
        color: on ? edge : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => set(!on),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: edge)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: on ? Colors.white : C.muted),
              const SizedBox(width: 8),
              Text(p.name, style: ts(14, w: w5, c: on ? Colors.white : C.ink)),
              if (p.station.isNotEmpty) Text('  ${p.station}', style: ts(12, c: on ? const Color(0xFFBDBDBD) : C.muted)),
              const SizedBox(width: 10),
              Dot(color: on && offline ? Colors.white : health, size: 8),
              if (offline || st.health == PrinterHealth.checking) ...[
                const SizedBox(width: 6),
                Text(label, style: ts(12, w: w6, c: on ? Colors.white : (offline ? C.redInk : C.amberInk))),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  /// The same mapping read the other way: what each printer has been assigned.
  /// Only explicit picks count; unassigned groups are listed on their own.
  Widget _byPrinter(Store s) {
    final hasUngrouped = s.itemsInGroup(null) > 0;
    bool assigned(String? groupId, PosPrinter p) => (s.kotRoutes[groupId ?? Store.noGroupKey] ?? const {}).contains(p.id);
    final unassigned = [
      for (final g in s.kotGroups)
        if (!s.isRouted(g.id)) g.name,
      if (hasUngrouped && !s.isRouted(null)) 'No group',
    ];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('By printer', style: ts(17, w: w5)),
        const SizedBox(height: 10),
        for (final p in s.printers)
          Builder(builder: (_) {
            final st = s.statusOf(p);
            final (color, label) = printerHealthLook(st);
            final groups = [
              for (final g in s.kotGroups)
                if (assigned(g.id, p)) g.name,
              if (hasUngrouped && assigned(null, p)) 'No group',
            ];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 200,
                  child: Row(children: [
                    Dot(color: color, size: 8),
                    const SizedBox(width: 8),
                    Flexible(child: Text(p.name, style: ts(14, w: w5), overflow: TextOverflow.ellipsis)),
                    if (st.health == PrinterHealth.offline) Text('  $label', style: ts(12, w: w6, c: C.redInk)),
                  ]),
                ),
                Expanded(
                  child: Text(groups.isEmpty ? 'Nothing assigned' : groups.join(' · '),
                      style: ts(14, c: groups.isEmpty ? C.muted : C.ink2)),
                ),
              ]),
            );
          }),
        if (unassigned.isNotEmpty) ...[
          const Divider(height: 20),
          Text(
              s.kotFallbackPrinters.isEmpty
                  ? 'Not assigned: ${unassigned.join(' · ')}. No counter or KOT printer is set up, so these will not print.'
                  : 'Not assigned: ${unassigned.join(' · ')}. These print on ${_fallbackName(s)} until you pick one above.',
              style: ts(13, c: C.amberInk, h: 1.4)),
        ],
      ]),
    );
  }
}
