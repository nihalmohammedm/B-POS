import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../plain_error.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings → Tables: the outlet's tables, grouped by floor. Everything here is saved to Supabase
/// (bpos.tables), so every till shows the same tables and floor plan. Dragging tables on the plan
/// itself is done on the Tables screen (long-press).
class TablesPanel extends StatelessWidget {
  const TablesPanel({super.key});

  Future<void> _edit(BuildContext context, Store s, TableModel? t) async {
    final res = await showPanelDialog<_TableForm>(context, maxWidth: 480, builder: (ctx) => _TableEditor(store: s, table: t));
    if (res == null || !context.mounted) return;
    try {
      if (t == null) {
        await s.addTable(res.number, res.seats, res.floor, w: res.w, h: res.h);
      } else {
        await s.updateTable(t, seats: res.seats, floor: res.floor, w: res.w, h: res.h);
      }
      if (context.mounted) toast(context, t == null ? 'Table ${res.number} added' : 'Table ${t.id} saved');
    } catch (e) {
      if (context.mounted) toast(context, plainError(e), error: true);
    }
  }

  Future<void> _sync(BuildContext context, Store s) async {
    try {
      await s.syncMenu();
      if (context.mounted) toast(context, '${s.tables.length} table${s.tables.length == 1 ? '' : 's'} synced');
    } catch (e) {
      if (context.mounted) toast(context, plainError(e), error: true);
    }
  }

  Future<void> _remove(BuildContext context, Store s, TableModel t) async {
    final ok = await confirmDialog(context,
        title: 'Remove table ${t.id}?',
        body: 'It disappears from the plan on every till. Past orders and bills for it are kept.',
        ok: 'Remove',
        okColor: C.red);
    if (!ok || !context.mounted) return;
    try {
      await s.removeTable(t);
      if (context.mounted) toast(context, 'Table ${t.id} removed');
    } catch (e) {
      if (context.mounted) toast(context, plainError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final canManage = s.can('settings.manage');
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Tables', style: ts(17, w: w5))),
          Btn.outline(s.syncingMenu ? 'Syncing…' : 'Sync tables',
              icon: Icons.sync, height: 40, onTap: s.syncingMenu ? null : () => _sync(context, s)),
          if (canManage) ...[
            const SizedBox(width: 10),
            Btn('Add table', icon: Icons.add, height: 40, onTap: () => _edit(context, s, null)),
          ],
        ]),
        const SizedBox(height: 4),
        Text('${s.tables.length} table${s.tables.length == 1 ? '' : 's'} · saved to your account, shared by every till. '
            'To move tables on the plan, long-press the Tables screen.',
            style: ts(13, c: C.muted, h: 1.4)),
        if (!canManage) ...[
          const SizedBox(height: 6),
          Text('Your role cannot change tables.', style: ts(12, c: C.muted)),
        ],
        if (s.tableSyncError != null) ...[
          const SizedBox(height: 8),
          Text('Layout not uploaded yet: ${s.tableSyncError}', style: ts(13, c: C.redInk, h: 1.4)),
        ],
        const SizedBox(height: 14),
        if (s.tables.isEmpty) Text('No tables yet.', style: ts(13, c: C.muted)),
        for (final f in s.floors) ...[
          Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(f.toUpperCase(), style: ts(12, w: w6, c: C.muted))),
          for (final t in s.tablesOn(f))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
              child: Row(children: [
                Expanded(
                    child: Text('Table ${t.id}  ·  ${t.seats} seats${t.parties.isEmpty ? '' : '  ·  in use'}',
                        style: ts(15, w: w5))),
                if (canManage) ...[
                  RoundIcon(Icons.edit_outlined, size: 40, tooltip: 'Edit', onTap: () => _edit(context, s, t)),
                  const SizedBox(width: 6),
                  RoundIcon(Icons.delete_outline, size: 40, fg: C.red, tooltip: 'Remove', onTap: () => _remove(context, s, t)),
                ],
              ]),
            ),
        ],
      ]),
    );
  }
}

class _TableForm {
  final String number, floor;
  final int seats, w, h;
  const _TableForm(this.number, this.seats, this.floor, this.w, this.h);
}

class _TableEditor extends StatefulWidget {
  final Store store;
  final TableModel? table;
  const _TableEditor({required this.store, this.table});
  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  late final numberC = TextEditingController(text: widget.table?.id ?? '');
  late final seatsC = TextEditingController(text: '${widget.table?.seats ?? 4}');
  late final floorC = TextEditingController(text: widget.table?.floor ?? (widget.store.floors.isEmpty ? 'Tables' : widget.store.floors.first));
  late int w = widget.table?.w ?? 1, h = widget.table?.h ?? 1;

  @override
  void dispose() {
    numberC.dispose();
    seatsC.dispose();
    floorC.dispose();
    super.dispose();
  }

  Widget _size(String label, int v, void Function(int) set) => Expanded(
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
          child: Row(children: [
            const SizedBox(width: 6),
            Text(label, style: ts(13, c: C.muted)),
            const Spacer(),
            RoundIcon(Icons.remove, size: 36, onTap: v > 1 ? () => setState(() => set(v - 1)) : null),
            SizedBox(width: 28, child: Center(child: Text('$v', style: ts(15, w: w5)))),
            RoundIcon(Icons.add, size: 36, onTap: v < 6 ? () => setState(() => set(v + 1)) : null),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final editing = widget.table != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(editing ? 'Edit table ${widget.table!.id}' : 'Add table', style: ts(20, w: w5)),
        const SizedBox(height: 14),
        TextField(
            controller: numberC,
            enabled: !editing,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: 'Table number (e.g. 12)', helperText: editing ? 'The number cannot be changed' : null)),
        const SizedBox(height: 12),
        TextField(
            controller: seatsC,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: 'Seats')),
        const SizedBox(height: 12),
        TextField(controller: floorC, decoration: const InputDecoration(hintText: 'Floor / section (e.g. Ground, AC)')),
        if (s.floors.length > 1 || (s.floors.length == 1 && s.floors.first != floorC.text.trim())) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in s.floors)
              ActionChip(label: Text(f), onPressed: () => setState(() => floorC.text = f)),
          ]),
        ],
        const SizedBox(height: 14),
        Text('Size on the plan', style: ts(14, w: w5)),
        const SizedBox(height: 8),
        Row(children: [_size('Wide', w, (v) => w = v), const SizedBox(width: 10), _size('Tall', h, (v) => h = v)]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Btn.outline('Cancel', expand: true, onTap: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(
              child: Btn('Save', expand: true, onTap: () {
            final number = numberC.text.trim();
            final seats = int.tryParse(seatsC.text.trim()) ?? 0;
            if (number.isEmpty) return toast(context, 'Enter a table number', error: true);
            if (seats < 1) return toast(context, 'Seats must be at least 1', error: true);
            Navigator.pop(context, _TableForm(number, seats, floorC.text.trim(), w, h));
          })),
        ]),
      ]),
    );
  }
}
