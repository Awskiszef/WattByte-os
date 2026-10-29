import '../core/error_log.dart';
import 'dart:convert';

import 'package:wattbyte_system/wattbyte_system.dart';

import '../domain/battery_capacity.dart';

/// What is known about the phone model: its names and its [DesignCapacity].
///
/// The design capacity is the nominal capacity of the model, from a device
/// specification database or the user. It is never a measurement; what this
/// particular battery holds today is an `EstimatedFullChargeCapacity`.
class DeviceSpecification {
  const DeviceSpecification({
    required this.manufacturer,
    required this.model,
    this.modelIdentifier,
    this.nominalVoltage,
    this.design = DesignCapacity.unknown,
  });

  final String manufacturer;
  final String model;
  final String? modelIdentifier;
  final double? nominalVoltage;

  /// Nominal capacity; [DesignCapacity.unknown] when no database knows the model
  /// (never a "typical" guess).
  final DesignCapacity design;

  double? get designCapacityMah => design.mah;
  double? get designCapacityWh => design.wh;
  DesignCapacitySource get designCapacitySource => design.source;
  bool get hasDesignCapacity => design.isKnown;

  static DeviceSpecification unknown(DeviceInfo? info) => DeviceSpecification(
        manufacturer: info?.manufacturer ?? '',
        model: info?.model ?? '',
        modelIdentifier: info?.modelIdentifier,
      );

  Map<String, Object?> toJson() => {
        'manufacturer': manufacturer,
        'model': model,
        'modelIdentifier': modelIdentifier,
        'designCapacityMah': design.mah,
        'designCapacityWh': design.wh,
        'nominalVoltage': nominalVoltage,
        'designCapacitySource': design.source.name,
      };

  /// Reads [toJson]'s output, and also the layout persisted by builds from
  /// before the design / estimated full-charge split (`batteryCapacityMah`,
  /// `batteryCapacityWh`, `source`). Of the legacy sources only `localDatabase`
  /// and `backendDatabase` were published catalog figures and keep a design
  /// capacity; `system`, `estimated`, `manual` and `unknown` were measurements
  /// or carry no provenance and yield none. Never throws: a field of the wrong
  /// type is treated as absent.
  static DeviceSpecification fromJson(Map<String, dynamic> j) {
    String? str(String key) {
      final v = j[key];
      return v is String ? v : null;
    }

    double? number(String key) {
      final v = j[key];
      return v is num ? v.toDouble() : null;
    }

    final DesignCapacity design;
    if (j.containsKey('designCapacitySource')) {
      design = DesignCapacity(
        mah: number('designCapacityMah'),
        wh: number('designCapacityWh'),
        source: DesignCapacitySource.tryParse(str('designCapacitySource')) ??
            DesignCapacitySource.unknown,
      );
    } else {
      final legacySource = switch (str('source')) {
        'localDatabase' => DesignCapacitySource.localDeviceDatabase,
        'backendDatabase' => DesignCapacitySource.backendDeviceDatabase,
        _ => DesignCapacitySource.unknown,
      };
      design = DesignCapacity(
        mah: number('batteryCapacityMah'),
        wh: number('batteryCapacityWh'),
        source: legacySource,
      );
    }
    return DeviceSpecification(
      manufacturer: str('manufacturer') ?? '',
      model: str('model') ?? '',
      modelIdentifier: str('modelIdentifier'),
      nominalVoltage: number('nominalVoltage'),
      design: design,
    );
  }

  @override
  String toString() =>
      'DeviceSpecification($manufacturer $model/$modelIdentifier, $design)';
}

/// The bundled catalog (`assets/device_specs/devices.json`, same file as
/// `packages/device-specs`). Exact identifiers first, then prefixes.
class DeviceCatalog {
  DeviceCatalog(this._entries, {required this.version});

  final List<Map<String, dynamic>> _entries;
  final String version;

  static DeviceCatalog fromJson(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return DeviceCatalog(
      (j['devices'] as List).cast<Map<String, dynamic>>(),
      version: (j['version'] as String?) ?? '',
    );
  }

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// The catalog entry for [identifier], whose capacity is a design capacity
  /// from [source] (the bundled catalog by default).
  DeviceSpecification? lookup(String identifier,
      {DesignCapacitySource source =
          DesignCapacitySource.localDeviceDatabase}) {
    final id = _norm(identifier);
    if (id.isEmpty) return null;
    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final e in _entries) {
      final ids = (e['identifiers'] as List?)?.cast<String>() ?? const [];
      if (ids.any((i) => _norm(i) == id)) {
        best = e;
        bestScore = 1 << 30;
        break;
      }
      for (final p in (e['identifierPrefixes'] as List?)?.cast<String>() ??
          const <String>[]) {
        final np = _norm(p);
        if (id.startsWith(np) && np.length > bestScore) {
          best = e;
          bestScore = np.length;
        }
      }
    }
    if (best == null) return null;
    final design = DesignCapacity(
      mah: (best['designCapacityMah'] as num).toDouble(),
      wh: (best['designCapacityWh'] as num?)?.toDouble(),
      source: source,
    );
    final mah = design.mah;
    final wh = design.wh;
    return DeviceSpecification(
      manufacturer: best['manufacturer'] as String,
      model: best['model'] as String,
      modelIdentifier: identifier.trim(),
      nominalVoltage: mah == null || wh == null
          ? null
          : (wh / (mah / 1000) * 100).round() / 100,
      design: design,
    );
  }
}

