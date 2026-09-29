/// Browsers can't send UDP or open raw sockets, so a captain running in a
/// browser can only reach the POS at the address it paired with.
Future<List<String>> discoverPos({String? posId, required int port, bool sweep = false}) async => const [];
