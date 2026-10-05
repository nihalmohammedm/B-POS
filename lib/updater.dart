import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// GitHub repo whose Releases host the APKs. Each release is tagged `v<name>+<code>`
/// (e.g. `v1.0.1+2`) and carries one APK per flavor: `bpos-pos.apk`, `bpos-captain.apk`,
/// `bpos-kitchen.apk`. The repo must be public for the device to read releases.
const updateRepo = 'nihalmohammedm/B-POS';

class AppInfo {
  final String packageName, versionName;
  final int versionCode;
  const AppInfo(this.packageName, this.versionName, this.versionCode);

  /// `com.bpos.app` → pos, `com.bpos.captain` → captain, `com.bpos.kitchen` → kitchen.
  String get flavor => switch (packageName) {
        'com.bpos.captain' => 'captain',
        'com.bpos.kitchen' => 'kitchen',
        _ => 'pos',
      };
}

class UpdateInfo {
  final String versionName, notes, apkUrl;
  final int versionCode, size;
  const UpdateInfo(this.versionName, this.versionCode, this.notes, this.apkUrl, this.size);
}

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

class Updater {
  static const _ch = MethodChannel('bpos/updater');

  static bool get supported => Platform.isAndroid;

  static Future<AppInfo> appInfo() async {
    final m = Map<String, dynamic>.from(await _ch.invokeMethod('getInfo') as Map);
    return AppInfo(m['packageName'] as String, m['versionName'] as String, (m['versionCode'] as num).toInt());
  }

  /// Returns the newest release if it is newer than the installed build, else null.
  static Future<UpdateInfo?> check(AppInfo cur) async {
    final res = await http
        .get(Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) throw UpdateException('No releases published yet');
    if (res.statusCode >= 300) throw UpdateException('Update check failed (${res.statusCode})');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
    final parts = tag.split('+');
    final name = parts.first;
    final code = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final assets = (j['assets'] as List).cast<Map<String, dynamic>>();
    final apk = assets.where((a) => a['name'] == 'bpos-${cur.flavor}.apk').firstOrNull;
    if (apk == null) throw UpdateException('Release $tag has no bpos-${cur.flavor}.apk');
    final newer = code > 0 ? code > cur.versionCode : _cmp(name, cur.versionName) > 0;
    if (!newer) return null;
    return UpdateInfo(name, code, (j['body'] as String?) ?? '', apk['browser_download_url'] as String, (apk['size'] as num).toInt());
  }

  static int _cmp(String a, String b) {
    final x = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final y = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  static Future<bool> canInstall() async => await _ch.invokeMethod('canInstall') as bool;
  static Future<void> openInstallSettings() => _ch.invokeMethod('openInstallSettings');

  /// Streams the APK to the cache dir, reporting 0..1 progress, and returns its path.
  static Future<String> download(UpdateInfo u, void Function(double) onProgress) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final file = File('${dir.path}/update.apk');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(u.apkUrl)));
      if (res.statusCode >= 300) throw UpdateException('Download failed (${res.statusCode})');
      final total = res.contentLength ?? u.size;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      if (u.size > 0 && got != u.size) throw UpdateException('Download incomplete');
    } finally {
      client.close();
    }
    return file.path;
  }

  static Future<void> install(String path) => _ch.invokeMethod('install', {'path': path});
}

/// Settings card: shows the installed version, checks for a newer release, downloads and installs it.
class UpdatePanel extends StatefulWidget {
  const UpdatePanel({super.key});
  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> {
  AppInfo? _info;
  UpdateInfo? _update;
  bool _checking = false, _checked = false;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Updater.supported) Updater.appInfo().then((i) => mounted ? setState(() => _info = i) : null, onError: (_) {});
  }

  Future<void> _check() async {
    if (_info == null) return;
    setState(() { _checking = true; _error = null; });
    try {
      final u = await Updater.check(_info!);
      if (!mounted) return;
      setState(() { _update = u; _checked = true; });
    } catch (e) {
      if (mounted) setState(() => _error = e is UpdateException ? e.message : 'Could not reach the update server');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    final u = _update!;
    try {
      if (!await Updater.canInstall()) {
        if (!mounted) return;
        toast(context, 'Allow “Install unknown apps” for BPOS, then tap Update again');
        await Updater.openInstallSettings();
        return;
      }
      setState(() { _progress = 0; _error = null; });
      final path = await Updater.download(u, (p) { if (mounted) setState(() => _progress = p); });
      await Updater.install(path);
    } catch (e) {
      if (mounted) setState(() => _error = e is UpdateException ? e.message : 'Update failed · $e');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final busy = _checking || _progress != null;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('App update', style: ts(17, w: w5)),
        const SizedBox(height: 4),
        Text(
          !Updater.supported
              ? 'In-app updates are only available on Android.'
              : info == null ? 'Reading version…' : 'Installed version ${info.versionName} (build ${info.versionCode})',
          style: ts(13, c: C.muted, h: 1.4),
        ),
        if (Updater.supported) ...[
          const SizedBox(height: 14),
          if (_progress != null) ...[
            LinearProgressIndicator(value: _progress, minHeight: 6),
            const SizedBox(height: 8),
            Text('Downloading ${(_progress! * 100).round()}%', style: ts(12, c: C.muted)),
          ] else if (_update != null) ...[
            Text('Version ${_update!.versionName} is available', style: ts(14, w: w5)),
            if (_update!.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_update!.notes.trim(), maxLines: 6, overflow: TextOverflow.ellipsis, style: ts(13, c: C.ink2, h: 1.4)),
            ],
          ] else if (_checked && _error == null)
            Text('You\'re on the latest version', style: ts(13, c: C.greenInk)),
          if (_error != null) Text(_error!, style: ts(13, c: C.red)),
          const SizedBox(height: 14),
          Row(children: [
            Btn.outline('Check for update', icon: Icons.refresh, onTap: busy || info == null ? null : _check),
            const SizedBox(width: 10),
            if (_update != null) Btn('Update now', icon: Icons.system_update, onTap: busy ? null : _install),
          ]),
        ],
      ]),
    );
  }
}
