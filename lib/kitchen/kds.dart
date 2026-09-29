import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../captain/pair_screen.dart';
import '../link/captain_link.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'bell.dart';

/// Kitchen display app root: pair with the main POS once, then the tickets.
class KitchenGate extends StatelessWidget {
  const KitchenGate({super.key});
  @override
  Widget build(BuildContext context) {
    final link = CaptainLinkScope.maybeOf(context)!;
    if (link.state == LinkState.unpaired) return const PairScreen();
    return const KdsScreen();
  }
}

/// What this display shows and how it alerts, kept on the device: each
/// station's phone picks its own KOT groups.
class KdsPrefs {
  static const _groupsKey = 'kds_groups', _soundKey = 'kds_sound';

  /// KOT group ids to show ([Store.noGroupKey] = items with no group).
  /// Null: every group, including ones added to the menu later.
  Set<String>? groups;
  bool sound = true;

  bool shows(String? group) => groups == null || groups!.contains(group ?? Store.noGroupKey);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final g = p.getString(_groupsKey);
      groups = g == null ? null : (jsonDecode(g) as List).cast<String>().toSet();
      sound = p.getBool(_soundKey) ?? true;
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      groups == null ? await p.remove(_groupsKey) : await p.setString(_groupsKey, jsonEncode(groups!.toList()));
      await p.setBool(_soundKey, sound);
    } catch (_) {}
  }
}

class KdsScreen extends StatefulWidget {
  const KdsScreen({super.key});
  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  static const warnMin = 10, lateMin = 15;

  final prefs = KdsPrefs();
  final bell = KitchenBell();
  bool readyTab = false;
  Timer? _tick;
  CaptainLink? _link;
  DateTime? _lastSnap;

  /// KOT numbers already on screen, so only new ones ring. Null until the
  /// first snapshot after launch: what's already there then doesn't ring.
  Set<int>? _seen;

  /// Cancellation tickets the cook has acknowledged on this display.
  final _dismissed = <int>{};

  /// KOTs with a request in flight to the POS, so a double tap sends once.
  final _busy = <int>{};

  @override
  void initState() {
    super.initState();
    prefs.load().then((_) {
      if (mounted) setState(() => _seen = _seen == null ? null : _visibleNos());
    });
    WakelockPlus.enable().catchError((_) {}); // a kitchen screen must not go dark
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l = CaptainLinkScope.read(context);
    if (l != _link) {
      _link?.removeListener(_onLink);
      _link = l?..addListener(_onLink);
    }
  }

  @override
  void dispose() {
    _link?.removeListener(_onLink);
    _tick?.cancel();
    bell.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Store get _s => StoreScope.read(context);

  List<Kot> _visible() => _s.kitchenKots.where((k) => prefs.shows(k.group)).toList();
  Set<int> _visibleNos() => {for (final k in _visible()) k.no};

  /// Each snapshot from the POS: ring for tickets this display hasn't seen.
  void _onLink() {
    final at = _link?.lastSnapshotAt;
    if (at == null || at == _lastSnap) return;
    _lastSnap = at;
    final now = _visible();
    final seen = _seen;
    _seen = {for (final k in now) k.no};
    if (seen == null || !prefs.sound) return;
    final fresh = now.where((k) => !seen.contains(k.no)).toList();
    if (fresh.isEmpty) return;
    bell.ring(times: fresh.any((k) => k.kind != KotKind.order) ? 2 : 1);
  }

  Future<void> _send(Kot k, String cmd, [Map<String, dynamic> extra = const {}]) async {
    final link = _link;
    if (link == null || !_busy.add(k.no)) return;
    setState(() {});
    try {
      await link.call(cmd, {'kot': k.no, ...extra});
    } on LinkError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      _busy.remove(k.no);
      if (mounted) setState(() {});
    }
  }

