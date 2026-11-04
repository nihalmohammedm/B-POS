import '../backoffice_api.dart';
import '../plain_error.dart';
import 'package:flutter/material.dart';
import '../pos/pos_shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'login_screen.dart';
import 'outlet_picker.dart';
import 'pin_screen.dart';
import 'profile_store.dart';
import 'supabase_auth_api.dart';

enum _Stage { loading, error, login, addAnotherLogin, pickOutlet, setPin, pinLock, authenticated }

/// BPOS's home screen: staff accounts already exist in Supabase (an admin creates
/// them; the app never does), so this is a plain
/// email+password login, the per-user PIN lock, or (once unlocked) the real
/// [PosShell] — see CLAUDE.md-adjacent plan notes on per-user PIN profiles.
/// The Captain app never uses this; it boots straight into its own UI.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _profileStore = ProfileStore();
  _Stage _stage = _Stage.loading;
  _Stage _loginStage = _Stage.login;
  String? _errorMessage;
  // Signed in, waiting on the outlet pick.
  AuthSession? _pickSession;
  List<OutletChoice> _pickOutlets = const [];
  LocalProfile? _activeProfile;
  String? _pendingAuthUserId;
  String? _pendingFullName;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _bootstrap();
    }
  }

  SupabaseAuthApi _api() {
    final s = StoreScope.of(context);
    return SupabaseAuthApi(baseUrl: s.backofficeUrl, anonKey: s.backofficeKey);
  }

  Future<void> _bootstrap() async {
    setState(() => _stage = _Stage.loading);
    final profiles = await _profileStore.list();
    if (profiles.isNotEmpty) {
      setState(() {
        _activeProfile = profiles.first;
        _stage = _Stage.pinLock;
      });
      return;
    }
    if (!mounted) return;
    try {
      await StoreScope.of(context).resolveOutletId();
      if (!mounted) return;
      setState(() => _stage = _Stage.login);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is AuthException || e is BackofficeException ? e.toString() : plainError(e);
        _stage = _Stage.error;
      });
    }
  }

  // Always the till's current outlet: it can change from inside the POS (Switch outlet).
  Future<String> _ensureOutletId() => StoreScope.of(context).resolveOutletId();

  Future<void> _afterAuthenticated({
    required AuthSession session,
    required ProfileInfo profile,
  }) async {
    final s = StoreScope.of(context);
    s.applySession(
      authUserId: session.authUserId,
      email: session.email,
      fullName: profile.fullName,
      accessToken: session.accessToken,
      roleCode: profile.roleCode,
      roleName: profile.roleName,
      permissions: profile.permissions,
    );
    final local = await _profileStore.upsertIdentity(
      authUserId: session.authUserId,
      email: session.email,
      fullName: profile.fullName,
      roleCode: profile.roleCode,
      roleName: profile.roleName,
      refreshToken: session.refreshToken,
    );
    if (!mounted) return;
    if (_profileStore.hasPin(local)) {
      setState(() {
        _activeProfile = local;
        _stage = _Stage.authenticated;
      });
    } else {
      setState(() {
        _pendingAuthUserId = session.authUserId;
        _pendingFullName = profile.fullName;
        _stage = _Stage.setPin;
      });
    }
  }

  /// Signs in, then settles which outlet: a till that already has one stays on it; a new
  /// till takes the user's only outlet, or asks when they work at several.
  Future<String?> _submitLogin(String email, String password) async {
    try {
      final s = StoreScope.of(context);
      final api = _api();
      final session = await api.signInWithPassword(email: email, password: password);
      final outlets = await api.fetchUserOutlets(accessToken: session.accessToken, authUserId: session.authUserId);
      if (outlets.isEmpty) return 'This login is not set up for any outlet. Ask the owner to add you.';
      OutletChoice? here;
      for (final o in outlets) {
        if (o.code == s.backofficeOutletCode) here = o;
      }
      if (s.outletBound) {
        if (here == null) {
          return 'This till is set up for ${s.outletName.isEmpty ? s.backofficeOutletCode : s.outletName}, '
              'and you are not linked to it. Ask the owner to add you.';
        }
        return await _enterOutlet(session, here);
      }
      if (outlets.length == 1) return await _enterOutlet(session, outlets.first);
      if (!mounted) return null;
      setState(() {
        _loginStage = _stage;
        _pickSession = session;
        _pickOutlets = outlets;
        _stage = _Stage.pickOutlet;
      });
      return null;
    } catch (e) {
      return e is AuthException || e is BackofficeException ? e.toString() : plainError(e);
    }
  }

  /// Opens [o] for [session]: reads the user's role there first, so a failure leaves the
  /// till untouched, then makes it this till's outlet.
  Future<String?> _enterOutlet(AuthSession session, OutletChoice o) async {
    try {
      final s = StoreScope.of(context);
      final profile = await _api().fetchProfile(accessToken: session.accessToken, authUserId: session.authUserId, outletId: o.id);
      final blocked = await s.switchOutlet(o.code);
      if (blocked != null) return blocked;
      await _afterAuthenticated(session: session, profile: profile);
      return null;
    } catch (e) {
      return e is AuthException || e is BackofficeException ? e.toString() : plainError(e);
    }
  }

  Future<void> _submitSetPin(String pin) async {
    final authUserId = _pendingAuthUserId;
    if (authUserId == null) return;
    await _profileStore.setPin(authUserId, pin);
    final local = await _profileStore.find(authUserId);
    if (!mounted) return;
    setState(() {
      _activeProfile = local;
      _stage = _Stage.authenticated;
    });
  }

  Future<bool> _verifyPin(String pin) async {
    final profile = _activeProfile;
    if (profile == null) return false;
    final ok = await _profileStore.verifyPin(profile.authUserId, pin);
    if (!ok) return false;
    try {
      final outletId = await _ensureOutletId();
      final session = await _api().refreshSession(profile.refreshToken);
      // Throws if no longer linked to this outlet: the catch below then falls
      // back to a full login instead of letting a de-authorized profile in.
      final profileInfo = await _api().fetchProfile(accessToken: session.accessToken, authUserId: session.authUserId, outletId: outletId);
      if (!mounted) return true;
      final s = StoreScope.of(context);
      s.applySession(
        authUserId: session.authUserId,
        email: session.email,
        fullName: profileInfo.fullName,
        accessToken: session.accessToken,
        roleCode: profileInfo.roleCode,
        roleName: profileInfo.roleName,
        permissions: profileInfo.permissions,
      );
      await _profileStore.upsertIdentity(
        authUserId: session.authUserId,
        email: session.email,
        fullName: profileInfo.fullName,
        roleCode: profileInfo.roleCode,
        roleName: profileInfo.roleName,
        refreshToken: session.refreshToken,
      );
      if (!mounted) return true;
      setState(() => _stage = _Stage.authenticated);
      return true;
    } catch (_) {
      // Refresh token expired/revoked — the PIN itself was right, so send them to
      // a normal password sign-in rather than a dead end.
      if (!mounted) return true;
      setState(() => _stage = _Stage.login);
      return true;
    }
  }

  /// From the POS: lock back to this user's PIN, or [forget] their saved login and go to
  /// the next saved profile's PIN (or the password login when none is left).
  Future<void> _signOut({required bool forget}) async {
    final s = StoreScope.of(context);
    final id = s.authUserId;
    s.clearSession();
    if (forget && id != null) await _profileStore.remove(id);
    final next = forget ? await _profileStore.mostRecentlyUsed() : (id == null ? null : await _profileStore.find(id));
    if (!mounted) return;
    setState(() {
      _activeProfile = next;
      _stage = next != null && _profileStore.hasPin(next) ? _Stage.pinLock : _Stage.login;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    switch (_stage) {
      case _Stage.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));

      case _Stage.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off, size: 40, color: C.muted),
                const SizedBox(height: 12),
                Text('Could not reach the server', style: ts(17, w: w6)),
                const SizedBox(height: 6),
                Text(_errorMessage ?? '', textAlign: TextAlign.center, style: ts(13, c: C.muted)),
                const SizedBox(height: 20),
                Btn('Retry', onTap: _bootstrap),
              ]),
            ),
          ),
        );

      case _Stage.login:
        return LoginScreen(outletName: s.outletName, onSubmit: _submitLogin);

      case _Stage.addAnotherLogin:
        return LoginScreen(
          outletName: s.outletName,
          onSubmit: _submitLogin,
          onCancel: () => setState(() => _stage = _Stage.pinLock),
        );

      case _Stage.pickOutlet:
        return OutletPickerScreen(
          fullName: '',
          outlets: _pickOutlets,
          currentCode: s.outletBound ? s.backofficeOutletCode : '',
          onPick: (o) => _enterOutlet(_pickSession!, o),
          onCancel: () => setState(() => _stage = _loginStage),
        );

      case _Stage.setPin:
        return SetPinScreen(fullName: _pendingFullName ?? '', onSet: _submitSetPin);

      case _Stage.pinLock:
        final p = _activeProfile!;
        return PinLockScreen(
          fullName: p.fullName,
          roleName: p.roleName,
          onVerify: _verifyPin,
          onSwitchUser: () => setState(() => _stage = _Stage.addAnotherLogin),
          onForgotPin: () => setState(() => _stage = _Stage.addAnotherLogin),
        );

      case _Stage.authenticated:
        return PosShell(onSignOut: _signOut);
    }
  }
}
