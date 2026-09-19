import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../settings/settings_view.dart' show SettingsGroup, SettingsRow;
import 'update_check.dart';
import 'update_dialog.dart';

/// Manual check + opt-in daily check.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

/// What this visit's check found.
enum _Result { none, upToDate, available, unreachable }

class _UpdatesScreenState extends State<UpdatesScreen> {
  final _version = installedVersion().catchError((_) => null);
  bool _auto = false;
  bool _loaded = false;
  bool _checking = false;
  var _result = _Result.none;
  AppRelease? _release;

  @override
  void initState() {
    super.initState();
    updateCheckAllowed()
        .then((on) {
          if (mounted) {
            setState(() {
              _auto = on;
              _loaded = true;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _loaded = true);
        });
  }

  /// A check now, ignoring the daily limit.
  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final check = await checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _release = check.release;
      _result = check.release != null
          ? _Result.available
          : check.reached
          ? _Result.upToDate
          : _Result.unreachable;
    });
    await _show();
  }

  Future<void> _show() async {
    final release = _release;
    if (release != null && mounted) await showUpdateDialog(context, release);
  }

  /// Enabling auto-check runs one check immediately.
  Future<void> _toggle(bool on) async {
    setState(() => _auto = on);
    await setUpdateCheckAllowed(on);
    if (!on) return;
    final check = await checkForUpdate(automatic: true);
    if (!mounted || check.release == null) return;
    setState(() {
      _release = check.release;
      _result = _Result.available;
    });
    await _show();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.canvas,
      ),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    color: AppColors.ink,
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: [
                    Text('Updates', style: textTheme.headlineMedium),
                    const SizedBox(height: 16),
                    SettingsGroup(
                      label: 'This phone',
                      rows: [
                        SettingsRow(
                          icon: Icons.info_outline,
                          iconColor: AppColors.secondary,
                          tileColor: AppColors.divider,
                          title: 'Installed version',
                          trailing: FutureBuilder<String?>(
                            future: _version,
                            builder: (context, snapshot) => Text(
                              snapshot.data ?? '',
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.faint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SettingsGroup(
                      label: 'Automatic',
                      rows: [
                        SettingsRow(
                          icon: Icons.update,
                          iconColor: AppColors.accent,
                          tileColor: AppColors.softTint,
                          title: 'Check for updates automatically',
                          subtitle: 'Once a day. Sends none of your records.',
                          trailing: Switch(
                            value: _auto,
                            onChanged: _loaded ? _toggle : null,
                            activeThumbColor: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _checking ? null : _check,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.canvas,
                          disabledBackgroundColor: AppColors.accent.withValues(
                            alpha: 0.5,
                          ),
                          disabledForegroundColor: AppColors.canvas,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            fontVariations: [FontVariation('wght', 500)],
                          ),
                        ),
                        child: Text(
                          _checking ? 'Checking…' : 'Check for updates',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ResultLine(
                      result: _result,
                      release: _release,
                      onView: () => unawaited(_show()),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'A check asks GitHub which version of Cura is the latest. '
                      'It sends none of your records. Like any web request, it '
                      'shows GitHub your IP address. With automatic checking '
                      'off, Cura only checks when you tap the button above.',
                      style: textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    required this.result,
    required this.release,
    required this.onView,
  });

  final _Result result;
  final AppRelease? release;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return switch (result) {
      _Result.none => const SizedBox.shrink(),
      _Result.upToDate => Text(
        'No updates found. You have the latest version.',
        textAlign: TextAlign.center,
        style: style?.copyWith(color: AppColors.secondary),
      ),
      _Result.unreachable => Text(
        'Couldn\'t reach GitHub. Check your connection and try again.',
        textAlign: TextAlign.center,
        style: style?.copyWith(color: AppColors.destructive),
      ),
      _Result.available => Column(
        children: [
          Text(
            'Version ${release!.version} is available.',
            textAlign: TextAlign.center,
            style: style?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton(
            onPressed: onView,
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('View update'),
          ),
        ],
      ),
    };
  }
}
