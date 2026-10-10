import '../plain_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../store.dart';
import '../sync/bill_sync_api.dart';
import '../theme.dart';
import '../updater.dart';
import '../widgets/common.dart';
import 'captains_screen.dart';
import 'kot_groups_screen.dart';
import 'meal_periods_panel.dart';
import 'menu_editor_screen.dart';
import 'payment_qr_panel.dart';
import 'print_layout_screen.dart';
import 'printers_screen.dart';
import 'settled_bills_screen.dart';

enum _Sec {
  connection('Connection', Icons.link),
  menu('Menu & sync', Icons.sync),
  menuEdit('Menu items', Icons.restaurant_menu),
  mealTimes('Meal times', Icons.schedule),
  bills('Settled bills', Icons.receipt_long_outlined),
  printers('Printers', Icons.print_outlined),
  captains('Captains', Icons.phone_android),
  kot('KOT groups', Icons.restaurant_outlined),
  layout('Print layout', Icons.description_outlined),
  payQr('Payment QR', Icons.qr_code_2),
  web('Web ordering', Icons.language),
  about('App & updates', Icons.system_update_alt);

  final String title;
  final IconData icon;
  const _Sec(this.title, this.icon);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url, _key, _outlet, _webBase, _webTable;
  _Sec _sec = _Sec.connection;
  // Narrow screens show the section list first, then one section at a time.
  bool _showDetail = false;
  bool _webBusy = false;

