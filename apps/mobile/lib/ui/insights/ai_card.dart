import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../cloud_providers.dart';
import '../../features/ai/ai_input_builder.dart';
import '../../features/ai/ai_service.dart';
import '../../features/auth/domain/auth_models.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../providers.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';

/// "Generate insight" / "Roast me". Not a chat: one request, one short answer,
/// built only from this month's totals.
class AiCard extends ConsumerStatefulWidget {
  const AiCard({super.key});

  @override
  ConsumerState<AiCard> createState() => _AiCardState();
}

class _AiCardState extends ConsumerState<AiCard> {
  bool _busy = false;
  AiResult? _result;
  AiError? _error;

  Future<void> _run(AiKind kind) async {
    final service = ref.read(aiServiceProvider);
    if (service == null) return;
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final data = await ref.read(appDataProvider.future);
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final stats = AiPeriodStats.thisMonth(
      days: data.days,
      sessions: data.sessions,
      calc: ref.read(energyCalcProvider),
      currency: settings.currency,
      now: DateTime.now(),
    );
    if (stats.isEmpty) {
      setState(() {
        _result = null;
        _error = null;
      });
      _snack(l.aiNoData);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await service.generate(kind, stats, languageCode: lang);
      if (mounted) setState(() => _result = r);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _errorText(AiError e) {
    final l = context.l10n;
    return switch (e) {
      AiError.notSignedIn => l.aiSignInHint,
      AiError.quotaExceeded => l.aiQuotaExceeded,
      AiError.offline => l.aiOffline,
      AiError.unavailable => l.aiUnavailable,
      AiError.invalidInput || AiError.other => l.aiError,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(aiServiceProvider) == null) return const SizedBox.shrink();
    final l = context.l10n;
    final signedIn = ref.watch(authControllerProvider).value is SignedIn;
    final theme = Theme.of(context);
    return WbCard(
      gradient: accentWash(context, WbColors.byte),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            container: true,
            child: Text(l.aiTitle, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          if (!signedIn)
            Semantics(
              container: true,
              child: WordFitText(l.aiSignInHint,
                  style: theme.textTheme.bodyMedium),
            )
          else ...[
            Semantics(
              container: true,
              child: WordFitText(l.aiSent, style: theme.textTheme.labelMedium),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                onPressed: _busy ? null : () => _run(AiKind.insight),
                child: Text(l.aiGenerateInsight),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(AiKind.roast),
                child: Text(l.aiGenerateRoast),
              ),
            ]),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(semanticsLabel: l.a11yLoading),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            // Announced as soon as it appears.
            Semantics(
              liveRegion: true,
              child: WordFitText(_errorText(_error!),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            // One announcement (a live region) with the whole answer.
            MergeSemantics(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The answer is free text: no word of it may be cut in half.
                    WordFitText('${_result!.emoji}  ${_result!.title}',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    WordFitText(_result!.message,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                    const SizedBox(height: 8),
                    WordFitText(l.aiRemaining(_result!.remainingToday),
                        style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
