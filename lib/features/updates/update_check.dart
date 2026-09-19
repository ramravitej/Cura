import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where releases are published. Drafts and prereleases never show.
const kLatestReleaseUrl =
    'https://api.github.com/repos/Tarun-032/Cura/releases/latest';

/// true = check daily. Missing or false = only when the user taps Check.
const kUpdateCheckKey = 'cura_update_check';

/// Last auto-check (ms); also backs "Later".
const kUpdateLastCheckKey = 'cura_update_last_check';

/// How often an automatic check may run.
const kUpdateCheckInterval = Duration(hours: 24);

/// App-support updates dir (FileProvider).
const kUpdateDir = 'updates';

const _device = MethodChannel('com.cura.cura/device');

/// A published release with an installable APK.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.publishedAt,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
    required this.pageUrl,
    this.sha256,
  });

  /// "1.4.0", without the tag's "v".
  final String version;

  /// Release body, markdown.
  final String notes;
  final DateTime? publishedAt;
  final String apkUrl;
  final String apkName;
  final int apkSize;

  /// The release page, for "Open on GitHub".
  final String pageUrl;

  /// Lowercase hex from GitHub's asset digest; null if GitHub gave none.
  final String? sha256;
}

/// The API's release JSON, or null when it has no APK to install.
AppRelease? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  if (tag is! String || tag.isEmpty) return null;
  final assets = json['assets'];
  if (assets is! List) return null;
  for (final a in assets) {
    if (a is! Map) continue;
    final name = a['name'];
    final url = a['browser_download_url'];
    final size = a['size'];
    if (name is! String || !name.toLowerCase().endsWith('.apk')) continue;
    if (url is! String || size is! int) continue;
    final digest = a['digest'];
    return AppRelease(
      version: _bare(tag),
      notes: (json['body'] as String?) ?? '',
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? ''),
      apkUrl: url,
      apkName: name,
      apkSize: size,
      pageUrl: (json['html_url'] as String?) ?? '',
      sha256: digest is String && digest.startsWith('sha256:')
          ? digest.substring(7).toLowerCase()
          : null,
    );
  }
  return null;
}

String _bare(String v) => v.trim().replaceFirst(RegExp('^[vV]'), '');

/// Numeric parts of "v1.4.0-beta" → [1, 4, 0]; null when malformed.
List<int>? _parts(String v) {
  final core = _bare(v).split(RegExp('[-+]')).first;
  final parts = core.split('.');
  final out = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return out.isEmpty ? null : out;
}

/// True if [remote] > [current] numerically; malformed → false.
bool isNewerVersion(String remote, String current) {
  final r = _parts(remote);
  final c = _parts(current);
  if (r == null || c == null) return false;
  for (var i = 0; i < r.length || i < c.length; i++) {
    final a = i < r.length ? r[i] : 0;
    final b = i < c.length ? c[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Auto-check: opted in, interval elapsed (clock back → due).
bool isAutoCheckDue({
  required bool? allowed,
  required int? lastCheckMs,
  required int nowMs,
}) {
  if (allowed != true) return false;
  if (lastCheckMs == null) return true;
  final elapsed = nowMs - lastCheckMs;
  return elapsed < 0 || elapsed >= kUpdateCheckInterval.inMilliseconds;
}

/// Latest release, or null. GitHub API only; no records.
Future<AppRelease?> fetchLatestRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(
          Uri.parse(kLatestReleaseUrl),
          headers: const {
            'Accept': 'application/vnd.github+json',
            // GitHub requires User-Agent.
            'User-Agent': 'Cura',
          },
        )
        .timeout(const Duration(seconds: 10));
    debugPrint('[Cura.update] check status=${res.statusCode}');
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body);
    return json is Map<String, dynamic> ? parseRelease(json) : null;
  } catch (e) {
    debugPrint('[Cura.update] check failed: ${e.runtimeType}');
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// The installed version, e.g. "1.3.0".
Future<String?> installedVersion() =>
    _device.invokeMethod<String>('getVersion');

/// Daily check enabled (default off).
Future<bool> updateCheckAllowed() async =>
    (await SharedPreferences.getInstance()).getBool(kUpdateCheckKey) ?? false;

Future<void> setUpdateCheckAllowed(bool allowed) async =>
    (await SharedPreferences.getInstance()).setBool(kUpdateCheckKey, allowed);

/// Result of a check against the installed version.
class UpdateCheck {
  const UpdateCheck({required this.reached, this.release});

  /// False when GitHub could not be reached or answered with nothing usable.
  final bool reached;

  /// Set only when a newer version is out.
  final AppRelease? release;
}

/// Check now; [automatic] uses consent + daily gate + timestamp.
Future<UpdateCheck> checkForUpdate({bool automatic = false}) async {
  final prefs = await SharedPreferences.getInstance();
  if (automatic) {
    final due = isAutoCheckDue(
      allowed: prefs.getBool(kUpdateCheckKey),
      lastCheckMs: prefs.getInt(kUpdateLastCheckKey),
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!due) return const UpdateCheck(reached: false);
  }
  final current = await installedVersion().catchError((_) => null);
  final latest = await fetchLatestRelease();
  if (latest == null || current == null) {
    return const UpdateCheck(reached: false);
  }
  if (automatic) {
    await prefs.setInt(
      kUpdateLastCheckKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
  await _deleteStaleApks(current);
  final newer = isNewerVersion(latest.version, current);
  debugPrint(
    '[Cura.update] installed=$current latest=${latest.version} newer=$newer',
  );
  return UpdateCheck(reached: true, release: newer ? latest : null);
}

/// Where [release]'s APK is (or will be) downloaded.
Future<File> apkFileFor(AppRelease release) async {
  final base = await getApplicationSupportDirectory();
  return File(p.join(base.path, kUpdateDir, release.apkName));
}

/// Size + optional SHA-256 (hashed off UI thread).
Future<bool> verifyApk(File file, {required int size, String? sha256}) async {
  if (!await file.exists() || await file.length() != size) return false;
  // No digest: size only; signing still enforced.
  if (sha256 == null) return true;
  final path = file.path;
  final actual = await Isolate.run(() => _sha256Of(path));
  return actual == sha256;
}

Future<String> _sha256Of(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

/// Delete APKs not newer than installed.
Future<void> _deleteStaleApks(String current) async {
  try {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, kUpdateDir),
    );
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final m = RegExp(r'(\d+(?:\.\d+)+)\.apk$').firstMatch(p.basename(f.path));
      if (m == null || !isNewerVersion(m.group(1)!, current)) await f.delete();
    }
  } catch (_) {
    // Housekeeping only.
  }
}

/// Whether Android lets Cura install apps yet.
Future<bool> canInstallUpdates() async =>
    await _device.invokeMethod<bool>('canInstallPackages') ?? false;

/// The system page where the user allows Cura to install apps.
Future<void> openInstallPermission() =>
    _device.invokeMethod('openInstallPermission');

/// Hands [file] to Android's installer.
Future<void> installApk(File file) =>
    _device.invokeMethod('installApk', {'path': file.path});

/// Opens an https link in the browser.
Future<void> openLink(String url) => _device.invokeMethod('openUrl', {'url': url});
