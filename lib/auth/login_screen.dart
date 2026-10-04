import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Email+password sign-in, labeled "Username" per the requested UX (any staff
/// email works — the field just isn't literally a separate username column, see
/// SupabaseAuthApi). Shared by the "add another staff login on this device" path
/// and the plain returning-outlet path from AuthGate.
class LoginScreen extends StatefulWidget {
  final String outletName;
  final Future<String?> Function(String email, String password) onSubmit;
  final VoidCallback? onCancel;
  const LoginScreen(
      {super.key,
      required this.outletName,
      required this.onSubmit,
      this.onCancel});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.onCancel != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              onPressed: widget.onCancel,
                              icon: const Icon(Icons.arrow_back, color: C.ink),
                            ),
                          ),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                              color: C.blueDeep, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 4))),
                        ),
                        const SizedBox(height: 16),
                        Text('BPOS', style: ts(24, w: w6)),
                        const SizedBox(height: 4),
                        Text(
                            widget.outletName.isEmpty
                                ? 'Sign in to continue'
                                : widget.outletName,
                            style: ts(14, c: C.muted)),
                        const SizedBox(height: 28),
                        const Label('Username'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _email,
                          autofocus: true,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email
                          ],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration:
                              const InputDecoration(hintText: 'you@outlet.com'),
                        ),
                        const SizedBox(height: 16),
                        const Label('Password'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _password,
                          focusNode: _passwordFocus,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _busy ? null : _submit(),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(_error!, style: ts(13, c: C.red, w: w5)),
                        ],
                        const SizedBox(height: 24),
                        Btn(_busy ? 'Signing in…' : 'Sign in',
                            expand: true, onTap: _busy ? null : _submit),
                      ]),
                ),
              ),
            ),
          ),
        ),
      );
}
