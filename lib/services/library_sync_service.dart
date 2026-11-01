import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../models/artist.dart';
import 'audio_fetch_service.dart';
import 'database_service.dart';

class LibrarySyncService {
  static final LibrarySyncService instance = LibrarySyncService._internal();
  LibrarySyncService._internal();

  bool _isPaused = false;
  bool _isCancelled = false;

  void pause() => _isPaused = true;
  void resume() => _isPaused = false;
  void cancel() => _isCancelled = true;

  /// Synchronise une liste de SORTIES (Albums/Singles).
  Future<void> syncReleases(
    List<String> releases, {
    required Function(int currentIndex, int total, String currentItemName) onProgress,
  }) async {
    _isPaused = false;
    _isCancelled = false;
    final total = releases.length;

    final List<Track> batchTracks = [];
    final List<Album> batchAlbums = [];
    final List<Artist> batchArtists = [];

    for (int i = 0; i < total; i++) {
      if (_isCancelled) break;

      while (_isPaused) {
        if (_isCancelled) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (_isCancelled) break;

      final release = releases[i]; // Format "Titre|||Artiste|||Album|||Duration"
      final parts = release.split('|||');
      if (parts.length < 2) continue;
      
      final trackTitle = parts[0].trim();
      String rawArtistName = parts[1].trim();
      final albumName = parts.length > 2 ? parts[2].trim() : 'Single';
      final durationStr = parts.length > 3 ? parts[3].trim() : '0';
      final int duration = int.tryParse(durationStr) ?? 0;

      if (trackTitle.isEmpty || trackTitle.toLowerCase() == 'inconnu' || trackTitle.toLowerCase() == 'unknown') continue;
      if (rawArtistName.isEmpty || rawArtistName.toLowerCase() == 'inconnu' || rawArtistName.toLowerCase() == 'unknown artist') continue;
      if (duration <= 0) continue;

      // Règle de l'utilisateur : nettoyer l'artiste
      String artistName = rawArtistName;
      if (artistName.contains(' & ')) {
        artistName = artistName.split(' & ')[0].trim();
      }
      if (artistName.contains(', ')) {
        artistName = artistName.split(', ')[0].trim();
      }
      
      if (i % 10 == 0) {
        onProgress(i + 1, total, "$trackTitle - $artistName");
      }

      try {
        final artistId = "local_art_${artistName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}";
        final albumId = "local_alb_${albumName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_$artistId";
        final trackId = "local_trk_${trackTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_$albumId";

        batchArtists.add(Artist(
          id: artistId,
          name: artistName,
          avatarUrl: '',
          bannerUrl: '',
        ));

        batchAlbums.add(Album(
          id: albumId,
          title: albumName,
          artist: artistName,
          artistId: artistId,
          coverUrl: '', 
          releaseYear: DateTime.now().year,
          tracksCount: 1, 
          genre: 'Imported',
          ambientColor: '#1A1A1A',
        ));

        batchTracks.add(Track(
          id: trackId,
          title: trackTitle,
          artist: artistName,
          artistId: artistId,
          album: albumName,
          albumId: albumId,
          coverUrl: '', 
          audioUrl: '', 
          duration: duration,
          genre: 'Imported',
          ambientColor: '#1A1A1A', 
          isFavorite: true,
          source: 'apple_import',
        ));

        if (batchTracks.length >= 250 || i == total - 1) {
          onProgress(i + 1, total, "Sauvegarde en base...");
          
          final currentTracks = List<Track>.from(batchTracks);
          final currentAlbums = List<Album>.from(batchAlbums);
          final currentArtists = List<Artist>.from(batchArtists);
          
          batchTracks.clear();
          batchAlbums.clear();
          batchArtists.clear();

          await DatabaseService.instance.saveRawImportBatch(currentTracks, currentAlbums, currentArtists);
          
          // Libère le thread principal et SQLite pour que l'UI reste parfaitement fluide
          await Future.delayed(const Duration(milliseconds: 50));
        }

      } catch (e) {
        if (kDebugMode) {
          debugPrint("⚠️ [LibrarySyncService] Erreur synchro brute $trackTitle : $e");
        }
      }
    }
  }
}

