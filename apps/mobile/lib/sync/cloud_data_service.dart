// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import '../api/api_factory.dart';
import '../api/api_failure.dart';
import '../api/session_manager.dart';
import '../generated/api/api.dart' as api;

/// What the account holds in the cloud, and the three things its owner can do about it without deleting the account
/// (`docs/CLOUD_DATA.md`): take a copy, erase the synced data, remove a device.
///
/// Every call is pinned to the account that was signed in when it started (F-13): if another account signs in while a
/// request is on the wire, it is not sent with that account's token and an answer that arrives later is dropped
/// ([StaleAccountException]). Failures are [ApiFailure]s, the type the screens already know how to word.
class CloudDataService {
  CloudDataService({required this.apis, required this.sessions});

  final ApiFactory apis;
  final SessionManager sessions;

  Future<T> _pinned<T>(Future<T> Function(String token) call) async {
    final userId = (await sessions.current())?.user.id;
    if (userId == null) throw const ApiFailure(ApiFailureKind.unauthorized);
    final epoch = sessions.accountEpoch;
    final result = await sessions
        .authorized((token) => guarded(() => call(token)), userId: userId);
    if (sessions.accountEpoch != epoch) throw const StaleAccountException();
    return result;
  }

  /// The devices this account has registered, oldest first.
  Future<List<api.DeviceDto>> devices() => _pinned((token) async {
        final list = await api.DevicesApi(apis.bearer(token)).apiV1DevicesGet();
        return list?.devices ?? const <api.DeviceDto>[];
      });

  /// Removes one device and, by cascade, the days it uploaded. The data on the phone itself is not touched.
  Future<void> removeDevice(String deviceId) => _pinned((token) async {
        await api.DevicesApi(apis.bearer(token)).apiV1DevicesIdDelete(deviceId);
      });

  /// Erases the synced days, summaries and AI records of the account. The account, its settings and its sessions stay.
  /// [withDevices] also removes the registered devices.
  Future<api.CloudDataDeleteResponse> eraseCloudData(
          {bool withDevices = false}) =>
      _pinned((token) async {
        final r = await api.AccountApi(apis.bearer(token))
            .apiV1MeCloudDataDelete(devices: withDevices ? 'true' : 'false');
        if (r == null) throw const ApiFailure(ApiFailureKind.server);
        return r;
      });

  /// The complete export document exactly as the server sent it (JSON bytes): saved and shared as it is, never re-encoded
  /// by the generated model, which would drop whatever a newer server adds.
  Future<List<int>> exportDocument() => _pinned((token) async {
        final response = await api.AccountApi(apis.bearer(token))
            .apiV1MeExportGetWithHttpInfo();
        if (response.statusCode >= HttpStatus.badRequest) {
          throw api.ApiException(response.statusCode, response.body);
        }
        return response.bodyBytes;
      });

  /// `wattbyte-cloud-export-YYYY-MM-DD.json`, the local date of the export.
  static String exportFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'wattbyte-cloud-export-${now.year}-${two(now.month)}-${two(now.day)}.json';
  }
}

/// Another account signed in while a request for the previous one was running; its answer is not used.
class StaleAccountException implements Exception {
  const StaleAccountException();
  @override
  String toString() => 'the signed-in account changed during the request';
}