  @override
  void initState() {
    super.initState();
    final s = StoreScope.read(context);
    _url = TextEditingController(text: s.backofficeUrl);
    _key = TextEditingController(text: s.backofficeKey);
    _outlet = TextEditingController(text: s.backofficeOutletCode);
    _webBase = TextEditingController(text: s.webMenuBaseUrl);
    _webTable = TextEditingController();
    s.refreshWebMenuEnabled();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _outlet.dispose();
    _webBase.dispose();
    _webTable.dispose();
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
      toast(context, 'Sync failed · ${s.lastSyncError ?? plainError(e)}', error: true);
    }
  }

  // ---------- frame: status strip, section list, detail pane ----------

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 820;
          final inDetail = wide || _showDetail;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                RoundIcon(Icons.arrow_back,
                    tooltip: 'Back',
                    onTap: () => !wide && _showDetail ? setState(() => _showDetail = false) : Navigator.of(context).maybePop()),
                const SizedBox(width: 14),
                Text(!wide && _showDetail ? _sec.title : 'Settings', style: ts(22, w: w5)),
              ]),
              const SizedBox(height: 14),
              if (!(!wide && _showDetail)) ...[_statusStrip(s), const SizedBox(height: 14)],
              Expanded(
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 250, child: SingleChildScrollView(child: _sectionList(s))),
                        const SizedBox(width: 18),
                        Expanded(child: _detail(s)),
                      ])
                    : (inDetail ? _detail(s) : SingleChildScrollView(child: _sectionList(s))),
              ),
            ]),
          );
        }),
      ),
    );
  }

  void _open(_Sec sec) => setState(() {
        _sec = sec;
        _showDetail = true;
      });

  /// One-glance health: tap a chip to jump to the section that fixes it.
  Widget _statusStrip(Store s) {
    final bills = s.settledBills;
    final failed = bills.where((o) => s.billSyncStatus[o.id]?.state == BillSyncState.failed).length;
    final syncing = bills.where((o) => s.billSyncStatus[o.id]?.state == BillSyncState.pending).length;
    final unrouted = s.kotGroups.where((g) => !s.isRouted(g.id)).length;
    final last = s.lastMenuSync;
    Widget chip(String text, Color dot, Color bg, Color fg, _Sec to) => GestureDetector(
          onTap: () => _open(to),
          child: Pill(text, bg: bg, fg: fg, size: 13, leading: Dot(color: dot, size: 8)),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      s.isOnline
          ? chip('Online', C.green, C.greenTint, C.greenInk, _Sec.connection)
          : chip('Offline', C.red, C.redTint, C.redInk, _Sec.connection),
      last == null
          ? chip('Menu never synced', C.amber, C.amberTint, C.amberInk, _Sec.menu)
          : chip('Menu synced ${elapsed(last)} ago', C.green, C.soft, C.ink, _Sec.menu),
      if (failed > 0)
        chip('$failed bill${failed == 1 ? '' : 's'} failed to sync', C.red, C.redTint, C.redInk, _Sec.bills)
      else if (syncing > 0)
        chip('$syncing bill${syncing == 1 ? '' : 's'} syncing', C.amber, C.amberTint, C.amberInk, _Sec.bills)
      else
        chip('Bills synced', C.green, C.soft, C.ink, _Sec.bills),
      s.printers.isEmpty
          ? chip('No printers', C.amber, C.amberTint, C.amberInk, _Sec.printers)
          : unrouted > 0
              ? chip('$unrouted KOT group${unrouted == 1 ? '' : 's'} without a printer', C.amber, C.amberTint, C.amberInk, _Sec.kot)
              : chip('${s.printers.length} printer${s.printers.length == 1 ? '' : 's'}', C.green, C.soft, C.ink, _Sec.printers),
      chip('${s.connectedCaptains.length}/${s.captainDevices.length} captains connected', s.connectedCaptains.isEmpty ? C.faint : C.green,
          C.soft, C.ink, _Sec.captains),
      if (s.webMenuEnabled == true)
        chip(s.webOrders.isEmpty ? 'Web menu on' : '${s.webOrders.length} web order${s.webOrders.length == 1 ? '' : 's'} waiting', C.blue,
            s.webOrders.isEmpty ? C.soft : C.skyTint, s.webOrders.isEmpty ? C.ink : C.skyInk, _Sec.web),
    ]);
  }

  Widget _sectionList(Store s) {
    String? badge(_Sec sec) {
      switch (sec) {
        case _Sec.bills:
          final n = s.settledBills.where((o) => s.billSyncStatus[o.id]?.state == BillSyncState.failed).length;
          return n > 0 ? '$n' : null;
        case _Sec.web:
          return s.webOrders.isEmpty ? null : '${s.webOrders.length}';
        default:
          return null;
      }
    }

    return Column(children: [
      for (final sec in _Sec.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: _sec == sec ? C.ink : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(sec),
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _sec == sec ? C.ink : C.line)),
                child: Row(children: [
                  Icon(sec.icon, size: 22, color: _sec == sec ? Colors.white : C.ink2),
                  const SizedBox(width: 12),
                  Expanded(child: Text(sec.title, style: ts(15, w: w5, c: _sec == sec ? Colors.white : C.ink))),
                  if (badge(sec) != null) Pill(badge(sec)!, bg: C.red, fg: Colors.white, size: 12),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _detail(Store s) {
    final children = switch (_sec) {
      _Sec.connection => [_connectionPanel(s)],
      _Sec.menu => [_syncPanel(s), _overviewPanel(s)],
      _Sec.menuEdit => [_menuEditPanel(s)],
      _Sec.mealTimes => [const MealPeriodsPanel()],
      _Sec.bills => [_billSyncPanel(s)],
      _Sec.printers => [_printersPanel(s)],
      _Sec.captains => [_captainsPanel(s)],
      _Sec.kot => [_kotGroupsPanel(s)],
      _Sec.layout => [_printLayoutPanel(s)],
      _Sec.payQr => [const PaymentQrPanel()],
      _Sec.web => [_webPanel(s)],
      _Sec.about => [const UpdatePanel()],
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 16), c],
        ]),
      ),
    );
  }

  // ---------- web ordering ----------

  Future<void> _toggleWeb(Store s, bool on) async {
    setState(() => _webBusy = true);
    try {
      await s.setWebMenuEnabled(on);
      if (mounted) toast(context, on ? 'Web ordering is on' : 'Web ordering is off');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _webBusy = false);
    }
  }

  Widget _webPanel(Store s) {
    final link = s.webMenuLink(tableLabel: _webTable.text);
    final canManage = s.can('settings.manage');
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Web ordering', style: ts(17, w: w5)),
        const SizedBox(height: 4),
        Text('Guests open a link, see the items marked "show on web", and order with their name and mobile number. '
            'Each order waits here for you to accept it.',
            style: ts(13, c: C.muted, h: 1.4)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Accept web orders', style: ts(15, w: w5)),
              Text(
                  s.webMenuEnabled == null
                      ? 'Checking…'
                      : s.webMenuEnabled!
                          ? 'The public menu is live'
                          : 'The public menu shows "not available"',
                  style: ts(12, c: C.muted)),
            ]),
          ),
          Toggle(
              value: s.webMenuEnabled ?? false,
              onChanged: (!canManage || _webBusy || s.webMenuEnabled == null) ? null : (v) => _toggleWeb(s, v)),
        ]),
        if (!canManage) ...[
          const SizedBox(height: 6),
          Text('Your role cannot change this.', style: ts(12, c: C.muted)),
        ],
        if (s.webOrders.isNotEmpty) ...[
          const SizedBox(height: 12),
          Pill('${s.webOrders.length} waiting on the counter screen', bg: C.skyTint, fg: C.skyInk),
        ],
        const SizedBox(height: 20),
        const Label('Where the menu page is hosted'),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _webBase,
                  keyboardType: TextInputType.url,
                  style: ts(14),
                  decoration: const InputDecoration(hintText: 'https://menu.yourdomain.com'))),
          const SizedBox(width: 10),
          Btn.outline('Save', onTap: () {
            s.setWebMenuBaseUrl(_webBase.text);
            toast(context, 'Menu address saved');
          }),
        ]),
        const SizedBox(height: 18),
        if (link.isEmpty)
          Text('Enter the address above to get the link and QR code.', style: ts(13, c: C.muted))
        else ...[
          const Label('Table number (optional, for a table QR)'),
          const SizedBox(height: 6),
          TextField(
              controller: _webTable,
              style: ts(14),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'e.g. 12')),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
              child: QrImageView(data: link, size: 170, backgroundColor: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(link, style: ts(13, c: C.ink2)),
                const SizedBox(height: 12),
                Btn.outline('Copy link', icon: Icons.copy, onTap: () {
                  Clipboard.setData(ClipboardData(text: link));
                  toast(context, 'Link copied');
                }),
              ]),
            ),
          ]),
        ],
      ]),
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
        Row(children: [
          Dot(color: s.isOnline ? C.green : C.faint, size: 8),
          const SizedBox(width: 6),
          Text(s.isOnline ? 'Online' : 'Offline', style: ts(12, w: w5, c: s.isOnline ? C.greenInk : C.muted)),
          if (s.isOnline && s.autoSyncEnabled) ...[
            const SizedBox(width: 6),
            Text('· syncs automatically in the background', style: ts(12, c: C.muted)),
          ],
          const Spacer(),
          Text('Auto-sync', style: ts(12, c: C.muted)),
          const SizedBox(width: 8),
          Toggle(value: s.autoSyncEnabled, scale: .72, onChanged: (v) => s.setAutoSync(v)),
        ]),
        const SizedBox(height: 14),
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

  Widget _billSyncPanel(Store s) {
    final bills = s.settledBills;
    final failed = bills.where((o) => s.billSyncStatus[o.id]?.state == BillSyncState.failed).length;
    final pending = bills.where((o) => s.billSyncStatus[o.id]?.state != BillSyncState.synced && s.billSyncStatus[o.id]?.state != BillSyncState.failed).length;
    return Panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Settled bills', style: ts(17, w: w5)),
            const SizedBox(height: 4),
            Text('Each settled bill syncs to Supabase in the background.', style: ts(13, c: C.muted, h: 1.4)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Pill('${bills.length} settled', bg: C.soft),
              if (pending > 0) Pill('$pending syncing', bg: C.amberTint, fg: C.amberInk),
              if (failed > 0) Pill('$failed failed', bg: C.redTint, fg: C.redInk),
            ]),
          ]),
        ),
        Btn.outline('View',
            icon: Icons.chevron_right,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettledBillsScreen()))),
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

  Widget _captainsPanel(Store s) => Panel(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Captains', style: ts(17, w: w5)),
              const SizedBox(height: 4),
              Text('Pair captain phones to take orders over the restaurant Wi-Fi, even without internet.',
                  style: ts(13, c: C.muted, h: 1.4)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pill('${s.captainDevices.length} paired', bg: C.soft),
                Pill('${s.connectedCaptains.length} connected',
                    bg: s.connectedCaptains.isEmpty ? C.soft : C.greenTint, fg: s.connectedCaptains.isEmpty ? C.ink : C.greenInk),
                if (!s.linkRunning) const Pill('Not accepting', bg: C.redTint, fg: C.redInk),
              ]),
            ]),
          ),
          Btn.outline('Manage',
              icon: Icons.chevron_right,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CaptainsScreen()))),
        ]),
      );

  Widget _kotGroupsPanel(Store s) {
    final unrouted = s.kotGroups.where((g) => !s.isRouted(g.id)).length;
    return Panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('KOT groups', style: ts(17, w: w5)),
            const SizedBox(height: 4),
            Text('Kitchen sections from the menu, and which printer each one prints on.', style: ts(13, c: C.muted, h: 1.4)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Pill('${s.kotGroups.length} groups', bg: C.soft),
              if (unrouted > 0) Pill('$unrouted without a printer', bg: C.amberTint, fg: C.amberInk),
            ]),
          ]),
        ),
        Btn.outline('Manage',
            icon: Icons.chevron_right,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KotGroupsScreen()))),
      ]),
    );
  }

  Widget _menuEditPanel(Store s) => Panel(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Menu items', style: ts(17, w: w5)),
              const SizedBox(height: 4),
              Text('See every item, change names, prices, sizes, type and KOT group. Edits are saved to this outlet in Supabase.',
                  style: ts(13, c: C.muted, h: 1.4)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pill('${s.menu.length} items', bg: C.soft),
                Pill('${s.categories.length} categories', bg: C.soft),
                if (!s.canEditMenu) const Pill('View only', bg: C.amberTint, fg: C.amberInk),
              ]),
            ]),
          ),
          Btn.outline('Open',
              icon: Icons.chevron_right,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MenuEditorScreen()))),
        ]),
      );

  Widget _printLayoutPanel(Store s) {
    final l = s.printLayout;
    return Panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Print layout', style: ts(17, w: w5)),
            const SizedBox(height: 4),
            Text('What the invoice and KOT show, with a live preview.', style: ts(13, c: C.muted, h: 1.4)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Pill('${l.paperMm} mm paper', bg: C.soft),
              Pill('Invoice × ${l.billCopies}', bg: C.soft),
              Pill('KOT × ${l.kotCopies}', bg: C.soft),
            ]),
          ]),
        ),
        Btn.outline('Edit',
            icon: Icons.chevron_right,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintLayoutScreen()))),
      ]),
    );
  }

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
