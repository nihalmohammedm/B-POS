import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../print_layout.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings › Payment QR: the UPI IDs the restaurant collects on. The selected
/// one prints as a pay QR on unpaid bills; the payment dialog offers all of them.
/// Every change is saved immediately.
class PaymentQrPanel extends StatelessWidget {
  const PaymentQrPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final l = s.printLayout;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Payment QR', style: ts(17, w: w5)),
        const SizedBox(height: 4),
        Text('The QR carries the bill amount, so the guest only confirms in their UPI app.', style: ts(13, c: C.muted, h: 1.4)),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => s.editPaymentQr((l) => l.billShowQr = !l.billShowQr),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Text('Print pay QR on unpaid bills', style: ts(15, w: w5))),
              Toggle(value: l.billShowQr, scale: .8, onChanged: (v) => s.editPaymentQr((l) => l.billShowQr = v)),
            ]),
          ),
        ),
        const Divider(height: 24),
        Text('UPI IDs', style: ts(15, w: w5)),
        Text('Add every ID you collect on. The selected one is printed on bills.', style: ts(12, c: C.muted)),
        const SizedBox(height: 8),
        if (l.upiAccounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(l.billShowQr ? 'No UPI ID added yet, so bills print without a QR.' : 'No UPI ID added yet.',
                style: ts(13, c: l.billShowQr ? C.red : C.muted)),
          ),
        for (final a in l.upiAccounts) _row(context, s, l, a),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerLeft,
            child: Btn.outline('Add UPI ID', icon: Icons.add, height: 44, onTap: () => _edit(context, s, null))),
      ]),
    );
  }

  Widget _row(BuildContext context, Store s, PrintLayout l, UpiAccount a) {
    final on = identical(l.billUpi, a);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
            color: on ? C.greenTint : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? C.green : C.line)),
        child: Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => s.editPaymentQr((l) => l.billUpiId = a.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(children: [
                  Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: on ? C.green : C.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.label, style: ts(15, w: w5)),
                      Text(a.vpa, style: ts(12, c: C.muted)),
                    ]),
                  ),
                  if (on) const Pill('ON BILLS', bg: C.greenTint, fg: C.greenInk, size: 11),
                ]),
              ),
            ),
          ),
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, s, a)),
          IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, color: C.red), onPressed: () => _remove(context, s, a)),
        ]),
      ),
    );
  }

  Future<void> _remove(BuildContext context, Store s, UpiAccount a) async {
    final ok = await confirmDialog(context,
        title: 'Remove ${a.label}?', body: '${a.vpa} stops appearing on bills and in the payment dialog.', ok: 'Remove', okColor: C.red);
    if (ok) s.editPaymentQr((l) => l.upiAccounts.removeWhere((x) => x.id == a.id));
  }

  Future<void> _edit(BuildContext context, Store s, UpiAccount? existing) => showSheet(context, (ctx) {
        final labelC = TextEditingController(text: existing?.label ?? '');
        final vpaC = TextEditingController(text: existing?.vpa ?? '');
        final payeeC = TextEditingController(text: existing?.payee ?? '');
        return StatefulBuilder(builder: (ctx, set) {
          final vpa = vpaC.text.trim();
          final valid = UpiAccount.validVpa(vpa);
          final ready = labelC.text.trim().isNotEmpty && valid;
          void save() {
            s.editPaymentQr((l) {
              if (existing != null) {
                final a = l.upiAccounts.firstWhere((x) => x.id == existing.id, orElse: () => existing);
                a
                  ..label = labelC.text.trim()
                  ..vpa = vpa
                  ..payee = payeeC.text.trim();
              } else {
                final a = UpiAccount(
                    id: 'upi${DateTime.now().microsecondsSinceEpoch}',
                    label: labelC.text.trim(),
                    vpa: vpa,
                    payee: payeeC.text.trim());
                l.upiAccounts.add(a);
                if (l.upiAccounts.length == 1) l.billUpiId = a.id;
              }
            });
            Navigator.pop(ctx);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(existing == null ? 'Add UPI ID' : 'Edit UPI ID', style: ts(20, w: w5)),
              const SizedBox(height: 18),
              const Label('Name'),
              const SizedBox(height: 6),
              TextField(
                  controller: labelC,
                  style: ts(14),
                  decoration: const InputDecoration(hintText: 'e.g. Counter GPay'),
                  onChanged: (_) => set(() {})),
              const SizedBox(height: 14),
              const Label('UPI ID'),
              const SizedBox(height: 6),
              TextField(
                  controller: vpaC,
                  style: ts(14),
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(hintText: 'shop@okhdfcbank', errorText: vpa.isNotEmpty && !valid ? 'Not a valid UPI ID' : null),
                  onChanged: (_) => set(() {})),
              const SizedBox(height: 14),
              const Label('Payee name shown to the guest (optional)'),
              const SizedBox(height: 6),
              TextField(controller: payeeC, style: ts(14), decoration: const InputDecoration(hintText: 'Defaults to the name above')),
              if (valid) ...[
                const SizedBox(height: 18),
                Center(
                  child: QrImageView(
                      data: UpiAccount(id: '', label: labelC.text.trim(), vpa: vpa, payee: payeeC.text.trim()).uri(0),
                      size: 150,
                      backgroundColor: Colors.white),
                ),
                Center(child: Text('Test: scan with your UPI app', style: ts(12, c: C.muted))),
              ],
              const SizedBox(height: 18),
              Btn('Save', icon: Icons.check, expand: true, height: 52, onTap: ready ? save : null),
            ]),
          );
        });
      });
}
