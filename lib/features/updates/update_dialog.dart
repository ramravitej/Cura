import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../ai/ai_providers.dart';
import '../ai/model_download.dart';
import '../library/document.dart' show shortDate;
import 'update_check.dart';

/// Release notes + download/install.
Future<void> showUpdateDialog(BuildContext context, AppRelease release) =>
    showDialog<void>(
      context: context,
      // Not dismissible — only Later/Hide.
      barrierDismissible: false,
      builder: (_) => UpdateDialog(release: release),
    );

enum _Phase { available, downloading, verifying, ready, needsPermission, failed }

class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key, required this.release});

  final AppRelease release;

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog>
    with WidgetsBindingObserver {
  var _phase = _Phase.available;
  String? _error;
  File? _apk;

  AppRelease get _release => widget.release;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_resume());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Return from unknown-apps settings → retry install.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _phase == _Phase.needsPermission) {
      unawaited(_install());
    }
  }

  /// Resume in-flight or finished download.
  Future<void> _resume() async {
    try {
      _apk = await apkFileFor(_release);
      final running = ref.read(updateDownloadProvider);
      if (running != null && running.running) {
        _set(_Phase.downloading);
      } else if (await _apk!.exists()) {
        await _verify();
      }
    } catch (_) {
      // No partial file; fresh start OK.
    }
  }

  void _set(_Phase phase, [String? error]) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _error = error;
    });
  }

  Future<void> _download() async {
    _set(_Phase.downloading);
    try {
      await ref
          .read(modelDownloaderProvider)
          .start(
            url: _release.apkUrl,
            fileName: _release.apkName,
            directory: kUpdateDir,
            displayName: 'Cura ${_release.version}',
            kind: kUpdateDownload,
          );
    } on ModelDownloadException catch (e) {
      // Duplicate start: follow existing download.
      if (ref.read(updateDownloadProvider)?.running != true) {
        _set(_Phase.failed, e.message);
      }
    }
  }

  Future<void> _verify() async {
    _set(_Phase.verifying);
    final apk = _apk ??= await apkFileFor(_release);
    final ok = await verifyApk(
      apk,
      size: _release.apkSize,
      sha256: _release.sha256,
    );
    if (ok) {
      _set(_Phase.ready);
      return;
    }
    // Bad file → delete, don't install.
    if (await apk.exists()) await apk.delete();
    _set(
      _Phase.failed,
      'The download didn\'t match the release on GitHub, so it was deleted. '
      'Try again.',
    );
  }

  Future<void> _install() async {
    if (!await canInstallUpdates()) {
      _set(_Phase.needsPermission);
      return;
    }
    _set(_Phase.ready);
    try {
      await installApk(_apk!);
    } catch (_) {
      _set(_Phase.failed, 'Couldn\'t open the installer. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Download done or failed.
    ref.listen<ModelDownload?>(updateDownloadProvider, (prev, next) {
      if (_phase != _Phase.downloading) return;
      if (next?.error != null) {
        _set(_Phase.failed, next!.error);
      } else if (prev != null && next == null) {
        unawaited(_verify());
      }
    });
    final download = ref.watch(updateDownloadProvider);
    final textTheme = Theme.of(context).textTheme;
    final published = _release.publishedAt?.toLocal();

    return AlertDialog(
      title: const Text('New update available'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${_release.version}',
              style: textTheme.titleMedium?.copyWith(color: AppColors.ink),
            ),
            if (published != null)
              Text(
                'Released ${shortDate(published)}, ${published.year}',
                style: textTheme.bodySmall?.copyWith(color: AppColors.faint),
              ),
            const SizedBox(height: 14),
            ..._body(textTheme, download),
          ],
        ),
      ),
      actions: _actions(),
    );
  }

  List<Widget> _body(TextTheme textTheme, ModelDownload? download) {
    final muted = textTheme.bodyMedium?.copyWith(color: AppColors.secondary);
    switch (_phase) {
      case _Phase.available:
        return [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: ReleaseNotes(markdown: _release.notes),
              ),
            ),
          ),
          if (_release.pageUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            _GitHubLink(url: _release.pageUrl),
          ],
        ];
      case _Phase.downloading:
        final percent = download?.percent ?? 0;
        return [
          LinearProgressIndicator(
            value: percent == 0 ? null : percent / 100,
            color: AppColors.accent,
            backgroundColor: AppColors.divider,
          ),
          const SizedBox(height: 10),
          Text(
            download?.paused == true
                ? 'Paused, waiting for a connection…'
                : percent == 0
                ? 'Starting the download…'
                : 'Downloading… $percent%',
            style: muted,
          ),
          const SizedBox(height: 4),
          Text(
            'You can keep using Cura. It carries on in the background.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.faint),
          ),
        ];
      case _Phase.verifying:
        return [
          const LinearProgressIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.divider,
          ),
          const SizedBox(height: 10),
          Text('Checking the download…', style: muted),
        ];
      case _Phase.ready:
        return [
          Text(
            'Downloaded and checked. Android will ask you to confirm the '
            'update. Your records stay as they are.',
            style: muted,
          ),
        ];
      case _Phase.needsPermission:
        return [
          Text(
            'Android needs your permission for Cura to install updates. Allow '
            'it on the next screen, then come back here.',
            style: muted,
          ),
        ];
      case _Phase.failed:
        return [
          Text(
            _error ?? 'Something went wrong. Try again.',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.destructive,
            ),
          ),
          if (_release.pageUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            _GitHubLink(url: _release.pageUrl),
          ],
        ];
    }
  }

  List<Widget> _actions() {
    Widget close(String label) => TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(label),
    );
    Widget primary(String label, VoidCallback onPressed) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      child: Text(label),
    );
    return switch (_phase) {
      _Phase.available => [
        close('Later'),
        primary('Update', () => unawaited(_download())),
      ],
      _Phase.downloading => [
        TextButton(
          onPressed: () async {
            await ref.read(modelDownloaderProvider).cancel(kUpdateDownload);
            _set(_Phase.available);
          },
          child: const Text('Cancel'),
        ),
        primary('Hide', () => Navigator.of(context).pop()),
      ],
      _Phase.verifying => const [],
      _Phase.ready => [
        close('Later'),
        primary('Install', () => unawaited(_install())),
      ],
      _Phase.needsPermission => [
        close('Later'),
        primary('Allow', () => unawaited(openInstallPermission())),
      ],
      _Phase.failed => [
        close('Close'),
        primary('Try again', () => unawaited(_download())),
      ],
    };
  }
}

