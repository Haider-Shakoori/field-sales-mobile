import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/api_exception.dart';
import '../state/app_state.dart';
import '../state/attendance_controller.dart';

String friendlyLoginError(Object error) {
  if (error is! ApiException) {
    return 'Unable to sign in right now. Please try again.';
  }

  return switch (error.code) {
    'TENANT_REQUIRED' =>
      'This email is used in more than one company. Enter your Company / Tenant code and try again.',
    'INVALID_CREDENTIALS' =>
      'The email, password, or Company / Tenant code is incorrect.',
    'MOBILE_ROLE_REQUIRED' =>
      'This account is not enabled for the FieldPulse mobile app. Ask your administrator to assign Salesman, Supervisor, or Sales Manager access.',
    'TENANT_SUSPENDED' =>
      'This company account is suspended. Please contact your administrator.',
    'DEVICE_LIMIT_REACHED' =>
      'This account is already active on another device. Ask an administrator to revoke the old device before signing in here.',
    'DEVICE_REVOKED' =>
      'This device has been revoked for this account. Please contact your administrator.',
    'APP_UPGRADE_REQUIRED' =>
      'This FieldPulse version is no longer supported. Update the app and try again.',
    'DEVICE_HEADERS_REQUIRED' =>
      'FieldPulse could not identify this device. Restart the app and try again.',
    'SERVER_ERROR' =>
      'The server could not complete the sign-in request. Please try again. If it continues, contact your administrator.',
    'VALIDATION_ERROR' => error.fieldErrors.values
            .expand((messages) => messages)
            .where((message) => message.trim().isNotEmpty)
            .firstOrNull ??
        'Please check the sign-in details and try again.',
    _ => error.status == null
        ? (error.message.trim().isEmpty
              ? 'No connection to the server. Check your internet connection and try again.'
              : error.message)
        : (error.message.trim().isEmpty
              ? 'Unable to sign in. Please try again.'
              : error.message),
  };
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final tenant = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final tenantFocus = FocusNode();

  bool busy = false;
  bool obscurePassword = true;
  String? error;

  @override
  void dispose() {
    tenant.dispose();
    email.dispose();
    password.dispose();
    tenantFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;

    final emailValue = email.text.trim();
    final passwordValue = password.text;
    final tenantValue = tenant.text.trim();

    if (emailValue.isEmpty || passwordValue.isEmpty) {
      setState(() {
        error = 'Enter your email and password to continue.';
      });
      return;
    }

    final appState = context.read<AppState>();
    final attendance = context.read<AttendanceController>();

    setState(() {
      busy = true;
      error = null;
    });

    try {
      await appState.login(
        emailValue,
        passwordValue,
        tenant: tenantValue.isEmpty ? null : tenantValue,
      );

      if (appState.isSalesman) {
        await attendance.restore();
      }
    } catch (exception) {
      if (!mounted) return;

      setState(() {
        error = friendlyLoginError(exception);
      });

      if (exception is ApiException && exception.code == 'TENANT_REQUIRED') {
        tenantFocus.requestFocus();
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.route_rounded, size: 52),
                      const SizedBox(height: 20),
                      Text(
                        'FieldPulse',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text('Your offline-first work companion'),
                      const SizedBox(height: 6),
                      Text(
                        'Salesmen, supervisors, and sales managers can sign in.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: tenant,
                        focusNode: tenantFocus,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Company / Tenant code',
                          hintText: 'e.g. shahab-demo',
                          helperText:
                              'Optional unless your email is used in more than one company.',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        obscureText: obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => obscurePassword = !obscurePassword,
                            ),
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(busy ? 'Signing in…' : 'Sign in'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
