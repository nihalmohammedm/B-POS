import 'dart:async';

/// One short, non-technical sentence for an exception, for showing to staff.
/// Errors we wrote ourselves (`message` carriers) pass through; network and parsing
/// failures become advice. The raw text belongs in the debug log, not on screen.
String plainError(Object e, {String fallback = 'Something went wrong. Please try again.'}) {
  if (e is String) return e;
  final raw = '$e'.toLowerCase();
  if (e is TimeoutException || raw.contains('timeout') || raw.contains('timed out')) {
    return 'The server is taking too long. Check the internet and try again.';
  }
  if (raw.contains('socketexception') ||
      raw.contains('clientexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection refused') ||
      raw.contains('network is unreachable') ||
      raw.contains('connection closed') ||
      raw.contains('handshake')) {
    return 'No internet connection. Check the Wi-Fi or data and try again.';
  }
  if (raw.contains('formatexception') || raw.contains('type \'')) return 'Got an unexpected reply from the server. Try again.';
  return fallback;
}

/// Turns an HTTP failure into advice instead of "path failed (401): {json}".
String plainHttpError(int status) {
  if (status == 401 || status == 403) return 'Not allowed. Please sign in again or ask the manager.';
  if (status == 404) return 'Not found on the server. Check the settings.';
  if (status == 429) return 'Too many requests. Wait a moment and try again.';
  if (status >= 500) return 'The server has a problem right now. Try again in a minute.';
  return 'Could not complete the request. Please try again.';
}
