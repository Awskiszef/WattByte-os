// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/error_log.dart';
import '../domain/auth_models.dart';

/// The iOS Keychain outlives the app: a session written by an earlier install is still there after the app was deleted and
/// installed again, so the "new" app would sign the previous account straight back in (F-19). The preferences, the database
/// and everything else in the app's container are wiped with the app, so their absence is the sign of a fresh install.
///
/// Rule: no install marker yet AND no preferences at all (nothing an earlier run of THIS install could have written) = a
/// fresh install: whatever session the store holds belongs to a previous install and is removed. An existing install that
/// is only updated to this version has preferences and keeps its session; it just gets the marker.
const String kInstallMarkerKey = 'wb.installMarker';

/// Returns true when a session of a previous install was removed.
Future<bool> clearSessionOfPreviousInstall({
  required SharedPreferences prefs,
  required TokenStore tokens,
}) async {
  if (prefs.containsKey(kInstallMarkerKey)) return false;
  final fresh = prefs.getKeys().isEmpty;
  var cleared = false;
  if (fresh) {
    try {
      if (await tokens.read() != null) {
        await tokens.clear();
        cleared = true;
      }
    } catch (e, st) {
      // A store that cannot be read or cleared must not stop the app from starting; the session restore deals with it.
      reportError(e, st, 'install marker');
    }
  }
  await prefs.setString(
      kInstallMarkerKey, DateTime.now().toUtc().toIso8601String());
  return cleared;
}
