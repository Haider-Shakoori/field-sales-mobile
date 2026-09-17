import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_l10n.dart';
import '../../state/app_state.dart';

/// Credential entry screen shown when no session is restored.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  String? _errorCode;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorCode = null;
    });
    final appState = context.read<AppState>();
    try {
      await appState.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorCode = appState.friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.storefront, size: 64, color: scheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    l10n.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: l10n.email,
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
                    validator: (value) =>
                        value == null || !value.contains('@') ? '' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: l10n.password,
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? '' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_errorCode != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage(l10n, _errorCode!),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.signInButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _errorMessage(AppL10n l10n, String code) {
    switch (code) {
      case 'INVALID_CREDENTIALS':
        return l10n.invalidCredentials;
      case 'DEACTIVATED':
        return l10n.accountDeactivated;
      case 'DEVICE_REVOKED':
        return l10n.deviceRevoked;
      case 'UPDATE_REQUIRED':
        return l10n.updateRequiredMessage;
      case 'NETWORK':
        return l10n.networkError;
      default:
        return l10n.unexpectedError;
    }
  }
}
