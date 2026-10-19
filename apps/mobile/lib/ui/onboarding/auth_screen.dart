import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../features/auth/domain/auth_models.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_form.dart';
import '../settings/flow_widgets.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';

/// Create account / Sign in. On success the start-up gate replaces the whole
/// stack with the device setup, so this screen only has to pop itself.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.register});

  final bool register;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late bool _register = widget.register;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    ref.listen(authControllerProvider, (_, next) {
      if (next.value is SignedIn && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FlowHeading(_register ? l.authCreateTitle : l.authSignInTitle,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(l.authWhyAccount,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: mutedOf(context), height: 1.4)),
              const SizedBox(height: 24),
              WbCard(
                gradient: accentWash(context, WbColors.byte),
                child: AuthForm(
                  register: _register,
                  onModeChanged: (v) => setState(() => _register = v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