  String _mmss(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final link = CaptainLinkScope.maybeOf(context)!;
    final all = s.kitchenKots.where((k) => prefs.shows(k.group)).toList()..sort((a, b) => a.at.compareTo(b.at));
    final cancels = all.where((k) => k.kind == KotKind.cancel && !_dismissed.contains(k.no)).toList();
    final work = all.where((k) => k.kind != KotKind.cancel && k.stage != KotStage.done).toList();
    final active = work.where((k) => k.stage != KotStage.ready).toList();
    final ready = work.where((k) => k.stage == KotStage.ready).toList();
    final shown = readyTab ? ready : [...cancels, ...active];
    final now = DateTime.now();
    final lateN = active.where((k) => now.difference(k.at).inMinutes >= lateMin).length;

    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!link.online) _offline(link),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(link.captainName.isEmpty ? 'Kitchen' : link.captainName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(20, w: w7)),
                  Text(_groupsLabel(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: C.muted)),
                ]),
              ),
              if (lateN > 0) ...[
                Pill('Late $lateN', bg: C.red, fg: Colors.white, size: 13, weight: w7),
                const SizedBox(width: 8),
              ],
              RoundIcon(prefs.sound ? Icons.notifications_active : Icons.notifications_off,
                  fg: prefs.sound ? C.ink : C.redInk,
                  tooltip: prefs.sound ? 'Bell on' : 'Bell off',
                  onTap: () => setState(() {
                        prefs.sound = !prefs.sound;
                        prefs.save();
                        if (prefs.sound) bell.ring();
                      })),
              const SizedBox(width: 8),
              RoundIcon(Icons.tune, tooltip: 'Sections & settings', onTap: () => _settings(context)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Seg<bool>(
              height: 48,
              fontSize: 16,
              expand: true,
              items: [(false, 'Cooking ${active.length + cancels.length}'), (true, 'Ready ${ready.length}')],
              value: readyTab,
              onChanged: (v) => setState(() => readyTab = v),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.soup_kitchen_outlined, size: 48, color: C.faint),
                    const SizedBox(height: 10),
                    Text(readyTab ? 'Nothing waiting for pickup' : 'No tickets', style: ts(17, w: w6)),
                    const SizedBox(height: 4),
                    Text('New KOTs ring the bell and appear here', style: ts(14, c: C.muted)),
                  ]))
                : LayoutBuilder(builder: (c, cons) {
                    // One column on a phone, more on a tablet.
                    final cols = math.max(1, (cons.maxWidth / 340).floor());
                    final w = (cons.maxWidth - 32 - 12 * (cols - 1)) / cols;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Wrap(spacing: 12, runSpacing: 12, children: [
                        for (final k in shown)
                          SizedBox(width: w, child: k.kind == KotKind.cancel ? _cancelTicket(s, k) : _ticket(s, k)),
                      ]),
                    );
                  }),
          ),
        ]),
      ),
    );
  }

  Widget _offline(CaptainLink link) => Material(
        color: link.state == LinkState.connecting ? C.amber : C.red,
        child: InkWell(
          onTap: link.reconnect,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    link.state == LinkState.connecting
                        ? 'Connecting to the POS…'
                        : 'Not connected to the POS · new KOTs won\'t arrive · retrying',
                    style: ts(14, w: w6, c: Colors.white)),
              ),
              Text('Retry', style: ts(14, w: w7, c: Colors.white, deco: TextDecoration.underline)),
            ]),
          ),
        ),
      );

  String _groupsLabel(Store s) {
    final g = prefs.groups;
    if (g == null) return 'All sections';
    final names = [
      for (final x in s.kotGroups)
        if (g.contains(x.id)) x.name,
      if (g.contains(Store.noGroupKey)) 'No section',
    ];
    return names.isEmpty ? 'No sections picked' : names.join(' · ');
  }

  (String, String) _where(Store s, Order o) => o.type == OrderType.dineIn
      ? ('Table ${s.labelOf(o)}', '${o.pax} pax · ${o.server}')
      : (o.customer.isEmpty ? o.token : o.customer, '${o.type.label} · ${o.token}');

  Widget _ticket(Store s, Kot k) {
    final o = s.orderById(k.orderId)!;
    final el = DateTime.now().difference(k.at);
    final stage = k.stage;
    final lvl = stage == KotStage.ready ? 3 : el.inMinutes >= lateMin ? 2 : el.inMinutes >= warnMin ? 1 : 0;
    const heads = <(Color, Color)>[
      (C.ink, Colors.white),
      (Color(0xFFF59E0B), Color(0xFF1A1A1A)),
      (C.red, Colors.white),
      (C.green, Colors.white),
    ];
    final (hb, hf) = heads[lvl];
    final (where, meta) = _where(s, o);
    final isNew = stage == KotStage.fresh;
    final busy = _busy.contains(k.no);
    final (action, cmd, actionBg) = switch (stage) {
      KotStage.fresh => ('Start', 'kdsStart', C.blueDeep),
      KotStage.preparing => ('Mark ready', 'kdsReady', C.green),
      _ => (o.type == OrderType.dineIn ? 'Served' : 'Handed over', 'kdsBump', C.ink),
    };
    final group = s.kotGroup(k.group)?.name;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isNew ? C.amber : C.line, width: isNew ? 3 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: hb,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (isNew) ...[
                Pill('NEW', bg: C.amber, fg: C.ink, size: 12, weight: w7),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(22, w: w7, c: hf))),
              Text(_mmss(el), style: ts(20, w: w7, c: hf).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Text('#${k.no}${group == null ? '' : ' · $group'}', style: ts(13, w: w7, c: hf)),
              if (k.batch.length > 1) Text('  ${k.batch.indexOf(k.no) + 1}/${k.batch.length}', style: ts(13, w: w6, c: hf)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(meta,
                      textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, c: hf))),
            ]),
          ]),
        ),
        // An edited item: what to stop making, then its replacement below.
        for (final v in k.voided) _voidedLine(v),
        if (k.voided.isNotEmpty && k.reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Text('Reason: ${k.reason}', style: ts(13, c: C.redInk)),
          ),
        for (var i = 0; i < k.lines.length; i++)
          if (k.lines[i].activeQty > 0) _line(k, i),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(children: [
            if (stage == KotStage.ready) ...[
              Expanded(child: Btn.outline('Recall', height: 56, fontSize: 16, onTap: busy ? null : () => _send(k, 'kdsRecall'))),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: Btn(busy ? '…' : action,
                  height: 56, fontSize: 17, bg: actionBg, expand: true, onTap: busy ? null : () => _send(k, cmd)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _line(Kot k, int i) {
    final l = k.lines[i];
    final done = l.state.index >= LineState.ready.index;
    final fg = done ? const Color(0xFFA1A1AA) : C.ink;
    return InkWell(
      onTap: _busy.contains(k.no) ? null : () => _send(k, 'kdsToggle', {'line': i}),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.soft))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 44, child: Text('${l.activeQty}×', style: ts(20, w: w7, c: fg))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.item.name, style: ts(19, w: w6, c: fg, deco: done ? TextDecoration.lineThrough : null)),
              for (final m in l.mods) Text(m, style: ts(15, w: w5, c: done ? fg : C.ink2)),
              if (l.note.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                  child: Text(l.note, style: ts(15, w: w6, c: const Color(0xFF92400E))),
                ),
            ]),
          ),
          Icon(done ? Icons.check_box : Icons.check_box_outline_blank, size: 28, color: done ? C.green : C.faint),
        ]),
      ),
    );
  }

  Widget _voidedLine(OrderLine v) => Container(
        color: C.redTint,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 44, child: Text('${v.qty}×', style: ts(20, w: w7, c: C.redInk))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.item.name, style: ts(19, w: w6, c: C.redInk, deco: TextDecoration.lineThrough)),
              if (v.optText.isNotEmpty) Text(v.optText, style: ts(15, c: C.redInk)),
            ]),
          ),
          Text('STOP', style: ts(14, w: w7, c: C.redInk)),
        ]),
      );

  /// A cancellation: nothing to cook, just "stop making these". Stays until
  /// the cook taps OK (or [Store.cancelShowFor] passes).
  Widget _cancelTicket(Store s, Kot k) {
    final o = s.orderById(k.orderId)!;
    final (where, _) = _where(s, o);
    final group = s.kotGroup(k.group)?.name;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.red, width: 3)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: C.red,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(children: [
            const Icon(Icons.cancel, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text('CANCELLED · $where',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(19, w: w7, c: Colors.white))),
            Text('#${k.no}${group == null ? '' : ' · $group'}', style: ts(13, w: w7, c: Colors.white)),
          ]),
        ),
        for (final v in k.voided) _voidedLine(v),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 12, 12),
          child: Row(children: [
            Expanded(
              child: Text(
                  [if (k.reason.isNotEmpty) k.reason, if (k.by.isNotEmpty) 'by ${k.by}', '${elapsed(k.at)} ago'].join(' · '),
                  style: ts(14, c: C.ink2)),
            ),
            Btn('OK', height: 52, fontSize: 17, bg: C.ink, onTap: () => setState(() => _dismissed.add(k.no))),
          ]),
        ),
      ]),
    );
  }

  // ---------- settings ----------

  Future<void> _settings(BuildContext context) => showSheet(context, (ctx) {
        return StatefulBuilder(builder: (ctx, set) {
          final s = StoreScope.of(ctx);
          final ids = [for (final g in s.kotGroups) g.id, Store.noGroupKey];
          final picked = prefs.groups ?? ids.toSet();

          void apply(Set<String>? g) {
            set(() => prefs.groups = g);
            setState(() {
              // Tickets that come into view by changing sections aren't new: don't ring for them.
              _seen = _seen == null ? null : {..._seen!, ..._visibleNos()};
            });
            prefs.save();
          }

          void toggle(String id) {
            final next = {...picked};
            next.contains(id) ? next.remove(id) : next.add(id);
            if (next.isEmpty) return toast(ctx, 'Pick at least one section', error: true);
            // Everything picked by hand means "all", so new sections show up too.
            apply(ids.every(next.contains) ? null : next);
          }

          Widget row(String id, String name) {
            final on = picked.contains(id);
            return InkWell(
              onTap: () => toggle(id),
              child: SizedBox(
                height: 56,
                child: Row(children: [
                  Icon(on ? Icons.check_box : Icons.check_box_outline_blank, size: 28, color: on ? C.blueDeep : C.faint),
                  const SizedBox(width: 14),
                  Expanded(child: Text(name, style: ts(17, w: w5))),
                ]),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('KOT sections on this display', style: ts(20, w: w6)),
              const SizedBox(height: 4),
              Text('Only tickets for these sections show and ring here. Each kitchen phone picks its own.',
                  style: ts(14, c: C.muted, h: 1.35)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => apply(null),
                child: SizedBox(
                  height: 56,
                  child: Row(children: [
                    Icon(prefs.groups == null ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 28, color: prefs.groups == null ? C.blueDeep : C.faint),
                    const SizedBox(width: 14),
                    Expanded(child: Text('All sections', style: ts(17, w: w6))),
                  ]),
                ),
              ),
              const Divider(height: 1),
              if (s.kotGroups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('The POS has no KOT groups set up yet', style: ts(14, c: C.muted)),
                ),
              for (final g in s.kotGroups) row(g.id, g.name),
              row(Store.noGroupKey, 'Items with no section'),
              const SizedBox(height: 18),
              Text('Bell', style: ts(20, w: w6)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Ring when a new KOT or cancellation arrives', style: ts(15))),
                Toggle(
                    value: prefs.sound,
                    onChanged: (v) {
                      set(() => prefs.sound = v);
                      setState(() {});
                      prefs.save();
                    }),
              ]),
              const SizedBox(height: 10),
              Btn.outline('Test bell', icon: Icons.notifications_active, expand: true, onTap: () => bell.ring()),
              const SizedBox(height: 6),
              Text('The bell plays at alarm volume · turn the phone\'s alarm volume up in a noisy kitchen.',
                  style: ts(13, c: C.muted, h: 1.35)),
              const SizedBox(height: 18),
              Btn.outline('Connection to the POS', icon: Icons.wifi, expand: true, onTap: () => showConnectionSheet(ctx)),
            ]),
          );
        });
      });
}
