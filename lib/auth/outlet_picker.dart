import 'package:flutter/material.dart';
import '../plain_error.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'supabase_auth_api.dart';

/// Shown after sign-in when the user works at more than one outlet and this till hasn't
/// been given one yet. The pick becomes the till's outlet (see Store.switchOutlet).
class OutletPickerScreen extends StatefulWidget {
  final String fullName;
  final List<OutletChoice> outlets;
  final String currentCode;

  /// Returns an error to show, or null once the outlet is open.
  final Future<String?> Function(OutletChoice o) onPick;
  final VoidCallback onCancel;
  const OutletPickerScreen(
      {super.key, required this.fullName, required this.outlets, required this.currentCode, required this.onPick, required this.onCancel});
  @override
  State<OutletPickerScreen> createState() => _OutletPickerScreenState();
}

class _OutletPickerScreenState extends State<OutletPickerScreen> {
  String? _busy, _error;

  Future<void> _pick(OutletChoice o) async {
    setState(() {
      _busy = o.id;
      _error = null;
    });
    final err = await widget.onPick(o);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(onPressed: _busy == null ? widget.onCancel : null, icon: const Icon(Icons.arrow_back, color: C.ink)),
                  ),
                  Text('Choose outlet', style: ts(24, w: w6)),
                  const SizedBox(height: 4),
                  Text(
                      '${widget.fullName.isEmpty ? 'You work' : '${widget.fullName} works'} at ${widget.outlets.length} outlets. '
                      'This till will remember the one you pick.',
                      style: ts(14, c: C.muted, h: 1.4)),
                  const SizedBox(height: 22),
                  for (final o in widget.outlets) ...[
                    OutletTile(o, current: o.code == widget.currentCode, busy: _busy == o.id, onTap: _busy == null ? () => _pick(o) : null),
                    const SizedBox(height: 10),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(_error!, style: ts(13, c: C.red, w: w5, h: 1.4)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}

/// One outlet as a large tap target: initial, name, code.
class OutletTile extends StatelessWidget {
  final OutletChoice o;
  final bool current, busy;
  final VoidCallback? onTap;
  const OutletTile(this.o, {super.key, this.current = false, this.busy = false, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            height: 76,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18), border: Border.all(color: current ? C.ink : C.line, width: current ? 2 : 1)),
            child: Row(children: [
              CircleAvatar(
                  radius: 22,
                  backgroundColor: C.sky,
                  child: Text(o.name.isEmpty ? '·' : o.name[0].toUpperCase(), style: ts(17, w: w6, c: Colors.white))),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.name.isEmpty ? o.code : o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(17, w: w5)),
                Text(o.code, style: ts(13, c: C.muted)),
              ])),
              if (busy)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              else if (current)
                const Pill('THIS TILL', bg: C.ink, fg: Colors.white, size: 11)
              else
                const Icon(Icons.chevron_right, color: C.muted),
            ]),
          ),
        ),
      );
}

/// "Switch outlet" from inside the POS, for staff linked to several outlets. Moving the
/// till wipes the old outlet's local data, so it is refused while anything is open or
/// waiting to upload, and asks for confirmation otherwise.
Future<void> showSwitchOutlet(BuildContext context) async {
  final s = StoreScope.read(context);
  final token = s.sessionAccessToken, uid = s.authUserId;
  if (token == null || uid == null) return;
  final api = SupabaseAuthApi(baseUrl: s.backofficeUrl, anonKey: s.backofficeKey);
  List<OutletChoice> outlets;
  try {
    outlets = await api.fetchUserOutlets(accessToken: token, authUserId: uid);
  } catch (e) {
    if (context.mounted) toast(context, e is AuthException ? e.message : plainError(e), error: true);
    return;
  }
  if (!context.mounted) return;
  if (outlets.length < 2) {
    toast(context, 'You are only linked to this outlet');
    return;
  }
  final blocked = s.outletSwitchBlocker;
  final picked = await showPanelDialog<OutletChoice>(context,
      maxWidth: 460,
      builder: (ctx) => SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Switch outlet', style: ts(20, w: w5))),
                RoundIcon(Icons.close, size: 40, onTap: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 6),
              if (blocked != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.amberTint, borderRadius: BorderRadius.circular(12)),
                  child: Text("Can't switch yet. $blocked", style: ts(13, c: C.amberInk, w: w5, h: 1.4)),
                )
              else
                Text("This till's menu, tables and bill history are replaced by the new outlet's. Paired captains must pair again.",
                    style: ts(13, c: C.muted, h: 1.4)),
              const SizedBox(height: 16),
              for (final o in outlets) ...[
                OutletTile(o,
                    current: o.code == s.backofficeOutletCode,
                    onTap: blocked != null || o.code == s.backofficeOutletCode ? null : () => Navigator.pop(ctx, o)),
                const SizedBox(height: 10),
              ],
            ]),
          ));
  if (picked == null || !context.mounted) return;
  try {
    // Role and permissions can differ per outlet: read them before touching local data.
    final profile = await api.fetchProfile(accessToken: token, authUserId: uid, outletId: picked.id);
    final err = await s.switchOutlet(picked.code);
    if (!context.mounted) return;
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    s.applySession(
      authUserId: uid,
      email: s.sessionEmail ?? '',
      fullName: profile.fullName,
      accessToken: token,
      roleCode: profile.roleCode,
      roleName: profile.roleName,
      permissions: profile.permissions,
    );
    toast(context, 'Switched to ${picked.name.isEmpty ? picked.code : picked.name}');
  } catch (e) {
    if (context.mounted) toast(context, e is AuthException ? e.message : plainError(e), error: true);
  }
}
