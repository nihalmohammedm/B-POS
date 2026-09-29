import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'kitchen/kds.dart';

void main() => runApp(const BposApp(title: 'BPOS Kitchen', home: KitchenGate(), kitchen: true));
