import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../sync/bill_sync_api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings › Settled bills: every settled order and whether it's made it to
/// Supabase yet (see Store._syncPendingBills). Read-only other than a manual
/// retry on a failed row — the push itself stays silent everywhere else.
class SettledBillsScreen extends StatelessWidget {
  const SettledBillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final bills = s.settledBills;
    final synced = bills.where((o) => s.billSyncStatus[o.id]?.state == BillSyncState.synced).length;
    final failed = bills.where((o) => s.billSyncStatus[o.id]?.state == BillSyncState.failed).length;
    final pending = bills.length - synced - failed;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              RoundIcon(Icons.arrow_back, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Back'),
              const SizedBox(width: 14),
              Expanded(child: Text('Settled bills', style: ts(22, w: w5))),
            ]),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Panel(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Sync to Supabase', style: ts(17, w: w5)),
                          const SizedBox(height: 4),
                          Text('Each settled bill pushes in the background — no action needed unless one fails.',
                              style: ts(13, c: C.muted, h: 1.4)),
                          const SizedBox(height: 14),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            Pill('$synced synced', bg: C.greenTint, fg: C.greenInk),
                            if (pending > 0) Pill('$pending pending', bg: C.amberTint, fg: C.amberInk),
                            if (failed > 0) Pill('$failed failed', bg: C.redTint, fg: C.redInk),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      if (bills.isEmpty)
                        Panel(child: Padding(padding: const EdgeInsets.all(8), child: Text('No settled bills yet', style: ts(14, c: C.muted))))
                      else
                        for (final o in bills) ...[_billRow(context, s, o), const SizedBox(height: 10)],
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

  Widget _billRow(BuildContext context, Store s, Order o) {
    final status = s.billSyncStatus[o.id];
    return Panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(s.titleOf(o), style: ts(15, w: w5)),
              const SizedBox(width: 8),
              Text(o.billNo ?? '', style: ts(13, c: C.muted)),
            ]),
            const SizedBox(height: 4),
            Text('${inr(o.total, decimals: true)} · ${elapsed(o.billedAt ?? o.at)} ago', style: ts(13, c: C.ink2)),
            if (status?.state == BillSyncState.failed && status?.lastError != null) ...[
              const SizedBox(height: 6),
              Text(status!.lastError!, style: ts(12, c: C.redInk, h: 1.3)),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        _statusPill(status),
        if (status?.state == BillSyncState.failed) ...[
          const SizedBox(width: 10),
          Btn.outline('Retry', height: 36, fontSize: 13, onTap: () => s.retryBillSync(o)),
        ],
      ]),
    );
  }

  Widget _statusPill(BillSyncStatus? status) {
    switch (status?.state) {
      case BillSyncState.synced:
        return const Pill('Synced', bg: C.greenTint, fg: C.greenInk);
      case BillSyncState.pending:
        return Pill(status!.attempts == 0 ? 'Queued' : 'Retrying…', bg: C.amberTint, fg: C.amberInk);
      case BillSyncState.failed:
        return const Pill('Failed', bg: C.redTint, fg: C.redInk);
      case null:
        return const Pill('Not tracked', bg: C.soft, fg: C.ink2);
    }
  }
}
