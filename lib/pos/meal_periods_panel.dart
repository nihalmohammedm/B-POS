import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings → Meal times: Morning / Lunch / Evening / Dinner windows and the
/// categories served in each. The order screen follows the clock and shows only
/// the running period's categories (staff can still switch to "All day").
class MealPeriodsPanel extends StatelessWidget {
  const MealPeriodsPanel({super.key});

  static const _defaults = [
    ('Morning', 6 * 60, 11 * 60),
    ('Lunch', 11 * 60, 15 * 60 + 30),
    ('Evening', 15 * 60 + 30, 19 * 60),
    ('Dinner', 19 * 60, 23 * 60 + 30),
  ];

  Future<void> _edit(BuildContext context, Store s, MealPeriod? p) async {
    final res = await showPanelDialog<MealPeriod>(context,
        maxWidth: 520, builder: (ctx) => _PeriodEditor(store: s, period: p));
    if (res == null) return;
    final list = [...s.mealPeriods];
    final i = list.indexWhere((x) => x.id == res.id);
    i < 0 ? list.add(res) : list[i] = res;
    list.sort((a, b) => a.startMin.compareTo(b.startMin));
    s.setMealPeriods(list);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final now = s.currentPeriod();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Meal times', style: ts(17, w: w5))),
          Btn('Add',
              icon: Icons.add,
              height: 40,
              onTap: () => _edit(context, s, null)),
        ]),
        const SizedBox(height: 4),
        Text(
            'Show Morning, Lunch, Evening and Dinner menus at their own times. Categories not assigned to any period are served all day.',
            style: ts(13, c: C.muted, h: 1.4)),
        const SizedBox(height: 14),
        if (s.mealPeriods.isEmpty)
          Btn.outline('Set up Morning / Lunch / Evening / Dinner',
              expand: true,
              onTap: () => s.setMealPeriods([
                    for (final (i, d) in _defaults.indexed)
                      MealPeriod(
                          id: 'p${DateTime.now().microsecondsSinceEpoch}$i',
                          name: d.$1,
                          startMin: d.$2,
                          endMin: d.$3),
                  ])),
        for (final p in s.mealPeriods)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
                color: p.id == now?.id ? C.skyTint : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.line)),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(p.name, style: ts(15, w: w5)),
                        if (p.id == now?.id) ...[
                          const SizedBox(width: 8),
                          const Pill('NOW',
                              bg: C.blue, fg: Colors.white, size: 10)
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text(p.range, style: ts(13, c: C.ink2)),
                      Text(
                          p.cats.isEmpty
                              ? 'No categories assigned'
                              : p.cats.join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ts(12, c: C.muted)),
                    ]),
              ),
              RoundIcon(Icons.edit_outlined,
                  size: 40, tooltip: 'Edit', onTap: () => _edit(context, s, p)),
              const SizedBox(width: 6),
              RoundIcon(Icons.delete_outline,
                  size: 40,
                  fg: C.red,
                  tooltip: 'Delete',
                  onTap: () => s.setMealPeriods(
                      [...s.mealPeriods]..removeWhere((x) => x.id == p.id))),
            ]),
          ),
      ]),
    );
  }
}

class _PeriodEditor extends StatefulWidget {
  final Store store;
  final MealPeriod? period;
  const _PeriodEditor({required this.store, this.period});
  @override
  State<_PeriodEditor> createState() => _PeriodEditorState();
}

class _PeriodEditorState extends State<_PeriodEditor> {
  late final nameC = TextEditingController(text: widget.period?.name ?? '');
  late int start = widget.period?.startMin ?? 9 * 60,
      end = widget.period?.endMin ?? 12 * 60;
  late final Set<String> cats = {...?widget.period?.cats};

  @override
  void dispose() {
    nameC.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final cur = isStart ? start : end;
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (t == null) return;
    setState(() => isStart
        ? start = t.hour * 60 + t.minute
        : end = t.hour * 60 + t.minute);
  }

  Widget _time(String label, int v, bool isStart) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pick(isStart),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.line)),
            child: Row(children: [
              Text(label, style: ts(13, c: C.muted)),
              const Spacer(),
              Text(MealPeriod.fmt(v), style: ts(15, w: w5)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.period == null ? 'New meal time' : 'Edit meal time',
                style: ts(20, w: w5)),
            const SizedBox(height: 14),
            TextField(
                controller: nameC,
                decoration:
                    const InputDecoration(hintText: 'Name (e.g. Lunch)')),
            const SizedBox(height: 12),
            Row(children: [
              _time('From', start, true),
              const SizedBox(width: 10),
              _time('To', end, false)
            ]),
            if (end <= start)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child:
                      Text('Ends after midnight', style: ts(12, c: C.muted))),
            const SizedBox(height: 16),
            Text('Categories served', style: ts(14, w: w5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in s.categories)
                FilterChip(
                    label: Text(c),
                    selected: cats.contains(c),
                    onSelected: (v) =>
                        setState(() => v ? cats.add(c) : cats.remove(c))),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: Btn.outline('Cancel',
                      expand: true, onTap: () => Navigator.pop(context))),
              const SizedBox(width: 10),
              Expanded(
                  child: Btn('Save', expand: true, onTap: () {
                final name = nameC.text.trim();
                if (name.isEmpty) {
                  toast(context, 'Enter a name', error: true);
                  return;
                }
                Navigator.pop(
                    context,
                    MealPeriod(
                        id: widget.period?.id ??
                            'p${DateTime.now().microsecondsSinceEpoch}',
                        name: name,
                        startMin: start,
                        endMin: end,
                        cats: cats));
              })),
            ]),
          ]),
    );
  }
}
