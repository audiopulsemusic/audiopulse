import 'package:flutter/foundation.dart';

import '../data/mock_data.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/database_service.dart';

/// Canonical in-memory view of the persisted library. SQLite remains the
/// durable source of truth; all mutations go through this controller. The
/// controller starts from the curated mock library so the UI is never empty
/// before the database resolves; `refresh()` then replaces it with the
/// persisted truth (which, on a fresh install, contains the same mocks).
class LibraryController extends ChangeNotifier {
  LibraryController({DatabaseService? database})
      : _database = database ?? DatabaseService.instance,
        _tracks = List.from(mockTracks),
        _playlists = List.from(mockPlaylists);

  final DatabaseService _database;
  List<Track> _tracks;
  List<Playlist> _playlists;
  bool _disposed = false;

  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  Track? trackById(String id) {
    for (final track in _tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  Future<void> refresh() async {
    if (_disposed) return;
    var tracks = _tracks;
    var playlists = _playlists;
    try {
      tracks = await _database.getAllTracks();
    } catch (_) {
      // Keep the existing library on a transient read failure.
    }
    try {
      playlists = await _database.getAllPlaylists();
    } catch (_) {
      // Keep the existing library on a transient read failure.
    }
    _tracks = tracks;
    _playlists = playlists;
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> upsertTrack(Track track) async {
    if (_disposed) return;
    await _database.insertOrUpdateTrack(track);
    final next = List<Track>.from(_tracks);
    final index = next.indexWhere((item) => item.id == track.id);
    if (index == -1) {
      next.add(track);
    } else {
      next[index] = track;
    }
    _tracks = next;
    if (!_disposed) notifyListeners();
  }

  Future<void> setDownload(String id, String? path, bool downloaded) async {
    await _database.updateTrackDownload(id, path, downloaded);
    final track = trackById(id);
    if (track == null) return;
    await upsertTrack(track.copyWith(
      isDownloaded: downloaded,
      localFilePath: path,
      clearLocalFilePath: !downloaded && path == null,
    ));
  }

  Future<void> setFavorite(String id, bool favorite) async {
    await _database.toggleFavorite(id, favorite);
    final track = trackById(id);
    if (track == null) return;
    await upsertTrack(track.copyWith(isFavorite: favorite));
  }

  Future<Playlist> createPlaylist(String title, String description) async {
    final playlist = await _database.createPlaylist(title, description);
    _playlists = [playlist, ..._playlists];
    if (!_disposed) notifyListeners();
    return playlist;
  }

  Future<bool> addToPlaylist(String playlistId, Track track) async {
    final added = await _database.addTrackToPlaylist(playlistId, track);
    if (added) await refresh();
    return added;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
