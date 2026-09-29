import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// "Ding-ding" of a counter service bell, as a 16-bit mono WAV: two strikes of
/// a few inharmonic partials that ring out, like struck metal. Built in code so
/// there's no sound file to ship or lose.
Uint8List bellWav({int rate = 22050}) {
  const f0 = 1320.0, seconds = 2.2, strikes = [0.0, 0.42];
  // (frequency ratio, loudness, decay per second)
  const partials = [(1.0, 1.0, 2.2), (2.0, .5, 3.0), (2.76, .35, 4.0), (5.4, .2, 6.0), (8.93, .1, 8.0)];
  final n = (rate * seconds).round();
  final pcm = Float64List(n);
  for (final at in strikes) {
    final start = (at * rate).round();
    for (var i = start; i < n; i++) {
      final t = (i - start) / rate;
      final attack = t < .002 ? t / .002 : 1.0; // no click at the strike
      var v = 0.0;
      for (final (r, a, d) in partials) {
        v += a * math.exp(-d * t) * math.sin(2 * math.pi * f0 * r * t);
      }
      pcm[i] += v * attack;
    }
  }
  final peak = pcm.fold<double>(0, (m, v) => math.max(m, v.abs()));
  final gain = peak == 0 ? 0.0 : .9 * 32767 / peak;

  final b = ByteData(44 + n * 2);
  void ascii(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // PCM chunk size
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little); // byte rate
  b.setUint16(32, 2, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(44 + i * 2, (pcm[i] * gain).round().clamp(-32768, 32767), Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Plays the bell on the kitchen display. On Android it plays as an alarm,
/// so it's heard even with the media volume turned down; the alarm volume
/// controls it.
class KitchenBell {
  AudioPlayer? _player;
  final _wav = bellWav();
  int _ringing = 0;

  Future<AudioPlayer> _ready() async {
    final p = _player;
    if (p != null) return p;
    final n = AudioPlayer();
    await n.setReleaseMode(ReleaseMode.stop);
    await n.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.alarm,
        contentType: AndroidContentType.sonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
    ));
    return _player = n;
  }

  /// Rings [times] times back to back (a cancellation rings twice). A ring
  /// asked for while one is playing is dropped rather than queued, so a burst
  /// of KOTs doesn't ring for a minute.
  Future<void> ring({int times = 1}) async {
    if (_ringing > 0) return;
    _ringing++;
    try {
      final p = await _ready();
      for (var i = 0; i < times; i++) {
        await p.play(BytesSource(_wav, mimeType: 'audio/wav'));
        await Future<void>.delayed(const Duration(milliseconds: 2300));
      }
    } catch (e) {
      debugPrint('Kitchen bell failed: $e');
    } finally {
      _ringing--;
    }
  }

  void dispose() => _player?.dispose();
}
