import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'link/captain_link.dart';
import 'link/link_models.dart';
import 'link/pos_host.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Shared bootstrap (store + theme + [MaterialApp]) for every flavor entry point,
/// so `main_pos.dart`/`main_captain.dart` only differ in title and home screen.
///
/// [hostCaptains]: this is the main POS; it opens the captain link on the
/// restaurant Wi-Fi at startup. [captain]: this is a captain device; its Store
/// mirrors the POS through a [CaptainLink]. [kitchen]: this is a kitchen
/// display; it mirrors the POS the same way, paired as a kitchen device.
class BposApp extends StatefulWidget {
  final String title;
  final Widget home;
  final bool hostCaptains;
  final bool captain;
  final bool kitchen;
  const BposApp(
      {super.key, required this.title, required this.home, this.hostCaptains = false, this.captain = false, this.kitchen = false});

  @override
  State<BposApp> createState() => _BposAppState();
}

class _BposAppState extends State<BposApp> {
  late final store = Store(mirror: widget.captain || widget.kitchen, dbName: widget.kitchen ? 'bpos_kitchen' : null);
  PosHost? _host;
  CaptainLink? _link;

  @override
  void initState() {
    super.initState();
    if (widget.hostCaptains) _host = PosHost(store)..start();
    if (widget.captain || widget.kitchen) {
      _link = CaptainLink(store, kind: widget.kitchen ? deviceKitchen : deviceCaptain)..init();
    }
  }

  @override
  void dispose() {
    _host?.stop();
    _link?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget app = MaterialApp(
      title: widget.title,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _ExitGuard(child: widget.home),
    );
    if (_link != null) app = CaptainLinkScope(link: _link!, child: app);
    return StoreScope(store: store, child: app);
  }
}

/// Wraps the root screen so the system back button can't close the app by accident
/// (a stray swipe on a till or kitchen phone would drop the live session): the first
/// press shows a hint, a second within two seconds exits. Pushed screens pop as normal.
class _ExitGuard extends StatefulWidget {
  final Widget child;
  const _ExitGuard({required this.child});
  @override
  State<_ExitGuard> createState() => _ExitGuardState();
}

class _ExitGuardState extends State<_ExitGuard> {
  DateTime? _lastBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBack = now;
        toast(context, 'Press back again to exit');
      },
      child: widget.child,
    );
  }
}