class _GitHubLink extends StatelessWidget {
  const _GitHubLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => unawaited(openLink(url)),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Open on GitHub',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.accent,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Release notes
// ───────────────────────────────────────────────────────────────────────────

enum NoteKind { heading, bullet, paragraph }

/// One block of a release body.
class NoteBlock {
  const NoteBlock(this.kind, this.text);

  final NoteKind kind;

  /// Wrapped lines rejoined; may still carry **bold** marks.
  final String text;

  @override
  String toString() => '${kind.name}: $text';
}

/// Release-body markdown: headings, bullets, bold, wraps.
List<NoteBlock> parseReleaseNotes(String markdown) {
  final blocks = <NoteBlock>[];
  NoteKind? kind;
  final buf = StringBuffer();

  void close() {
    final text = _plain(buf.toString().trim());
    if (kind != null && text.isNotEmpty) blocks.add(NoteBlock(kind!, text));
    kind = null;
    buf.clear();
  }

  for (final raw in markdown.replaceAll('\r', '').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      close();
      continue;
    }
    final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line);
    if (heading != null) {
      close();
      kind = NoteKind.heading;
      buf.write(heading.group(1));
      close();
      continue;
    }
    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      close();
      kind = NoteKind.bullet;
      buf.write(bullet.group(1));
      continue;
    }
    // Continuation or new paragraph.
    if (kind == null) {
      kind = NoteKind.paragraph;
    } else {
      buf.write(' ');
    }
    buf.write(line);
  }
  close();
  return blocks;
}

/// Links to their text, code spans to plain.
String _plain(String s) => s
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
    .replaceAll('`', '');

/// A release body, rendered in the app's own type.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodyMedium?.copyWith(
      color: AppColors.ink,
      height: 1.45,
    );
    final blocks = parseReleaseNotes(markdown);
    if (blocks.isEmpty) {
      return Text('No release notes.', style: body);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0
                  ? 0
                  : blocks[i].kind == NoteKind.heading
                  ? 16
                  : 8,
            ),
            child: switch (blocks[i].kind) {
              NoteKind.heading => Text(
                blocks[i].text,
                style: textTheme.titleSmall?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              NoteKind.bullet => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: body),
                  Expanded(child: _rich(blocks[i].text, body)),
                ],
              ),
              NoteKind.paragraph => _rich(blocks[i].text, body),
            },
          ),
      ],
    );
  }

  /// **bold** runs in weight 700.
  Widget _rich(String text, TextStyle? style) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(
        TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
