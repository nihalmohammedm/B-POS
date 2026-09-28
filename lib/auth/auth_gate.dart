import 'package:flutter/material.dart';
import '../pos/pos_shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'login_screen.dart';
import 'pin_screen.dart';
import 'profile_store.dart';
import 'setup_owner_screen.dart';
import 'supabase_auth_api.dart';

enum _Stage { loading, error, setupOwner, login, addAnotherLogin, setPin, pinLock, authenticated }

/// BPOS's home screen: decides between first-run owner setup, a plain
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
  String? _outletId;
  String? _errorMessage;
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
      final s = StoreScope.of(context);
      final outletId = await _api().resolveOutletId(s.backofficeOutletCode);
      final hasUsers = await _api().outletHasAnyUser(outletId);
      if (!mounted) return;
      setState(() {
        _outletId = outletId;
        _stage = hasUsers ? _Stage.login : _Stage.setupOwner;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _stage = _Stage.error;
      });
    }
  }

  Future<String> _ensureOutletId() async {
    if (_outletId != null) return _outletId!;
    final s = StoreScope.of(context);
    _outletId = await _api().resolveOutletId(s.backofficeOutletCode);
    return _outletId!;
  }

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

  Future<String?> _submitSetupOwner(String fullName, String email, String password) async {
    try {
      final outletId = await _ensureOutletId();
      final session = await _api().signUp(email: email, password: password);
      final profile =
          await _api().createOwnerProfile(accessToken: session.accessToken, authUserId: session.authUserId, outletId: outletId, fullName: fullName);
      await _afterAuthenticated(session: session, profile: profile);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> _submitLogin(String email, String password) async {
    try {
      final outletId = await _ensureOutletId();
      final session = await _api().signInWithPassword(email: email, password: password);
      final profile = await _api().fetchProfile(accessToken: session.accessToken, authUserId: session.authUserId, outletId: outletId);
      if (profile == null) {
        return "This account isn't set up for this outlet yet. Contact your manager.";
      }
      await _afterAuthenticated(session: session, profile: profile);
      return null;
    } catch (e) {
      return e.toString();
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
      final profileInfo = await _api().fetchProfile(accessToken: session.accessToken, authUserId: session.authUserId, outletId: outletId);
      if (profileInfo == null) {
        // No longer linked to this outlet — fall back to a full re-login instead
        // of silently letting a de-authorized profile back in.
        if (!mounted) return true;
        setState(() => _stage = _Stage.login);
        return true;
      }
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

      case _Stage.setupOwner:
        return SetupOwnerScreen(outletName: s.outletName, onSubmit: _submitSetupOwner);

      case _Stage.login:
        return LoginScreen(outletName: s.outletName, onSubmit: _submitLogin);

      case _Stage.addAnotherLogin:
        return LoginScreen(
          outletName: s.outletName,
          onSubmit: _submitLogin,
          onCancel: () => setState(() => _stage = _Stage.pinLock),
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
        return const PosShell();
    }
  }
}
