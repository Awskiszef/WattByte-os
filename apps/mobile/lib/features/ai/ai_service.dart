import '../../api/api_factory.dart';
import '../../api/api_failure.dart';
import '../../api/session_manager.dart';
import '../../generated/api/api.dart' as api;
import '../auth/domain/auth_models.dart';
import 'ai_input_builder.dart';

enum AiKind { insight, roast }

enum AiError {
  notSignedIn,
  quotaExceeded,
  unavailable,
  offline,
  invalidInput,
  other
}

class AiException implements Exception {
  const AiException(this.error);

  final AiError error;

  @override
  String toString() => 'AiException(${error.name})';
}

class AiResult {
  const AiResult({
    required this.title,
    required this.message,
    required this.emoji,
    required this.severity,
    required this.provider,
    required this.model,
    required this.remainingToday,
  });

  final String title;
  final String message;
  final String emoji;

  /// `info`, `notice` or `celebrate`.
  final String severity;
  final String provider;
  final String model;
  final int remainingToday;
}

/// Flutter -> WattByte API -> AI Gateway -> provider -> back. The app never holds
/// a provider key and never sends anything but the aggregates in [AiPeriodStats].
class AiService {
  AiService({required this.apis, required this.sessions});

  final ApiFactory apis;
  final SessionManager sessions;

  Future<AiResult> generate(AiKind kind, AiPeriodStats stats,
      {required String languageCode}) async {
    final input = api.AIInput(
      period: stats.period,
      periodType: api.AIInputPeriodTypeEnum.month,
      mobileDataGb: stats.mobileDataGb,
      wifiDataGb: stats.wifiDataGb,
      totalDataGb: stats.totalDataGb,
      chargingSessions: stats.chargingSessions,
      batteryEnergyKwh: stats.batteryEnergyKwh,
      wallEnergyKwh: stats.wallEnergyKwh,
      electricityCost: stats.electricityCost,
      currency: stats.currency,
      previousPeriodChangePercent: stats.previousPeriodChangePercent,
      wifiSharePercent: stats.wifiSharePercent,
      averageSessionMah: stats.averageSessionMah,
    );
    final request = api.AIGenerateRequest(
      mode: kind == AiKind.roast
          ? api.AIGenerateRequestModeEnum.roast
          : api.AIGenerateRequestModeEnum.normal,
      locale: languageCode == 'pl'
          ? api.AIGenerateRequestLocaleEnum.pl
          : api.AIGenerateRequestLocaleEnum.en,
      input: input,
    );
    try {
      final res = await sessions.authorized((token) => guarded(() async {
            final ai = api.AiApi(apis.bearer(token));
            final r = kind == AiKind.roast
                ? await ai.apiV1AiRoastPost(request)
                : await ai.apiV1AiInsightPost(request);
            if (r == null) throw const ApiFailure(ApiFailureKind.server);
            return r;
          }, timeout: const Duration(seconds: 90)));
      return AiResult(
        title: res.output.title,
        message: res.output.message,
        emoji: res.output.emoji,
        severity: res.output.severity.toString(),
        provider: res.provider,
        model: res.model,
        remainingToday: res.remainingToday,
      );
    } on AuthException {
      throw const AiException(AiError.notSignedIn);
    } on ApiFailure catch (f) {
      throw AiException(switch (f.kind) {
        ApiFailureKind.unauthorized => AiError.notSignedIn,
        ApiFailureKind.rateLimited when f.code == 'ai_quota_exceeded' =>
          AiError.quotaExceeded,
        ApiFailureKind.rateLimited => AiError.unavailable,
        ApiFailureKind.network || ApiFailureKind.timeout => AiError.offline,
        ApiFailureKind.badRequest => AiError.invalidInput,
        ApiFailureKind.server => AiError.unavailable,
        _ => AiError.other,
      });
    }
  }
}
