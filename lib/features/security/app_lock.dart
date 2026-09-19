import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_colors.dart';
import '../../core/widgets/circle_icon_badge.dart';

/// Opt-in biometric app lock (off by default). Auth is fully on-device.

/// Persisted flag: require unlock to open Cura?
const kAppLockKey = 'cura_app_lock';

/// Lets [AppLockGate] react to the Settings toggle without a restart.
final ValueNotifier<bool> appLockEnabledNotifier = ValueNotifier<bool>(false);

/// Lock state: null unknown, true covered. UI waits on [untilUnlocked].
final ValueNotifier<bool?> appLockedNotifier = ValueNotifier<bool?>(null);

/// Completes once the app is open and not behind the lock screen.
Future<void> untilUnlocked() {
  if (appLockedNotifier.value == false) return Future.value();
  final done = Completer<void>();
  void check() {
    if (appLockedNotifier.value == false && !done.isCompleted) {
      appLockedNotifier.removeListener(check);
      done.complete();
    }
  }

  appLockedNotifier.addListener(check);
  return done.future;
}

/// > 0 while an in-app flow has a system activity open (camera scan, file
/// picker). Returning from those is our own flow, not the user leaving.
int _externalFlowDepth = 0;
bool get appLockSuppressed => _externalFlowDepth > 0;

/// Runs [action] (which opens a system activity) without the return from it
/// tripping the lock.
Future<T> withoutAppLock<T>(Future<T> Function() action) async {
  _externalFlowDepth++;
  try {
    return await action();
  } finally {
    // The resume event can land just after this returns; wait a beat before
    // re-arming so it isn't mistaken for the user coming back.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_externalFlowDepth > 0) _externalFlowDepth--;
    });
  }
}

Future<bool> isAppLockEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getBool(kAppLockKey) ?? false;
  appLockEnabledNotifier.value = value;
  return value;
}

Future<void> setAppLockEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kAppLockKey, value);
  appLockEnabledNotifier.value = value;
}

/// Thin wrapper over [LocalAuthentication] so the rest of the app never touches
/// the plugin directly.
class BiometricAuth {
  BiometricAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True if the phone has any secure lock (biometric or PIN/pattern) to prompt.
  Future<bool> canAuthenticate() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompts to unlock (biometric, or device PIN/pattern as fallback). Returns
  /// false on cancel. Lets the user in if the phone has no lock left to check, so
  /// they can't be locked out of their own records.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException catch (e) {
      if (e.code == auth_error.notAvailable ||
          e.code == auth_error.notEnrolled ||
          e.code == auth_error.passcodeNotSet) {
        return true; // no lock to check → let them in
      }
      return false;
    }
  }
}

/// Accent fingerprint in a mint disc. Used by onboarding and [LockScreen].
class FingerprintBadge extends StatelessWidget {
  const FingerprintBadge({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CircleIconBadge(icon: Icons.fingerprint, size: size);
}

/// Full-screen opaque cover shown while the app is locked. Calls [onUnlock] to
/// (re)trigger the biometric prompt.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.canvas,
      ),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const FingerprintBadge(),
                      const SizedBox(height: 24),
                      Text('Cura is locked', style: textTheme.headlineMedium),
                      const SizedBox(height: 10),
                      Text(
                        'Unlock to open your records.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: onUnlock,
                    icon: const Icon(Icons.lock_open_outlined, size: 20),
                    label: const Text('Unlock'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.canvas,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        fontVariations: [FontVariation('wght', 500)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] and shows the lock on launch and on return from background.
/// A no-op when the flag is off.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child, this.auth});

  final Widget child;

  /// Tests pass a fake; the app uses the device's own.
  @visibleForTesting
  final BiometricAuth? auth;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  late final BiometricAuth _auth = widget.auth ?? BiometricAuth();
  // null until prefs load — cover child meanwhile.
  bool? _enabled;
  bool _locked = false;
  bool _authing = false; // true while a prompt is open, so it can't fire twice

  /// Syncs [_locked] and [appLockedNotifier].
  void _setLocked(bool locked) {
    appLockedNotifier.value = locked;
    if (mounted && locked != _locked) setState(() => _locked = locked);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appLockEnabledNotifier.addListener(_onEnabledChanged);
    _load();
  }

  @override
  void dispose() {
    appLockEnabledNotifier.removeListener(_onEnabledChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await isAppLockEnabled();
    if (!mounted) return;
    setState(() => _enabled = enabled);
    _setLocked(enabled);
    if (enabled) _tryUnlock();
  }

  // Sync the cached flag with the Settings toggle; turning it off drops the cover.
  void _onEnabledChanged() {
    final enabled = appLockEnabledNotifier.value;
    if (!mounted || _enabled == null || enabled == _enabled) return;
    setState(() => _enabled = enabled);
    if (!enabled) _setLocked(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ignore transitions our own prompt or an in-app picker/scanner causes.
    if (_authing || _enabled != true || appLockSuppressed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Re-lock and hide records from the app-switcher preview.
      if (!_locked) _setLocked(true);
    } else if (state == AppLifecycleState.resumed && _locked) {
      _tryUnlock();
    }
  }

  Future<void> _tryUnlock() async {
    if (_authing) return;
    _authing = true;
    try {
      final ok = await _auth.authenticate('Unlock Cura to open your records');
      if (ok) _setLocked(false);
    } finally {
      _authing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_enabled == null)
          const Positioned.fill(child: ColoredBox(color: AppColors.canvas))
        else if (_locked)
          LockScreen(onUnlock: _tryUnlock),
      ],
    );
  }
}
