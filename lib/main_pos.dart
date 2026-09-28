import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'auth/auth_gate.dart';

void main() => runApp(const BposApp(title: 'BPOS', home: AuthGate()));
