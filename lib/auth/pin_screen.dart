import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _pinLength = 4;

class _Dots extends StatelessWidget {
  final int filled;
  const _Dots(this.filled);
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _pinLength; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? C.ink : Colors.transparent,
                border: Border.all(color: i < filled ? C.ink : C.faint, width: 2),
              ),
            ),
        ],
      );
}

class _Keypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  const _Keypad({required this.onDigit, required this.onBackspace});

  Widget _key(String label, {VoidCallback? onTap, Widget? child}) => SizedBox(
        width: 84,
        height: 68,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Center(child: child ?? Text(label, style: ts(24, w: w5))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _key(d, onTap: () => onDigit(d)))],
          ),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(width: 96),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _key('0', onTap: () => onDigit('0'))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _key('', onTap: onBackspace, child: const Icon(Icons.backspace_outlined, size: 22, color: C.ink2)),
        ),
      ]),
    ]);
  }
}

/// Choose a new PIN (entered twice to confirm). Used right after a first-time
/// sign-in, or after "Forgot PIN?" re-authentication.
class SetPinScreen extends StatefulWidget {
  final String fullName;
  final Future<void> Function(String pin) onSet;
  const SetPinScreen({super.key, required this.fullName, required this.onSet});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  String _first = '';
  String _entry = '';
  bool _confirming = false;
  String? _error;
  bool _saving = false;

  void _digit(String d) {
    if (_saving || _entry.length >= _pinLength) return;
    setState(() {
      _error = null;
      _entry += d;
    });
    if (_entry.length == _pinLength) _onComplete();
  }

  void _backspace() {
    if (_saving || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _onComplete() async {
    if (!_confirming) {
      setState(() {
        _first = _entry;
        _entry = '';
        _confirming = true;
      });
      return;
    }
    if (_entry != _first) {
      setState(() {
        _error = "PINs didn't match — try again";
        _entry = '';
        _first = '';
        _confirming = false;
      });
      return;
    }
    setState(() => _saving = true);
    await widget.onSet(_entry);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_confirming ? 'Confirm your PIN' : 'Set a PIN', style: ts(24, w: w6)),
                const SizedBox(height: 6),
                Text(
                  _confirming
                      ? 'Enter it again to confirm'
                      : "Hi ${widget.fullName.isEmpty ? '' : widget.fullName.split(' ').first} — choose a $_pinLength-digit PIN to unlock BPOS from now on",
                  textAlign: TextAlign.center,
                  style: ts(14, c: C.muted, h: 1.4),
                ),
                const SizedBox(height: 32),
                _Dots(_entry.length),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: ts(13, c: C.red, w: w5)),
                ],
                const SizedBox(height: 32),
                if (_saving) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
                else _Keypad(onDigit: _digit, onBackspace: _backspace),
              ]),
            ),
          ),
        ),
      );
}

/// Numeric-PIN unlock for a known local profile, with "not you" / "forgot PIN"
/// escape hatches back to full email+password sign-in.
class PinLockScreen extends StatefulWidget {
  final String fullName, roleName;
  final Future<bool> Function(String pin) onVerify;
  final VoidCallback onSwitchUser;
  final VoidCallback onForgotPin;
  const PinLockScreen({
    super.key,
    required this.fullName,
    required this.roleName,
    required this.onVerify,
    required this.onSwitchUser,
    required this.onForgotPin,
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _entry = '';
  bool _checking = false;
  String? _error;

  void _digit(String d) {
    if (_checking || _entry.length >= _pinLength) return;
    setState(() {
      _error = null;
      _entry += d;
    });
    if (_entry.length == _pinLength) _submit();
  }

  void _backspace() {
    if (_checking || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _checking = true);
    final ok = await widget.onVerify(_entry);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _checking = false;
        _entry = '';
        _error = 'Wrong PIN';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircleAvatar(radius: 34, backgroundColor: C.skyTint, child: Icon(Icons.person, color: C.skyInk, size: 32)),
                const SizedBox(height: 16),
                Text(widget.fullName, style: ts(20, w: w6)),
                if (widget.roleName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Pill(widget.roleName, bg: C.soft, fg: C.ink2),
                ],
                const SizedBox(height: 28),
                _Dots(_entry.length),
                const SizedBox(height: 8),
                Text(_error ?? 'Enter PIN', style: ts(13, c: _error != null ? C.red : C.muted, w: w5)),
                const SizedBox(height: 28),
                if (_checking) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
                else _Keypad(onDigit: _digit, onBackspace: _backspace),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: widget.onSwitchUser,
                  child: Text(
                      'Not ${widget.fullName.isEmpty ? 'you' : widget.fullName.split(' ').first}? Sign in as someone else'),
                ),
                TextButton(onPressed: widget.onForgotPin, child: const Text('Forgot PIN?')),
              ]),
            ),
          ),
        ),
      );
}
