import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A staff member's local login on *this* device: identity + role cached from
/// their last successful sign-in, a salted PIN hash for the lock screen, and the
/// Supabase refresh token that lets the app mint a fresh session without asking
/// for their password again. Lives only in this device's secure storage — never
/// synced, never sent anywhere.
class LocalProfile {
  final String authUserId, email, fullName, roleCode, roleName;
  final String pinSalt, pinHash;
  final String refreshToken;
  final DateTime lastUsedAt;

  const LocalProfile({
    required this.authUserId,
    required this.email,
    required this.fullName,
    required this.roleCode,
    required this.roleName,
    required this.pinSalt,
    required this.pinHash,
    required this.refreshToken,
    required this.lastUsedAt,
  });

  LocalProfile copyWith({
    String? fullName,
    String? roleCode,
    String? roleName,
    String? pinSalt,
    String? pinHash,
    String? refreshToken,
    DateTime? lastUsedAt,
  }) =>
      LocalProfile(
        authUserId: authUserId,
        email: email,
        fullName: fullName ?? this.fullName,
        roleCode: roleCode ?? this.roleCode,
        roleName: roleName ?? this.roleName,
        pinSalt: pinSalt ?? this.pinSalt,
        pinHash: pinHash ?? this.pinHash,
        refreshToken: refreshToken ?? this.refreshToken,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, dynamic> toJson() => {
        'authUserId': authUserId,
        'email': email,
        'fullName': fullName,
        'roleCode': roleCode,
        'roleName': roleName,
        'pinSalt': pinSalt,
        'pinHash': pinHash,
        'refreshToken': refreshToken,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory LocalProfile.fromJson(Map<String, dynamic> j) => LocalProfile(
        authUserId: j['authUserId'] as String,
        email: j['email'] as String,
        fullName: j['fullName'] as String,
        roleCode: j['roleCode'] as String,
        roleName: j['roleName'] as String,
        pinSalt: j['pinSalt'] as String,
        pinHash: j['pinHash'] as String,
        refreshToken: j['refreshToken'] as String,
        lastUsedAt: DateTime.parse(j['lastUsedAt'] as String),
      );
}

class ProfileStore {
  static const _key = 'bpos_local_profiles_v1';
  // macOS: the default "Data Protection Keychain" API needs a keychain-access-groups
  // entitlement tied to a real Apple Developer Team in Xcode signing, or every call
  // fails with PlatformException(-34018, errSecMissingEntitlement) — regardless of
  // App Sandbox. useDataProtectionKeychain: false switches to the legacy per-app
  // keychain API, which works for local/ad-hoc-signed dev builds with no entitlement
  // at all. Not needed on other platforms, so it's a no-op there.
  final _storage = const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));
  final _rand = Random.secure();

  String _newSalt() => base64Url.encode(List<int>.generate(16, (_) => _rand.nextInt(256)));

  String hashPin(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<List<LocalProfile>> list() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    final arr = jsonDecode(raw) as List<dynamic>;
    final profiles = arr.map((e) => LocalProfile.fromJson(e as Map<String, dynamic>)).toList();
    profiles.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return profiles;
  }

  Future<void> _saveAll(List<LocalProfile> profiles) async {
    await _storage.write(key: _key, value: jsonEncode(profiles.map((p) => p.toJson()).toList()));
  }

  Future<LocalProfile?> find(String authUserId) async {
    final all = await list();
    for (final p in all) {
      if (p.authUserId == authUserId) return p;
    }
    return null;
  }

  Future<LocalProfile?> mostRecentlyUsed() async {
    final all = await list();
    return all.isEmpty ? null : all.first;
  }

  /// Creates or refreshes the cached identity/role/refresh-token for a profile,
  /// without touching its PIN (used right after any successful sign-in/refresh).
  Future<LocalProfile> upsertIdentity({
    required String authUserId,
    required String email,
    required String fullName,
    required String roleCode,
    required String roleName,
    required String refreshToken,
  }) async {
    final all = await list();
    final i = all.indexWhere((p) => p.authUserId == authUserId);
    final LocalProfile updated;
    if (i == -1) {
      updated = LocalProfile(
        authUserId: authUserId,
        email: email,
        fullName: fullName,
        roleCode: roleCode,
        roleName: roleName,
        pinSalt: '',
        pinHash: '',
        refreshToken: refreshToken,
        lastUsedAt: DateTime.now(),
      );
      all.add(updated);
    } else {
      updated = all[i].copyWith(
        fullName: fullName,
        roleCode: roleCode,
        roleName: roleName,
        refreshToken: refreshToken,
        lastUsedAt: DateTime.now(),
      );
      all[i] = updated;
    }
    await _saveAll(all);
    return updated;
  }

  bool hasPin(LocalProfile p) => p.pinHash.isNotEmpty;

  Future<void> setPin(String authUserId, String pin) async {
    final all = await list();
    final i = all.indexWhere((p) => p.authUserId == authUserId);
    if (i == -1) return;
    final salt = _newSalt();
    all[i] = all[i].copyWith(pinSalt: salt, pinHash: hashPin(pin, salt), lastUsedAt: DateTime.now());
    await _saveAll(all);
  }

  Future<bool> verifyPin(String authUserId, String pin) async {
    final p = await find(authUserId);
    if (p == null || p.pinHash.isEmpty) return false;
    return hashPin(pin, p.pinSalt) == p.pinHash;
  }

  Future<void> touch(String authUserId) async {
    final all = await list();
    final i = all.indexWhere((p) => p.authUserId == authUserId);
    if (i == -1) return;
    all[i] = all[i].copyWith(lastUsedAt: DateTime.now());
    await _saveAll(all);
  }

  Future<void> remove(String authUserId) async {
    final all = await list()
      ..removeWhere((p) => p.authUserId == authUserId);
    await _saveAll(all);
  }
}
