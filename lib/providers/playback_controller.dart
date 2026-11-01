import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import '../services/audio_player_service.dart';

/// Thin injectable playback boundary. AudioProvider remains the compatibility
/// façade while new code can depend on this controller directly.
class PlaybackController extends ChangeNotifier {
  PlaybackController({AudioPlayerService? player}) : _player = player ?? AudioPlayerService();

  final AudioPlayerService _player;
  Track? _currentTrack;

  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _player.isPlaying;

  Future<void> playTrack(Track track, AudioSource source) async {
    _currentTrack = track;
    await _player.setAudioSource(source, track: track);
    await _player.play();
    notifyListeners();
  }

  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
