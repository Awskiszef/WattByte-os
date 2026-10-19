import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../domain/auth_models.dart';
import 'auth_controller.dart';

/// Email + password form driving [AuthController]; used by the start-up flow
/// (Create account / Sign in) and by the Account screen after sign-out.
class AuthForm extends ConsumerStatefulWidget {
  const AuthForm({super.key, required this.register, this.onModeChanged});

  /// True = create an account, false = sign in.
  final bool register;
  final ValueChanged<bool>? onModeChanged;

  @override
  ConsumerState<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<AuthForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  /// The last failure belongs to the form as it was submitted; switching between
  /// sign-in and registration must not keep showing it.
  bool _showError = true;

  @override
  void didUpdateWidget(covariant AuthForm old) {
    super.didUpdateWidget(old);
    if (old.register != widget.register) {
      _showError = false;
      _password.clear();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider.notifier);
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _showError = true);
    if (widget.register) {
      await auth.signUpWithEmail(email, password);
    } else {
      await auth.signInWithEmail(email, password);
    }
    if (ref.read(authControllerProvider).value is SignedIn && mounted) {
      // The form is reused after sign-out: it must start empty.
      _password.clear();
      _email.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final state = auth.value;
    final busy = auth.isLoading;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            enabled: !busy,
            decoration: InputDecoration(labelText: l.email),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            textInputAction: TextInputAction.done,
            enabled: !busy,
            autofillHints: [
              widget.register
                  ? AutofillHints.newPassword
                  : AutofillHints.password
            ],
            decoration: InputDecoration(
                labelText: l.password,
                // The hint must never be cut off at large text sizes.
                helperMaxLines: 4,
                helperText: widget.register ? l.passwordHint : null),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: busy
                // The button keeps its name while it works, and says so.
                ? Semantics(
                    label: widget.register ? l.signUp : l.signIn,
                    hint: l.authBusy,
                    child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : Text(widget.register ? l.signUp : l.signIn,
                    textAlign: TextAlign.center),
          ),
          if (widget.onModeChanged != null)
            TextButton(
              onPressed:
                  busy ? null : () => widget.onModeChanged!(!widget.register),
              child: Text(widget.register ? l.haveAccount : l.noAccount,
                  textAlign: TextAlign.center),
            ),
          if (state is AuthFailure && _showError) ...[
            const SizedBox(height: 4),
            // A live region: a screen reader announces the failure when it
            // appears, without the user having to find it.
            Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.error_outline_rounded,
                        size: 18, color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(authErrorText(context, state.error),
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                                color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String authErrorText(BuildContext context, AuthError e) {
  final l = context.l10n;
  return switch (e) {
    AuthError.unavailable => l.accountUnavailableTitle,
    AuthError.invalidCredentials => l.authInvalidCredentials,
    AuthError.network => l.authNetworkError,
    AuthError.sessionExpired => l.authSessionExpired,
    AuthError.cancelled => l.cancel,
    AuthError.emailTaken => l.authEmailTaken,
    AuthError.invalidInput => l.authInvalidInput,
    AuthError.rateLimited => l.authRateLimited,
    AuthError.server => l.authServerError,
  };
}
