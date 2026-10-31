// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One recorded HTTP request.
class Recorded {
  Recorded(this.method, this.path, this.headers, this.body, [this.query = '']);

  /// The raw query string (`devices=true`), empty when there is none.
  final String query;

  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, dynamic>? body;

  String? get bearer => headers['authorization']?.replaceFirst('Bearer ', '');
}

typedef Responder = http.Response Function(Recorded r);

/// A scriptable stand-in for the WattByte API (no network involved).
class FakeBackend {
  final List<Recorded> requests = [];
  final Map<String, Responder> routes = {};

  /// When set, every request fails like a lost connection.
  bool offline = false;

  late final MockClient client = MockClient((request) async {
    if (offline) throw const SocketException('offline');
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    final r = Recorded(request.method, request.url.path, request.headers, body,
        request.url.query);
    requests.add(r);
    final route = routes['${r.method} ${r.path}'];
    if (route == null) return http.Response('{}', 404);
    return route(r);
  });

  List<Recorded> where(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).toList();

  static http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  static http.Response error(int status, String code, [String? message]) =>
      json({
        'error': {'code': code, 'message': message ?? code}
      }, status);

  /// A `DeviceDto` as the API sends it: ALL FOURTEEN keys are always present
  /// (the schema requires them), the battery ones `null` while nothing is
  /// stored. [battery] overrides the seven battery keys (see [batteryKeys]).
  static Map<String, dynamic> device(
    String id, {
    String installationId = 'xxxxxxxx',
    String platform = 'android',
    String? model,
    String? modelIdentifier,
    Map<String, Object?> battery = const {},
  }) {
    for (final key in battery.keys) {
      if (!batteryKeys.contains(key)) {
        throw ArgumentError.value(
            key, 'battery', 'not a DeviceDto battery key');
      }
    }
    return {
      'id': id,
      'installationId': installationId,
      'platform': platform,
      'model': model,
      'modelIdentifier': modelIdentifier,
      for (final key in batteryKeys) key: battery[key],
      'createdAt': '2026-10-13T10:00:00.000Z',
      'lastSeenAt': '2026-10-13T10:00:00.000Z',
    };
  }

  /// The two battery-capacity groups of `POST /devices` / `DeviceDto`
  /// (`docs/BATTERY_CAPACITY.md`): the design capacity of the phone MODEL and
  /// the estimated full-charge capacity of THIS battery. Each is stored
  /// atomically.
  static const designKeys = [
    'designCapacityMah',
    'designCapacityWh',
    'designCapacitySource',
  ];
  static const estimateKeys = [
    'estimatedFullChargeCapacityMah',
    'estimatedFullChargeCapacityWh',
    'fullChargeCapacitySource',
    'fullChargeCapacityConfidence',
  ];
  static const batteryKeys = [...designKeys, ...estimateKeys];

  /// The keys the app sent before the split; no request or response has them
  /// any more.
  static const retiredBatteryKeys = [
    'batteryCapacityMah',
    'batteryCapacityWh',
    'batterySpecificationSource',
  ];
}

/// The device table of the real API (`apps/api/src/database`), per user and
/// installation, with its rules, so a test sees what the server would store
/// and answer.
///
/// * `model` and `modelIdentifier` keep the stored value when a registration
///   leaves them `null` (`COALESCE`).
/// * Each battery group is stored atomically: a registration that gives the
///   group's SOURCE replaces the whole group (its nulls included); with a
///   `null` source the stored group is kept and the sent values are ignored;
///   every field `null` changes nothing.
/// * The cross-field rules of `validateBatteryCapacityGroups` and the ranges
///   of the request schema are 400 `validation` (see [problem]).
class FakeDeviceTable {
  final Map<String, Map<String, dynamic>> _rows = {};
  final Map<String, String> _ids = {};

  /// The stored `DeviceDto` of [installationId] for [userId], or null.
  Map<String, dynamic>? row(String userId, String installationId) =>
      _rows['$userId/$installationId'];

  /// Every stored device of [userId], oldest first.
  List<Map<String, dynamic>> rowsOf(String userId) => [
        for (final e in _rows.entries)
          if (e.key.startsWith('$userId/')) e.value
      ];

