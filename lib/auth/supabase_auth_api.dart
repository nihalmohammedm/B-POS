import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthSession {
  final String accessToken, refreshToken, authUserId, email;
  final DateTime expiresAt;
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.authUserId,
    required this.email,
    required this.expiresAt,
  });
}

class ProfileInfo {
  final String userId, fullName, roleCode, roleName;
  final Set<String> permissions;
  const ProfileInfo({
    required this.userId,
    required this.fullName,
    required this.roleCode,
    required this.roleName,
    required this.permissions,
  });
}

/// Talks to Supabase Auth (GoTrue) and reads the matching `bpos` profile/role rows.
/// Sibling to [BackofficeApi] (same host, same `bpos` schema), but this one carries
/// a signed-in user's own access token instead of the shared anon key wherever the
/// call should be attributed to that user (and honored by RLS once it's enabled).
class SupabaseAuthApi {
  final String baseUrl;
  final String anonKey;
  SupabaseAuthApi({required this.baseUrl, required this.anonKey});

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> _authHeaders() => {
        'apikey': anonKey,
        'Content-Type': 'application/json',
      };

  Map<String, String> _restHeaders(String accessToken) => {
        'apikey': anonKey,
        'Authorization': 'Bearer ${accessToken.isEmpty ? anonKey : accessToken}',
        'Accept-Profile': 'bpos',
        'Content-Profile': 'bpos',
      };

  AuthSession _sessionFromToken(Map<String, dynamic> body) {
    final user = body['user'] as Map<String, dynamic>?;
    if (user == null) throw AuthException('Malformed auth response');
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    return AuthSession(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
      authUserId: user['id'] as String,
      email: user['email'] as String? ?? '',
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Future<AuthSession> signInWithPassword({required String email, required String password}) async {
    final res = await http
        .post(Uri.parse('$_root/auth/v1/token?grant_type=password'),
            headers: _authHeaders(), body: jsonEncode({'email': email, 'password': password}))
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 300) {
      throw AuthException(body['error_description'] as String? ?? body['msg'] as String? ?? 'Sign-in failed');
    }
    return _sessionFromToken(body);
  }

  Future<AuthSession> signUp({required String email, required String password}) async {
    final res = await http
        .post(Uri.parse('$_root/auth/v1/signup'), headers: _authHeaders(), body: jsonEncode({'email': email, 'password': password}))
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 300) {
      throw AuthException(body['error_description'] as String? ?? body['msg'] as String? ?? 'Sign-up failed');
    }
    if (body['access_token'] == null) {
      throw AuthException('Account created but not signed in automatically — check email confirmation settings.');
    }
    return _sessionFromToken(body);
  }

  Future<AuthSession> refreshSession(String refreshToken) async {
    final res = await http
        .post(Uri.parse('$_root/auth/v1/token?grant_type=refresh_token'),
            headers: _authHeaders(), body: jsonEncode({'refresh_token': refreshToken}))
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 300) {
      throw AuthException(body['error_description'] as String? ?? body['msg'] as String? ?? 'Session expired');
    }
    return _sessionFromToken(body);
  }

  /// Row(s) this call is allowed to see are governed by RLS once it's enabled; for
  /// now the tables are open, but every call here still uses the caller's own
  /// access token rather than the anon key.
  Future<List<dynamic>> _get(String accessToken, String path, Map<String, String> qp) async {
    final uri = Uri.parse('$_root/rest/v1/$path').replace(queryParameters: qp);
    final res = await http.get(uri, headers: _restHeaders(accessToken)).timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw AuthException('$path failed (${res.statusCode}): ${res.body}');
    return jsonDecode(res.body) as List<dynamic>;
  }

  /// Looks up an outlet's id from its short code (e.g. "BOLGATTY") — the same
  /// lookup [BackofficeApi.fetchMenu] does internally, exposed here so the auth
  /// flow doesn't have to wait on a menu sync to know which outlet it's signing
  /// staff into.
  Future<String> resolveOutletId(String outletCode) async {
    final rows = await _get('', 'outlets', {'select': 'id', 'code': 'eq.$outletCode', 'limit': '1'});
    if (rows.isEmpty) throw AuthException('No outlet found with code "$outletCode"');
    return rows.first['id'] as String;
  }

  /// True once at least one staff member has been linked to [outletId] — used to
  /// decide whether the app should offer first-run owner setup or a plain login.
  Future<bool> outletHasAnyUser(String outletId) async {
    final rows = await _get('', 'outlet_users', {'select': 'id', 'outlet_id': 'eq.$outletId', 'limit': '1'});
    return rows.isNotEmpty;
  }

  Future<ProfileInfo?> fetchProfile({required String accessToken, required String authUserId, required String outletId}) async {
    final users = await _get(accessToken, 'users', {'select': 'id,full_name', 'auth_user_id': 'eq.$authUserId', 'limit': '1'});
    if (users.isEmpty) return null;
    final userId = users.first['id'] as String;
    final fullName = users.first['full_name'] as String? ?? '';

    final outletUsers = await _get(accessToken, 'outlet_users', {
      'select': 'role_id,roles(code,name)',
      'user_id': 'eq.$userId',
      'outlet_id': 'eq.$outletId',
      'is_active': 'eq.true',
      'limit': '1',
    });
    if (outletUsers.isEmpty) return null;
    final roleId = outletUsers.first['role_id'] as String;
    final role = outletUsers.first['roles'] as Map<String, dynamic>?;
    final roleCode = role?['code'] as String? ?? '';
    final roleName = role?['name'] as String? ?? '';

    final rolePerms = await _get(accessToken, 'role_permissions', {'select': 'permissions(code)', 'role_id': 'eq.$roleId'});
    final permissions = {
      for (final r in rolePerms)
        if ((r['permissions'] as Map<String, dynamic>?)?['code'] != null) (r['permissions'] as Map<String, dynamic>)['code'] as String
    };

    return ProfileInfo(userId: userId, fullName: fullName, roleCode: roleCode, roleName: roleName, permissions: permissions);
  }

  /// Bootstraps the very first Owner account: creates the `bpos.users` profile row
  /// and links it to [outletId] with the `owner` role. Only meant to be called right
  /// after [signUp], and only while [outletHasAnyUser] is still false.
  Future<ProfileInfo> createOwnerProfile({
    required String accessToken,
    required String authUserId,
    required String outletId,
    required String fullName,
  }) async {
    // Table grants for `bpos.users`/`bpos.outlet_users` are intentionally not open
    // to regular authenticated writes (RLS/grants aren't set up yet per CLAUDE.md,
    // and blanket INSERT would let anyone who signs up self-grant an owner role).
    // Bootstrap instead goes through the guarded `bpos.bootstrap_first_owner`
    // SECURITY DEFINER function from the seed migration, which only succeeds while
    // the outlet truly has zero staff yet.
    final uri = Uri.parse('$_root/rest/v1/rpc/bootstrap_first_owner');
    final res = await http
        .post(uri, headers: _restHeaders(accessToken), body: jsonEncode({'p_outlet_id': outletId, 'p_full_name': fullName}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) {
      final body = jsonDecode(res.body);
      final msg = body is Map<String, dynamic> ? (body['message'] as String? ?? res.body) : res.body;
      throw AuthException(msg);
    }

    final profile = await fetchProfile(accessToken: accessToken, authUserId: authUserId, outletId: outletId);
    if (profile == null) throw AuthException('Owner account created but could not be loaded — try signing in again.');
    return profile;
  }
}
