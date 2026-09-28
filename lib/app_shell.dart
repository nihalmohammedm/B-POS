import 'package:flutter/material.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Shared bootstrap (store + theme + [MaterialApp]) for every flavor entry point,
/// so `main_pos.dart`/`main_captain.dart` only differ in title and home screen.
class BposApp extends StatefulWidget {
  final String title;
  final Widget home;
  const BposApp({super.key, required this.title, required this.home});

  @override
  State<BposApp> createState() => _BposAppState();
}

class _BposAppState extends State<BposApp> {
  final store = Store();
  @override
  Widget build(BuildContext context) => StoreScope(
        store: store,
        child: MaterialApp(
          title: widget.title,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: widget.home,
        ),
      );
}