/// Resolves the model's design capacity in this order and stops at the first
/// hit ([DesignCapacity.resolve]):
///
///   1. bundled device catalog                         -> `localDeviceDatabase`
///   2. the API's copy of the catalog (newer models),
///      cached for offline launches                    -> `backendDeviceDatabase`
///   3. nothing                                        -> unknown
///
/// An unknown model has no capacity at all: there is no "typical" figure and
/// the Android charge counter is not consulted (it is the charge currently in
/// the battery, not a capacity; see `FullChargeCapacityEstimator`). iOS and
/// Android behave the same. A manual value entered by the user is handled by the
/// caller (never replaced by automatic detection).
class DeviceSpecificationService {
  DeviceSpecificationService({
    required this.system,
    required this.loadCatalog,
    this.backendLookup,
    this.readCache,
    this.writeCache,
  });

  final WattByteSystem system;

  /// Reads the bundled JSON (rootBundle in the app, a string in tests).
  final Future<String> Function() loadCatalog;

  /// `GET /devices/specifications/:identifier`; null when unknown there too. Throws when offline.
  final Future<DeviceSpecification?> Function(String identifier)? backendLookup;
  final String? Function()? readCache;
  final Future<void> Function(String json)? writeCache;

  Future<DeviceSpecification> detect() async {
    DeviceInfo? info;
    try {
      info = await system.deviceInfo();
    } catch (e, st) {
      // The platform side failed (not "offline"): recorded, and the setup carries on without a model.
      reportError(e, st, 'device info');
      info = null;
    }
    final identifier = info?.modelIdentifier ?? '';
    if (identifier.isEmpty) return DeviceSpecification.unknown(info);

    DeviceSpecification? local;
    try {
      local = DeviceCatalog.fromJson(await loadCatalog()).lookup(identifier);
    } catch (e, st) {
      // A broken asset must not stop the setup; the other sources still apply. It is a defect of the build, so it is recorded.
      reportError(e, st, 'device catalog asset');
    }

    // The network is only asked when the bundled catalog does not know the model.
    final backend = local != null && local.hasDesignCapacity
        ? null
        : await _backend(identifier);

    final design = DesignCapacity.resolve(
      local: local?.design,
      backend: backend?.design,
    );
    if (!design.isKnown) return DeviceSpecification.unknown(info);
    return local != null && local.design == design ? local : backend!;
  }

  /// The backend's specification for [identifier]: the cached one, otherwise a
  /// lookup (cached on success). Null when unknown there, offline or failing.
  Future<DeviceSpecification?> _backend(String identifier) async {
    final cached = _cached(identifier);
    if (cached != null) return cached;

    final remote = backendLookup;
    if (remote == null) return null;
    try {
      final spec = await remote(identifier);
      if (spec == null || !spec.hasDesignCapacity) return null;
      final stored = DeviceSpecification(
        manufacturer: spec.manufacturer,
        model: spec.model,
        modelIdentifier: identifier,
        nominalVoltage: spec.nominalVoltage,
        design: DesignCapacity(
          mah: spec.designCapacityMah,
          wh: spec.designCapacityWh,
          source: DesignCapacitySource.backendDeviceDatabase,
        ),
      );
      await writeCache?.call(jsonEncode(stored.toJson()));
      return stored;
    } catch (_) {
      // Offline: the catalog may know the model on a later launch.
      return null;
    }
  }

  DeviceSpecification? _cached(String identifier) {
    final raw = readCache?.call();
    if (raw == null) return null;
    try {
      final spec =
          DeviceSpecification.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (spec.modelIdentifier != identifier || !spec.hasDesignCapacity) {
        return null;
      }
      // Whatever the cache claims, only the backend writes it: it is relabelled
      // so a tampered entry can never come back as `manual` (which is sticky).
      return DeviceSpecification(
        manufacturer: spec.manufacturer,
        model: spec.model,
        modelIdentifier: spec.modelIdentifier,
        nominalVoltage: spec.nominalVoltage,
        design: DesignCapacity(
          mah: spec.designCapacityMah,
          wh: spec.designCapacityWh,
          source: DesignCapacitySource.backendDeviceDatabase,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
