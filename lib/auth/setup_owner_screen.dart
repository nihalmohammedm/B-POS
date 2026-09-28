import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Shown only once per outlet — when nobody has been linked to it yet. Creates
/// the very first account (always the Owner role) so the restaurant can start
/// setting up staff logins from inside the app instead of the Supabase dashboard.
class SetupOwnerScreen extends StatefulWidget {
  final String outletName;
  final Future<String?> Function(String fullName, String email, String password) onSubmit;
  const SetupOwnerScreen({super.key, required this.outletName, required this.onSubmit});

  @override
  State<SetupOwnerScreen> createState() => _SetupOwnerScreenState();
}

class _SetupOwnerScreenState extends State<SetupOwnerScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Fill in every field');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = "Passwords don't match");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit(_name.text.trim(), _email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Panel(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Set up ${widget.outletName.isEmpty ? 'this outlet' : widget.outletName}', style: ts(22, w: w6)),
                    const SizedBox(height: 6),
                    Text('No staff account exists yet — create the first Owner login to get started.',
                        style: ts(14, c: C.muted, h: 1.4)),
                    const SizedBox(height: 24),
                    const Label('Full name'),
                    const SizedBox(height: 6),
                    TextField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(hintText: 'Owner name')),
                    const SizedBox(height: 16),
                    const Label('Username'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(hintText: 'you@outlet.com'),
                    ),
                    const SizedBox(height: 16),
                    const Label('Password'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: 'At least 8 characters',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Label('Confirm password'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _confirm,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      decoration: const InputDecoration(hintText: 'Retype password'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: ts(13, c: C.red, w: w5)),
                    ],
                    const SizedBox(height: 24),
                    Btn(_busy ? 'Creating…' : 'Create Owner account', expand: true, onTap: _busy ? null : _submit),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
