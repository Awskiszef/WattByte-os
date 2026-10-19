import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../core/error_log.dart';

/// Creates the periodic timer; tests pass a fake that they fire by hand.
typedef PeriodicTimerFactory = Timer Function(
    Duration period, void Function(Timer timer) callback);

/// The foreground refresh loop: while the app is open, signed in and on screen it
/// calls [onTick] every [interval] (60 s) so "Today" and a running charge stay
/// live. It used to be a bare `Timer.periodic` inside the shell widget; this class
/// makes the rules explicit and testable without a widget or real time:
///
/// * **One timer at most.** `start`, `resume` and `onAccountChanged` can be called
///   in any order and any number of times; the timer is created only when the loop
///   is wanted AND the app is in the foreground, and never twice.
/// * **Paused in the background.** `hidden`, `paused` and `detached` cancel the
///   timer; `resumed` restarts it and refreshes at once. `inactive` (an incoming call
///   sheet, the app switcher) keeps it, the screen is still on.
/// * **Stopped when the account goes away.** [onAccountChanged] with null (sign-out,
///   account deleted) cancels the timer; a different account restarts it with a fresh
///   timer, so nothing of the previous account's schedule lingers.
/// * **Stopped on [dispose]**, after which nothing can start it again and no tick is
///   delivered.
/// * **No pile-up.** A tick that arrives while the previous one is still running is
///   skipped, and a failing [onTick] is reported ([reportError]) instead of becoming an
///   unhandled asynchronous error.
///
/// What a tick does (collect, queue, sync) is not decided here; the sync it may
/// trigger has its own interval and backoff (`SyncService.syncIfDue`).
class ForegroundRefresh {
  ForegroundRefresh({
    required this.onTick,
    this.interval = const Duration(seconds: 60),
    PeriodicTimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.periodic;

  final Future<void> Function() onTick;
  final Duration interval;
  final PeriodicTimerFactory _timerFactory;

  Timer? _timer;
  bool _wanted = false;
  bool _foreground = true;
  bool _disposed = false;
  bool _ticking = false;
  String? _accountId;

  /// A timer is alive right now.
  bool get isRunning => _timer?.isActive ?? false;

  /// The loop has been started (and not stopped), whether or not the app is in the foreground.
  bool get isWanted => _wanted && !_disposed;

  /// The account the loop is running for, when it was told ([onAccountChanged]).
  String? get accountId => _accountId;

  /// Starts the loop (without an immediate tick: the caller refreshes once itself).
  void start() {
    if (_disposed) return;
    _wanted = true;
    _apply();
  }

  /// Stops the loop until [start] or [onAccountChanged] with an account.
  void stop() {
    _wanted = false;
    _accountId = null;
    _apply();
  }

  /// The signed-in account changed: null stops the loop (signed out, account
  /// deleted), the same id is a no-op, another id restarts it with a fresh timer.
  void onAccountChanged(String? accountId) {
    if (_disposed) return;
    if (accountId == null) {
      stop();
      return;
    }
    if (_wanted && accountId == _accountId) return;
    _accountId = accountId;
    _wanted = true;
    _cancel();
    _apply();
  }

  void pause() {
    _foreground = false;
    _apply();
  }

  /// Back in the foreground: restarts the timer and refreshes immediately.
  void resume() {
    _foreground = true;
    _apply();
    _tick();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        resume();
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        pause();
    }
  }

  void dispose() {
    _disposed = true;
    _wanted = false;
    _accountId = null;
    _cancel();
  }

  void _apply() {
    final shouldRun = _wanted && _foreground && !_disposed;
    if (shouldRun && _timer == null) {
      _timer = _timerFactory(interval, (_) => _tick());
    } else if (!shouldRun) {
      _cancel();
    }
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    if (!_wanted || !_foreground || _disposed || _ticking) return;
    _ticking = true;
    unawaited(() async {
      try {
        await onTick();
      } catch (e, st) {
        reportError(e, st, 'foreground refresh');
      } finally {
        _ticking = false;
      }
    }());
  }
}
