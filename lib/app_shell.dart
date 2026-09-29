import 'package:flutter/material.dart';
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
      home: widget.home,
    );
    if (_link != null) app = CaptainLinkScope(link: _link!, child: app);
    return StoreScope(store: store, child: app);
  }
}