  /// `POST /api/v1/devices`: 201 with the stored `DeviceDto`, or 400
  /// `validation`. [deviceId] is the id a NEW row gets; an existing row keeps
  /// its own.
  http.Response register(
      String userId, Map<String, dynamic> body, String deviceId) {
    final bad = problem(body);
    if (bad != null) return FakeBackend.error(400, 'validation', bad);
    final installationId = body['installationId'] as String;
    final key = '$userId/$installationId';
    final stored = _rows[key];
    final next = FakeBackend.device(
      _ids.putIfAbsent(key, () => deviceId),
      installationId: installationId,
      platform: body['platform'] as String,
      model: (body['model'] as String?) ?? stored?['model'] as String?,
      modelIdentifier: (body['modelIdentifier'] as String?) ??
          stored?['modelIdentifier'] as String?,
      battery: {
        for (final (keys, source) in [
          (FakeBackend.designKeys, 'designCapacitySource'),
          (FakeBackend.estimateKeys, 'fullChargeCapacitySource'),
        ])
          for (final k in keys) k: body[source] != null ? body[k] : stored?[k],
      },
    );
    _rows[key] = next;
    return FakeBackend.json(next, 201);
  }

  /// The reason a registration body is refused (HTTP 400 `validation`), or
  /// null when the server accepts it. Mirrors the request schema (ranges) and
  /// `apps/api/src/modules/devices/battery-capacity.ts` (cross-field rules).
  static String? problem(Map<String, dynamic> b) {
    num? number(String k) => b[k] as num?;
    String? text(String k) => b[k] as String?;

    for (final k in ['designCapacityMah', 'estimatedFullChargeCapacityMah']) {
      final v = number(k);
      if (v != null && (!v.isFinite || v < 0.1 || v > 30000)) {
        return '$k must be between 0.1 and 30000';
      }
    }
    for (final k in ['designCapacityWh', 'estimatedFullChargeCapacityWh']) {
      final v = number(k);
      if (v != null && (!v.isFinite || v < 0.001 || v > 200)) {
        return '$k must be between 0.001 and 200';
      }
    }
    const designSources = {
      'manufacturerSpecification',
      'localDeviceDatabase',
      'backendDeviceDatabase',
      'manual',
      'unknown',
    };
    final designSource = text('designCapacitySource');
    if (designSource != null && !designSources.contains(designSource)) {
      return 'designCapacitySource: unknown value $designSource';
    }
    final fullSource = text('fullChargeCapacitySource');
    if (fullSource != null &&
        !const {'androidChargeCounter', 'unknown'}.contains(fullSource)) {
      return 'fullChargeCapacitySource: unknown value $fullSource';
    }
    final confidence = text('fullChargeCapacityConfidence');
    if (confidence != null &&
        !const {'low', 'medium', 'high'}.contains(confidence)) {
      return 'fullChargeCapacityConfidence: unknown value $confidence';
    }

    final designMah = number('designCapacityMah');
    final designWh = number('designCapacityWh');
    final hasDesignNumber = designMah != null || designWh != null;
    if (hasDesignNumber && designSource == null) {
      return 'designCapacityMah and designCapacityWh need a designCapacitySource';
    }
    if (designSource == 'unknown' && hasDesignNumber) {
      return 'designCapacitySource unknown carries no designCapacityMah or designCapacityWh';
    }
    if (designWh != null && designMah == null) {
      return 'designCapacityWh needs designCapacityMah';
    }
    if (designSource != null &&
        designSource != 'unknown' &&
        designMah == null) {
      return 'designCapacitySource $designSource needs designCapacityMah';
    }

    final fullMah = number('estimatedFullChargeCapacityMah');
    final fullWh = number('estimatedFullChargeCapacityWh');
    final hasFullNumber = fullMah != null || fullWh != null;
    if (hasFullNumber && fullSource == null) {
      return 'estimatedFullChargeCapacity values need a fullChargeCapacitySource';
    }
    if (fullSource == 'unknown' && (hasFullNumber || confidence != null)) {
      return 'fullChargeCapacitySource unknown carries no estimate and no confidence';
    }
    if (fullWh != null && fullMah == null) {
      return 'estimatedFullChargeCapacityWh needs estimatedFullChargeCapacityMah';
    }
    if (fullSource == 'androidChargeCounter' && fullMah == null) {
      return 'fullChargeCapacitySource androidChargeCounter needs estimatedFullChargeCapacityMah';
    }
    if (confidence != null && fullMah == null) {
      return 'fullChargeCapacityConfidence needs estimatedFullChargeCapacityMah';
    }
    if (fullMah != null && confidence == null) {
      return 'estimatedFullChargeCapacityMah needs a fullChargeCapacityConfidence';
    }
    return null;
  }
}
