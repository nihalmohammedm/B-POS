import '../store.dart';
import 'link_models.dart';

/// Browsers can't open a server socket, so a POS running in a web browser
/// can't host captains; it says so on the Captains screen.
class PosHost {
  final Store s;
  final int port;
  PosHost(this.s, {this.port = linkPort});
  bool get running => false;
  int get boundPort => port;

  Future<void> start() async => s.setLinkState(
      running: false, error: 'Captains can only connect when the POS runs as the Windows or Android app, not in a web browser.');
  Future<void> stop() async {}
}
