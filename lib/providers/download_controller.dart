import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../services/audio_fetch_service.dart';
import 'library_controller.dart';

/// Single owner for download mutations and progress publication.
class DownloadController extends ChangeNotifier {
  DownloadController({
    required LibraryController library,
    Future<String?> Function(
      Track track,
      void Function(double)? onProgress,
      void Function(int)? onBitrateResolved,
    )? fetchStream,
    int? maxRetries = 5,
    Duration? retryDelay = const Duration(milliseconds: 1500),
  })  : _library = library,
        _fetchStream = fetchStream ?? _defaultFetchStream,
        _maxRetries = maxRetries,
        _retryDelay = retryDelay;

  final LibraryController _library;
  final Future<String?> Function(
    Track track,
    void Function(double)? onProgress,
    void Function(int)? onBitrateResolved,
  ) _fetchStream;

  // Nullable fields make hot-reloaded instances from a previous class layout
  // safe: an old isolate may temporarily hold null for newly-added fields.
  final int? _maxRetries;
  final Duration? _retryDelay;
  final Map<String, Future<Track?>> _inFlight = {};
  final Map<String, double> _progress = {};

  Map<String, double> get progress => Map.unmodifiable(_progress);
  int get _retryLimit => (_maxRetries ?? 5).clamp(1, 5);
  Duration get _retryWait => _retryDelay ?? const Duration(milliseconds: 1500);

  static Future<String?> _defaultFetchStream(
    Track track,
    void Function(double)? onProgress, [
    void Function(int)? onBitrateResolved,
  ]) {
    return AudioFetchService.instance.downloadAudioStream(
      track,
      onProgress: onProgress,
      onBitrateResolved: onBitrateResolved,
    );
  }

  Future<Track?> download(Track track) {
    final existing = _inFlight[track.id];
    if (existing != null) return existing;
    final operation = _download(track);
    _inFlight[track.id] = operation;
    unawaited(operation.then<void>(
      (_) => _inFlight.remove(track.id),
      onError: (Object error, StackTrace stackTrace) => _inFlight.remove(track.id),
    ));
    return operation;
  }

  Future<Track?> _download(Track track) async {
    try {
      for (var attempt = 1; attempt <= _retryLimit; attempt++) {
        try {
          int? resolvedBitrate;
          final path = await _fetchStream(
            track,
            (value) {
              _progress[track.id] = value;
              notifyListeners();
            },
            (bitrate) {
              resolvedBitrate = bitrate;
            },
          );
          if (path != null) {
            final updated = track.copyWith(
              isDownloaded: true,
              localFilePath: path,
              bitrate: (resolvedBitrate != null && resolvedBitrate! > 0)
                  ? resolvedBitrate
                  : (track.bitrate > 0 ? track.bitrate : null),
            );
            await _library.upsertTrack(updated);
            return updated;
          }
          if (attempt < _retryLimit) {
            await Future<void>.delayed(_retryWait);
          }
        } catch (error) {
          if (kDebugMode) {
            debugPrint('[DownloadController] attempt $attempt/$_retryLimit failed: $error');
          }
          if (attempt < _retryLimit) {
            await Future<void>.delayed(_retryWait);
          }
        }
      }
      return null;
    } catch (error) {
      // Downloads are background/UI actions: failure is represented by null,
      // never by an unhandled future that can crash the application.
      if (kDebugMode) debugPrint('[DownloadController] download failed: $error');
      return null;
    } finally {
      _progress.remove(track.id);
      notifyListeners();
    }
  }
}
