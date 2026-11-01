import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/track.dart';

/// Clean, standard just_audio player service with granular telemetry logs
class AudioPlayerService {
  static bool enableAudioLogs = kDebugMode;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _logSubscription;
  Future<void> _commandTail = Future<void>.value();
  bool _isDisposed = false;

  AudioPlayerService() {
    if (enableAudioLogs) {
      // Kept separate from the provider subscription and cancelled on dispose.
      _logSubscription = _player.playerStateStream.listen((state) {
        if (kDebugMode && enableAudioLogs) {
          debugPrint('[PlayerState] 🔄 État: ${state.processingState} | En lecture: ${state.playing}');
        }
      });
    }
  }

  AudioPlayer get player => _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get volumeStream => _player.volumeStream;

  Duration get currentPosition => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;

  /// Serializes all mutations of the native player. A failed command does not
  /// poison the queue: later commands still run, while the original caller
  /// receives the original error.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_isDisposed) {
      return Future<T>.error(StateError('AudioPlayerService is disposed'));
    }

    final completer = Completer<T>();
    final previous = _commandTail;
    _commandTail = previous.then<void>((_) async {
      if (_isDisposed) {
        completer.completeError(StateError('AudioPlayerService is disposed'));
        return;
      }
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _setAudioSource(AudioSource source, {Track? track}) async {
    try {
      await _player.setAudioSource(source);
    } catch (e) {
      if (kDebugMode && enableAudioLogs) {
        debugPrint('[AudioPlayer] ⚠️ setAudioSource standard failed: $e');
      }
      if (source is UriAudioSource && source.tag != null) {
        if (kDebugMode && enableAudioLogs) {
          debugPrint('[AudioPlayer] 🔄 Retry setAudioSource direct sans tag MediaItem...');
        }
        await _player.setAudioSource(AudioSource.uri(source.uri));
      } else {
        rethrow;
      }
    }
    if (kDebugMode && enableAudioLogs && track != null) {
      final displayDur = track.duration > 0 ? Duration(seconds: track.duration) : (_player.duration ?? Duration.zero);
      debugPrint('[AudioPlayer] 🎵 [4/4] Moteur prêt | Durée officielle: $displayDur (${track.duration}s)');
    }
  }

  Future<void> setAudioSource(AudioSource source, {Track? track}) async {
    await _enqueue(() => _setAudioSource(source, track: track));
  }

  Future<void> _setAudioTrack(Track track, {String? url}) async {
    await _player.stop();

    final mediaItem = MediaItem(
      id: track.id,
      album: track.album.isNotEmpty ? track.album : 'Single',
      title: track.title,
      artist: track.artist,
      artUri: track.coverUrl.isNotEmpty ? Uri.tryParse(track.coverUrl) : null,
      duration: track.duration > 0 ? Duration(seconds: track.duration) : null,
    );

    final audioSourceUrl = url ?? (track.audioUrl.startsWith('http') || track.audioUrl.startsWith('/') ? track.audioUrl : null);
    if (audioSourceUrl == null || audioSourceUrl.isEmpty) {
      throw StateError('Aucune URL audio valide pour "${track.title}"');
    }
    if (audioSourceUrl.startsWith('yt://')) {
      throw FormatException('URL de flux audio non résolue ou invalide: $audioSourceUrl');
    }

    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!isMobile && (audioSourceUrl.startsWith('http://') || audioSourceUrl.startsWith('https://'))) {
      await _player.setUrl(audioSourceUrl);
    } else {
      final dynamic sourceTag = isMobile ? mediaItem : null;
      final AudioSource source;
      if (audioSourceUrl.startsWith('http://') || audioSourceUrl.startsWith('https://')) {
        source = AudioSource.uri(Uri.parse(audioSourceUrl), tag: sourceTag);
      } else {
        final cleanPath = audioSourceUrl.startsWith('file://')
            ? audioSourceUrl.replaceFirst('file://', '')
            : audioSourceUrl;
        final file = File(cleanPath);
        if (!file.existsSync() || file.lengthSync() == 0) {
          throw FileSystemException('Fichier audio local introuvable ou vide', cleanPath);
        }
        source = AudioSource.file(cleanPath, tag: sourceTag);
      }
      await _player.setAudioSource(source);
    }

    if (kDebugMode && enableAudioLogs) {
      final displayDur = track.duration > 0 ? Duration(seconds: track.duration) : (_player.duration ?? Duration.zero);
      debugPrint('[AudioPlayer] 🎵 [4/4] Moteur prêt | Durée officielle: $displayDur (${track.duration}s)');
    }
  }

  Future<void> setAudioTrack(Track track, {String? url}) async {
    await _enqueue(() => _setAudioTrack(track, url: url));
  }

  Future<void> play() async {
    await _enqueue(() async {
      if (kDebugMode && enableAudioLogs) {
        debugPrint('[AudioPlayer] ▶️ Commande play() envoyée (état actuel: ${_player.processingState})...');
      }
      // just_audio's play() future completes when playback stops or finishes,
      // not when the command has been dispatched. Waiting for it here would
      // block pause/seek/source changes behind the first track forever.
      unawaited(_player.play().catchError((error, stackTrace) {
        if (kDebugMode) debugPrint('[AudioPlayer] ❌ play() ERROR: $error');
      }));
      if (kDebugMode && enableAudioLogs) {
        debugPrint('[AudioPlayer] 🔊 Son actif !');
      }
    });
  }

  Future<void> pause() async {
    await _enqueue(() async {
      if (_player.processingState == ProcessingState.idle) return;
      await _player.pause();
    });
  }

  Future<void> seek(Duration position) async {
    await _enqueue(() async {
      if (_player.processingState == ProcessingState.idle || _player.duration == null || _player.duration == Duration.zero) {
        return;
      }
      await _player.seek(position);
    });
  }

  Future<void> setVolume(double volume) async {
    await _enqueue(() => _player.setVolume(volume.clamp(0.0, 1.0)));
  }

  Future<void> stop() async {
    await _enqueue(_player.stop);
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _logSubscription?.cancel();
    unawaited(_player.dispose());
  }
}
