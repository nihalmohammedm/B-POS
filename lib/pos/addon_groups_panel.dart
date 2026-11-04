import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings → Add-on groups: reusable sets of add-ons (e.g. "Alfaham extras": Chest piece +₹20)
/// that any number of items can use. Items pick them in the menu item editor; changing a group
/// here changes every item that uses it.
class AddonGroupsPanel extends StatelessWidget {
  const AddonGroupsPanel({super.key});

  Future<void> _edit(BuildContext context, Store s, AddonGroup? g) async {
    final res = await showPanelDialog<AddonGroup>(context, maxWidth: 520, builder: (ctx) => _GroupEditor(group: g));
    if (res == null || !context.mounted) return;
    try {
      await s.saveAddonGroup(res);
      if (context.mounted) toast(context, '${res.name} saved');
    } catch (e) {
      if (context.mounted) toast(context, 'Not saved · $e', error: true);
    }
  }

  Future<void> _remove(BuildContext context, Store s, AddonGroup g) async {
    final n = s.itemsUsingGroup(g.id);
    final ok = await confirmDialog(context,
        title: 'Remove ${g.name}?',
        body: n == 0
            ? 'It stops showing as an add-on choice. Past orders keep their prices.'
            : 'It stops showing on $n item${n == 1 ? '' : 's'}. Past orders keep their prices.',
        ok: 'Remove',
        okColor: C.red);
    if (ok != true || !context.mounted) return;
    try {
      await s.removeAddonGroup(g.id);
    } catch (e) {
      if (context.mounted) toast(context, 'Not removed · $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final canEdit = s.canEditMenu;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Add-on groups', style: ts(17, w: w5))),
          if (canEdit) Btn('New group', icon: Icons.add, height: 40, onTap: () => _edit(context, s, null)),
        ]),
        const SizedBox(height: 4),
        Text(
            'Set up extras once, like Chest piece +₹20, and tick the group on every item that offers it. Change a price here and it changes on all of them.',
            style: ts(13, c: C.muted, h: 1.4)),
        if (!canEdit) ...[
          const SizedBox(height: 8),
          const Pill('View only', bg: C.amberTint, fg: C.amberInk),
        ],
        const SizedBox(height: 14),
        if (s.addonGroups.isEmpty) Text('No groups yet.', style: ts(13, c: C.muted)),
        for (final g in s.addonGroups)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.name, style: ts(15, w: w5)),
                  const SizedBox(height: 2),
                  Text(
                      g.addons.isEmpty ? 'No add-ons' : g.addons.map((a) => '${a.name} +₹${a.price.toStringAsFixed(a.price == a.price.roundToDouble() ? 0 : 2)}').join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ts(13, c: C.ink2)),
                  Text('Used on ${s.itemsUsingGroup(g.id)} items', style: ts(12, c: C.muted)),
                ]),
              ),
              if (canEdit) ...[
                RoundIcon(Icons.edit_outlined, size: 40, tooltip: 'Edit', onTap: () => _edit(context, s, g)),
                const SizedBox(width: 6),
                RoundIcon(Icons.delete_outline, size: 40, fg: C.red, tooltip: 'Remove', onTap: () => _remove(context, s, g)),
              ],
            ]),
          ),
      ]),
    );
  }
}

class _Row {
  final String? id;
  final TextEditingController name, price;
  _Row(Addon a)
      : id = a.id,
        name = TextEditingController(text: a.name),
        price = TextEditingController(text: a.price == a.price.roundToDouble() ? a.price.toStringAsFixed(0) : '${a.price}');
  _Row.blank()
      : id = null,
        name = TextEditingController(),
        price = TextEditingController();
  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _GroupEditor extends StatefulWidget {
  final AddonGroup? group;
  const _GroupEditor({this.group});
  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  late final nameC = TextEditingController(text: widget.group?.name ?? '');
  late final rows = [for (final a in widget.group?.addons ?? const <Addon>[]) _Row(a)];

  @override
  void initState() {
    super.initState();
    if (rows.isEmpty) rows.add(_Row.blank());
  }

  @override
  void dispose() {
    nameC.dispose();
    for (final r in rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = nameC.text.trim();
    if (name.isEmpty) {
      toast(context, 'Give the group a name', error: true);
      return;
    }
    final addons = <Addon>[];
    for (final r in rows) {
      final n = r.name.text.trim(), p = double.tryParse(r.price.text.trim());
      if (n.isEmpty && r.price.text.trim().isEmpty) continue; // untouched blank row
      if (n.isEmpty || p == null || p < 0) {
        toast(context, 'Every add-on needs a name and a price', error: true);
        return;
      }
      addons.add(Addon(n, p, id: r.id));
    }
    if (addons.isEmpty) {
      toast(context, 'Add at least one add-on', error: true);
      return;
    }
    Navigator.pop(context, AddonGroup(widget.group?.id ?? '', name, addons));
  }

  @override
  Widget build(BuildContext context) {
    const money = TextInputType.numberWithOptions(decimal: true);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.group == null ? 'New add-on group' : 'Edit add-on group', style: ts(20, w: w5)),
        const SizedBox(height: 14),
        TextField(controller: nameC, decoration: const InputDecoration(hintText: 'Group name (e.g. Alfaham extras)')),
        const SizedBox(height: 14),
        Row(children: [
          const Expanded(child: Label('Add-ons')),
          Btn.outline('Add', icon: Icons.add, height: 34, fontSize: 13, onTap: () => setState(() => rows.add(_Row.blank()))),
        ]),
        for (final (i, r) in rows.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(flex: 3, child: TextField(controller: r.name, style: ts(14), decoration: const InputDecoration(hintText: 'Chest piece'))),
              const SizedBox(width: 10),
              Expanded(
                  flex: 2,
                  child: TextField(
                      controller: r.price,
                      style: ts(14),
                      keyboardType: money,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: const InputDecoration(prefixText: '+ ₹ ', hintText: '0'))),
              IconButton(
                  tooltip: 'Remove add-on',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => rows.removeAt(i).dispose())),
            ]),
          ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Btn.outline('Cancel', expand: true, onTap: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(child: Btn('Save', expand: true, onTap: _save)),
        ]),
      ]),
    );
  }
}
