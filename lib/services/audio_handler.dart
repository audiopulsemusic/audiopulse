import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/album.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'database_service.dart';
import 'fuzzy_matcher.dart';

class _BrowsableAlbumEntry {
  final String key;
  final String title;
  final String artist;
  final String coverUrl;
  final List<Track> tracks;

  const _BrowsableAlbumEntry({
    required this.key,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.tracks,
  });
}

class AudioPulseHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  // Constantes officielles Android Auto MediaBrowser (Content Style & Search)
  static const String contentStyleSupportedKey =
      'android.media.browse.CONTENT_STYLE_SUPPORTED';
  static const String contentStyleBrowsableHintKey =
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
  static const String contentStylePlayableHintKey =
      'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
  static const String contentStyleGroupTitleHintKey =
      'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';
  static const String searchSupportedKey =
      'android.media.browse.SEARCH_SUPPORTED';

  static const int contentStyleListItem = 1;
  static const int contentStyleGridItem = 2;

  // Identifiants d'arborescence MediaBrowser
  static const String libraryNodeId = 'library';
  static const String favoritesNodeId = 'favorites';
  static const String playlistsNodeId = 'playlists';
  static const String albumsNodeId = 'albums';
  static const String playlistPrefix = 'playlist:';
  static const String albumPrefix = 'album:';
  static const String searchTrackPrefix = 'search/';

  static const double _minFuzzyScore = 55.0;
  static const int _maxTransientSearchCache = 50;

  final AudioPlayer _player;
  final DatabaseService _db;
  final Random _random = Random();

  /// Cache mémoire borné pour permettre à `playFromMediaId` et `getMediaItem`
  /// de lire immédiatement un titre issu d'une recherche en ligne Android Auto
  /// avant même qu'il ne soit persisté dans SQLite.
  final Map<String, Track> _transientSearchTracks = <String, Track>{};

  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function(int index)? onSkipToQueueItem;
  Future<void> Function(Track track, List<Track>? queue)? onPlayTrackWithQueue;
  Future<void> Function()? onResumeOrShuffleLibrary;
  Future<List<Track>> Function(String query)? onOnlineSearchFallback;

  /// Indique qu'une résolution de flux ou transition de piste est en cours.
  /// Empêche `audio_service` de passer en `AudioProcessingState.idle` (ce qui
  /// appelle `stopSelf()` / `deactivateMediaSession()` sur Android et efface
  /// `MPNowPlayingInfoCenter` sur iOS) pendant le changement de morceau.
  bool _isTransitioningTrack = false;
  bool _hasActiveSession = false;
  int? _currentQueueIndex;

  AudioPulseHandler(
    this._player, {
    DatabaseService? database,
  }) : _db = database ?? DatabaseService.instance {
    // Diffuse l'état du lecteur à Android / iOS / Android Auto (Buffering, Position, Index)
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('[AudioHandler] Player error: $e');
        }
      },
    );

    // CRITIQUE : playbackEventStream n'émet PAS lors des changements de `playing` (play/pause).
    // Sans écoute de playerStateStream, audio_service ne voit jamais playing=true et ne lance
    // jamais la notification média Android ni le widget MPNowPlayingInfoCenter sur iOS.
    _player.playerStateStream.listen((state) {
      if (state.playing && state.processingState == ProcessingState.ready) {
        _isTransitioningTrack = false;
      }
      _broadcastState();
    });

    // Met à jour la durée dans le MediaItem dès que le flux audio la résout
    _player.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero) {
        final currentItem = mediaItem.valueOrNull;
        if (currentItem != null &&
            (currentItem.duration == null ||
                currentItem.duration == Duration.zero)) {
          mediaItem.add(currentItem.copyWith(duration: duration));
        }
        _broadcastState();
      }
    });

    // Initialise immédiatement les systemActions (dont playFromSearch) pour que
    // Google Assistant et Android Auto détectent le support vocal dès le démarrage.
    _broadcastState();
  }

  /// Appelé par AudioProvider dès qu'un morceau est sélectionné (avant même la résolution réseau)
  /// pour maintenir la MediaSession active et afficher immédiatement les métadonnées.
  void notifyTrackLoading(MediaItem item) {
    _hasActiveSession = true;
    _isTransitioningTrack = true;
    mediaItem.add(item);
    _broadcastState();
  }

  /// Appelé lorsque le chargement d'un flux est terminé ou a échoué.
  void clearTransitionState() {
    _isTransitioningTrack = false;
    _broadcastState();
  }

  /// Synchronise la file d'attente `AudioProvider` vers la `MediaSession` Android Auto / iOS.
  void syncQueue(List<Track> tracks, {int? currentIndex}) {
    final items = tracks
        .map((track) => _trackToMediaItem(track))
        .toList(growable: false);
    queue.add(items);
    if (currentIndex != null && currentIndex >= 0 && currentIndex < items.length) {
      _currentQueueIndex = currentIndex;
    } else if (items.isEmpty) {
      _currentQueueIndex = null;
    }
    _broadcastState();
  }

  // ==== HELPERS BASE DE DONNÉES & CONVERSIONS MEDIAITEM ====

  Future<List<Track>> _safeGetAllTracks() async {
    try {
      return await _db.getAllTracks();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioHandler] getAllTracks error: $e');
      }
      return const [];
    }
  }

  Future<List<Playlist>> _safeGetAllPlaylists() async {
    try {
      return await _db.getAllPlaylists();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioHandler] getAllPlaylists error: $e');
      }
      return const [];
    }
  }

  Future<List<Album>> _safeGetAllAlbums() async {
    try {
      return await _db.getAllAlbums();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioHandler] getAllAlbums error: $e');
      }
      return const [];
    }
  }

  void _rememberTransientTracks(Iterable<Track> tracks) {
    for (final track in tracks) {
      if (_transientSearchTracks.length >= _maxTransientSearchCache &&
          !_transientSearchTracks.containsKey(track.id)) {
        _transientSearchTracks.remove(_transientSearchTracks.keys.first);
      }
      _transientSearchTracks[track.id] = track;
    }
  }

  MediaItem _trackToMediaItem(
    Track track, {
    String? contextPrefix,
    String? groupTitle,
  }) {
    final encodedTrackId = Uri.encodeComponent(track.id);
    final itemId = (contextPrefix != null && contextPrefix.isNotEmpty)
        ? '$contextPrefix/$encodedTrackId'
        : track.id;

    return MediaItem(
      id: itemId,
      album: track.album.isNotEmpty ? track.album : 'Single',
      title: track.title,
      artist: track.artist,
      artUri: track.coverUrl.isNotEmpty ? Uri.tryParse(track.coverUrl) : null,
      duration: track.duration > 0 ? Duration(seconds: track.duration) : null,
      playable: true,
      extras: <String, dynamic>{
        'trackId': track.id,
        'contextPrefix': ?contextPrefix,
        contentStyleGroupTitleHintKey: ?groupTitle,
      },
    );
  }

  MediaItem _playlistToMediaItem(Playlist playlist, {String? groupTitle}) {
    String cover = playlist.coverUrl;
    if (cover.isEmpty) {
      for (final track in playlist.tracks) {
        if (track.coverUrl.isNotEmpty) {
          cover = track.coverUrl;
          break;
        }
      }
    }
    final count = playlist.tracks.length;
    final encodedId = Uri.encodeComponent(playlist.id);

    return MediaItem(
      id: '$playlistPrefix$encodedId',
      title: playlist.title,
      displaySubtitle: '$count ${count > 1 ? "titres" : "titre"}',
      artUri: cover.isNotEmpty ? Uri.tryParse(cover) : null,
      playable: false,
      extras: <String, dynamic>{
        'playlistId': playlist.id,
        contentStylePlayableHintKey: contentStyleListItem,
        contentStyleGroupTitleHintKey: ?groupTitle,
      },
    );
  }

  MediaItem _albumToMediaItem(_BrowsableAlbumEntry album, {String? groupTitle}) {
    final count = album.tracks.length;
    final encodedKey = Uri.encodeComponent(album.key);

    return MediaItem(
      id: '$albumPrefix$encodedKey',
      title: album.title,
      artist: album.artist,
      displaySubtitle:
          '${album.artist} • $count ${count > 1 ? "titres" : "titre"}',
      artUri: album.coverUrl.isNotEmpty ? Uri.tryParse(album.coverUrl) : null,
      playable: false,
      extras: <String, dynamic>{
        'albumKey': album.key,
        contentStylePlayableHintKey: contentStyleListItem,
        contentStyleGroupTitleHintKey: ?groupTitle,
      },
    );
  }

  static bool _isSinglePlaceholderAlbum(String albumTitle) {
    final trimmed = albumTitle.trim();
    return trimmed.isEmpty ||
        trimmed == 'Single' ||
        trimmed == 'Streaming Web' ||
        trimmed == 'Hi-Fi Audio';
  }

  Future<List<_BrowsableAlbumEntry>> _loadBrowsableAlbums() async {
    final tracks = await _safeGetAllTracks();
    if (tracks.isEmpty) {
      return const [];
    }
    final storedAlbums = await _safeGetAllAlbums();
    final storedById = <String, Album>{
      for (final album in storedAlbums)
        if (album.id.isNotEmpty) album.id: album,
    };

    final grouped = <String, List<Track>>{};
    final metaByKey = <String, ({String title, String artist, String coverUrl})>{};

    for (final track in tracks) {
      if (_isSinglePlaceholderAlbum(track.album) && track.albumId.isEmpty) {
        continue;
      }
      final key = track.albumId.trim().isNotEmpty
          ? track.albumId.trim()
          : '${track.artist.trim().toLowerCase()}___${track.album.trim().toLowerCase()}';

      grouped.putIfAbsent(key, () => <Track>[]).add(track);
      if (!metaByKey.containsKey(key)) {
        final stored = storedById[track.albumId.trim()];
        metaByKey[key] = (
          title: (stored != null && stored.title.isNotEmpty)
              ? stored.title
              : track.album.trim(),
          artist: (stored != null && stored.artist.isNotEmpty)
              ? stored.artist
              : track.artist.trim(),
          coverUrl: (stored != null && stored.coverUrl.isNotEmpty)
              ? stored.coverUrl
              : track.coverUrl,
        );
      } else if (metaByKey[key]!.coverUrl.isEmpty && track.coverUrl.isNotEmpty) {
        final existing = metaByKey[key]!;
        metaByKey[key] = (
          title: existing.title,
          artist: existing.artist,
          coverUrl: track.coverUrl,
        );
      }
    }

    final entries = <_BrowsableAlbumEntry>[];
    grouped.forEach((key, albumTracks) {
      final meta = metaByKey[key]!;
      entries.add(_BrowsableAlbumEntry(
        key: key,
        title: meta.title.isNotEmpty ? meta.title : 'Album',
        artist: meta.artist.isNotEmpty ? meta.artist : 'Artiste inconnu',
        coverUrl: meta.coverUrl,
        tracks: List<Track>.unmodifiable(albumTracks),
      ));
    });

    entries.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return entries;
  }

  // ==== ANDROID AUTO MEDIA BROWSER INTERFACE ====

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.recentRootId) {
      final active = mediaItem.valueOrNull;
      if (active != null) {
        return [active.copyWith(playable: true)];
      }
      final tracks = await _safeGetAllTracks();
      if (tracks.isNotEmpty) {
        return [
          _trackToMediaItem(tracks.first, contextPrefix: libraryNodeId),
        ];
      }
      return const [];
    }

    if (parentMediaId == AudioService.browsableRootId) {
      return const [
        MediaItem(
          id: libraryNodeId,
          title: 'Ma Bibliothèque',
          playable: false,
          extras: <String, dynamic>{
            contentStylePlayableHintKey: contentStyleListItem,
          },
        ),
        MediaItem(
          id: favoritesNodeId,
          title: 'Favoris',
          playable: false,
          extras: <String, dynamic>{
            contentStylePlayableHintKey: contentStyleListItem,
          },
        ),
        MediaItem(
          id: playlistsNodeId,
          title: 'Mes Playlists',
          playable: false,
          extras: <String, dynamic>{
            contentStyleBrowsableHintKey: contentStyleListItem,
            contentStylePlayableHintKey: contentStyleListItem,
          },
        ),
        MediaItem(
          id: albumsNodeId,
          title: 'Albums',
          playable: false,
          extras: <String, dynamic>{
            contentStyleBrowsableHintKey: contentStyleGridItem,
            contentStylePlayableHintKey: contentStyleListItem,
          },
        ),
      ];
    }

    if (parentMediaId == libraryNodeId) {
      final tracks = await _safeGetAllTracks();
      return tracks
          .map((t) => _trackToMediaItem(t, contextPrefix: libraryNodeId))
          .toList();
    }

    if (parentMediaId == favoritesNodeId) {
      final tracks = await _safeGetAllTracks();
      return tracks
          .where((t) => t.isFavorite)
          .map((t) => _trackToMediaItem(t, contextPrefix: favoritesNodeId))
          .toList();
    }

    if (parentMediaId == playlistsNodeId) {
      final playlists = await _safeGetAllPlaylists();
      return playlists.map(_playlistToMediaItem).toList();
    }

    if (parentMediaId.startsWith(playlistPrefix)) {
      final encodedId = parentMediaId.substring(playlistPrefix.length);
      final playlistId = Uri.decodeComponent(encodedId);
      final playlists = await _safeGetAllPlaylists();
      final playlist = playlists.where((p) => p.id == playlistId).firstOrNull;
      if (playlist == null) {
        return const [];
      }
      final prefix = '$playlistPrefix$encodedId';
      return playlist.tracks
          .map((t) => _trackToMediaItem(t, contextPrefix: prefix))
          .toList();
    }

    if (parentMediaId == albumsNodeId) {
      final albums = await _loadBrowsableAlbums();
      return albums.map(_albumToMediaItem).toList();
    }

    if (parentMediaId.startsWith(albumPrefix)) {
      final encodedKey = parentMediaId.substring(albumPrefix.length);
      final albumKey = Uri.decodeComponent(encodedKey);
      final albums = await _loadBrowsableAlbums();
      final album = albums.where((a) => a.key == albumKey).firstOrNull;
      if (album == null) {
        return const [];
      }
      final prefix = '$albumPrefix$encodedKey';
      return album.tracks
          .map((t) => _trackToMediaItem(t, contextPrefix: prefix))
          .toList();
    }

    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (mediaId.startsWith(playlistPrefix) && !mediaId.contains('/')) {
      final playlistId =
          Uri.decodeComponent(mediaId.substring(playlistPrefix.length));
      final playlists = await _safeGetAllPlaylists();
      final playlist = playlists.where((p) => p.id == playlistId).firstOrNull;
      return playlist != null ? _playlistToMediaItem(playlist) : null;
    }

    if (mediaId.startsWith(albumPrefix) && !mediaId.contains('/')) {
      final albumKey =
          Uri.decodeComponent(mediaId.substring(albumPrefix.length));
      final albums = await _loadBrowsableAlbums();
      final album = albums.where((a) => a.key == albumKey).firstOrNull;
      return album != null ? _albumToMediaItem(album) : null;
    }

    final selection = await _resolvePlayableSelection(mediaId);
    if (selection == null) {
      return null;
    }
    return _trackToMediaItem(selection.track).copyWith(id: mediaId);
  }

  Future<({Track track, List<Track> queue})?> _resolvePlayableSelection(
    String mediaId,
  ) async {
    // 1. Piste ou dossier issu d'une playlist : "playlist:<encodedId>/<encodedTrackId>" ou "playlist:<encodedId>"
    if (mediaId.startsWith(playlistPrefix)) {
      final rest = mediaId.substring(playlistPrefix.length);
      final slashIndex = rest.indexOf('/');
      final playlistId = Uri.decodeComponent(
        slashIndex == -1 ? rest : rest.substring(0, slashIndex),
      );
      final trackId = slashIndex == -1
          ? null
          : Uri.decodeComponent(rest.substring(slashIndex + 1));

      final playlists = await _safeGetAllPlaylists();
      final playlist = playlists.where((p) => p.id == playlistId).firstOrNull;
      if (playlist == null || playlist.tracks.isEmpty) {
        return null;
      }
      final selectedTrack = trackId == null
          ? playlist.tracks.first
          : (playlist.tracks.where((t) => t.id == trackId).firstOrNull ??
              playlist.tracks.first);
      return (track: selectedTrack, queue: playlist.tracks);
    }

    // 2. Piste ou dossier issu d'un album : "album:<encodedKey>/<encodedTrackId>" ou "album:<encodedKey>"
    if (mediaId.startsWith(albumPrefix)) {
      final rest = mediaId.substring(albumPrefix.length);
      final slashIndex = rest.indexOf('/');
      final albumKey = Uri.decodeComponent(
        slashIndex == -1 ? rest : rest.substring(0, slashIndex),
      );
      final trackId = slashIndex == -1
          ? null
          : Uri.decodeComponent(rest.substring(slashIndex + 1));

      final albums = await _loadBrowsableAlbums();
      final album = albums.where((a) => a.key == albumKey).firstOrNull;
      if (album == null || album.tracks.isEmpty) {
        return null;
      }
      final selectedTrack = trackId == null
          ? album.tracks.first
          : (album.tracks.where((t) => t.id == trackId).firstOrNull ??
              album.tracks.first);
      return (track: selectedTrack, queue: album.tracks);
    }

    // 3. Piste issue des favoris : "favorites/<encodedTrackId>"
    if (mediaId.startsWith('$favoritesNodeId/')) {
      final trackId = Uri.decodeComponent(
        mediaId.substring(favoritesNodeId.length + 1),
      );
      final favTracks =
          (await _safeGetAllTracks()).where((t) => t.isFavorite).toList();
      final selected = favTracks.where((t) => t.id == trackId).firstOrNull;
      if (selected != null) {
        return (track: selected, queue: favTracks);
      }
    }

    // 4. Piste issue de la bibliothèque, de la recherche ou ID direct
    String rawTrackId = mediaId;
    if (mediaId.startsWith('$libraryNodeId/')) {
      rawTrackId = Uri.decodeComponent(
        mediaId.substring(libraryNodeId.length + 1),
      );
    } else if (mediaId.startsWith(searchTrackPrefix)) {
      rawTrackId = Uri.decodeComponent(
        mediaId.substring(searchTrackPrefix.length),
      );
    }

    final allTracks = await _safeGetAllTracks();
    final dbTrack = allTracks.where((t) => t.id == rawTrackId).firstOrNull;
    if (dbTrack != null) {
      return (track: dbTrack, queue: allTracks);
    }

    final transient = _transientSearchTracks[rawTrackId];
    if (transient != null) {
      return (track: transient, queue: <Track>[transient]);
    }

    return null;
  }

  Future<void> _dispatchTrackPlayback(Track track, List<Track> playQueue) async {
    _isTransitioningTrack = true;
    _broadcastState();
    if (onPlayTrackWithQueue != null) {
      await onPlayTrackWithQueue!(track, playQueue);
    } else {
      customEvent.add(<String, dynamic>{
        'action': 'playMediaId',
        'mediaId': track.id,
        'queue': playQueue,
      });
    }
  }

  // ==== RECHERCHE VISUELLE & RECHERCHE VOCALE ANDROID AUTO ====

  static final RegExp _playlistVoiceRegex = RegExp(
    r'^(?:(?:joue|mets|lance|ecoute|lire|play|start)\s+)?(?:(?:ma|la|les|mes|une|my|the)\s+)?playlists?\s+(.+)$',
  );
  static final RegExp _albumVoiceRegex = RegExp(
    r'^(?:(?:joue|mets|lance|ecoute|lire|play|start)\s+)?(?:(?:l|le|mon|cet|the|an?)\s+)?albums?\s+(.+)$',
  );
  static final RegExp _genericVerbVoiceRegex = RegExp(
    r'^(?:joue|mets|lance|ecoute|lire|play|start|listen\s+to)\s+(.+)$',
  );

  static String _stripVoiceCommandVerbs(String raw) {
    final norm = FuzzyMatcher.normalize(raw);
    final match = _genericVerbVoiceRegex.firstMatch(norm);
    return match != null ? match.group(1)!.trim() : raw.trim();
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final cleanQuery = _stripVoiceCommandVerbs(query.trim());
    if (cleanQuery.isEmpty) {
      return const [];
    }

    final results = <MediaItem>[];

    // 1. Playlists locales correspondantes
    final playlists = await _safeGetAllPlaylists();
    final scoredPlaylists = <({Playlist playlist, double score})>[];
    for (final pl in playlists) {
      final score = FuzzyMatcher.calculateScore(
        query: cleanQuery,
        title: pl.title,
        subtitle: pl.description,
      );
      if (score >= _minFuzzyScore) {
        scoredPlaylists.add((playlist: pl, score: score));
      }
    }
    scoredPlaylists.sort((a, b) => b.score.compareTo(a.score));
    for (final entry in scoredPlaylists.take(5)) {
      results.add(
        _playlistToMediaItem(entry.playlist, groupTitle: 'Playlists'),
      );
    }

    // 2. Albums locaux correspondants
    final albums = await _loadBrowsableAlbums();
    final scoredAlbums = <({_BrowsableAlbumEntry album, double score})>[];
    for (final alb in albums) {
      final score = FuzzyMatcher.calculateScore(
        query: cleanQuery,
        title: alb.title,
        subtitle: alb.artist,
      );
      if (score >= _minFuzzyScore) {
        scoredAlbums.add((album: alb, score: score));
      }
    }
    scoredAlbums.sort((a, b) => b.score.compareTo(a.score));
    for (final entry in scoredAlbums.take(5)) {
      results.add(_albumToMediaItem(entry.album, groupTitle: 'Albums'));
    }

    // 3. Pistes locales correspondantes
    final tracks = await _safeGetAllTracks();
    final scoredTracks = <({Track track, double score})>[];
    for (final track in tracks) {
      final score = FuzzyMatcher.calculateScore(
        query: cleanQuery,
        title: track.title,
        subtitle: '${track.artist} ${track.album}',
      );
      if (score >= _minFuzzyScore) {
        scoredTracks.add((track: track, score: score));
      }
    }
    scoredTracks.sort((a, b) => b.score.compareTo(a.score));
    for (final entry in scoredTracks.take(15)) {
      results.add(
        _trackToMediaItem(
          entry.track,
          contextPrefix: libraryNodeId,
          groupTitle: 'Titres',
        ),
      );
    }

    // 4. Fallback catalogue en ligne si peu ou pas de titres locaux trouvés
    if (scoredTracks.length < 3 && onOnlineSearchFallback != null) {
      try {
        final onlineTracks = await onOnlineSearchFallback!(cleanQuery);
        if (onlineTracks.isNotEmpty) {
          _rememberTransientTracks(onlineTracks);
          final localIds = tracks.map((t) => t.id).toSet();
          for (final online in onlineTracks
              .where((t) => !localIds.contains(t.id))
              .take(10)) {
            results.add(
              _trackToMediaItem(
                online,
                contextPrefix: 'search',
                groupTitle: 'Catalogue en ligne',
              ),
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AudioHandler] Online search fallback error: $e');
        }
      }
    }

    return results;
  }

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final rawQuery = query.trim();
    final focus = (extras?['android.intent.extra.focus'] as String?)?.trim() ?? '';
    final extraPlaylist =
        (extras?['android.intent.extra.playlist'] as String?)?.trim() ?? '';
    final extraAlbum =
        (extras?['android.intent.extra.album'] as String?)?.trim() ?? '';
    final extraArtist =
        (extras?['android.intent.extra.artist'] as String?)?.trim() ?? '';
    final extraTitle =
        (extras?['android.intent.extra.title'] as String?)?.trim() ?? '';

    final hasStructuredExtras = extraPlaylist.isNotEmpty ||
        extraAlbum.isNotEmpty ||
        extraArtist.isNotEmpty ||
        extraTitle.isNotEmpty;

    // 1. Exigence Google Android Auto : requête vide ("Mets de la musique")
    // -> Reprendre la session active ou lancer la bibliothèque en aléatoire.
    if (rawQuery.isEmpty && !hasStructuredExtras) {
      if (onResumeOrShuffleLibrary != null) {
        await onResumeOrShuffleLibrary!();
        return;
      }
      final allTracks = await _safeGetAllTracks();
      if (allTracks.isNotEmpty) {
        final shuffled = List<Track>.from(allTracks)..shuffle(_random);
        await _dispatchTrackPlayback(shuffled.first, shuffled);
      } else if (onPlay != null) {
        await onPlay!();
      }
      return;
    }

    try {
      final normalizedRaw = FuzzyMatcher.normalize(rawQuery);
      final playlistRegexMatch = _playlistVoiceRegex.firstMatch(normalizedRaw);
      final albumRegexMatch = _albumVoiceRegex.firstMatch(normalizedRaw);

      final wantsPlaylist = focus.contains('playlist') ||
          extraPlaylist.isNotEmpty ||
          playlistRegexMatch != null;
      final wantsAlbum = focus.contains('album') ||
          (extraAlbum.isNotEmpty && extraTitle.isEmpty) ||
          albumRegexMatch != null;
      final wantsArtist = focus.contains('artist') ||
          (extraArtist.isNotEmpty && extraTitle.isEmpty && extraAlbum.isEmpty);

      final strippedQuery = _stripVoiceCommandVerbs(rawQuery);

      final playlists = (await _safeGetAllPlaylists())
          .where((p) => p.tracks.isNotEmpty)
          .toList();
      final albums = await _loadBrowsableAlbums();
      final tracks = await _safeGetAllTracks();

      // Score Playlists
      final playlistQuery = extraPlaylist.isNotEmpty
          ? extraPlaylist
          : (playlistRegexMatch?.group(1)?.trim() ?? strippedQuery);
      Playlist? bestPlaylist;
      double bestPlaylistScore = 0.0;
      if (playlistQuery.isNotEmpty) {
        for (final pl in playlists) {
          final score = FuzzyMatcher.calculateScore(
            query: playlistQuery,
            title: pl.title,
            subtitle: pl.description,
          );
          if (score > bestPlaylistScore) {
            bestPlaylistScore = score;
            bestPlaylist = pl;
          }
        }
      }

      if (wantsPlaylist &&
          bestPlaylist != null &&
          bestPlaylistScore >= _minFuzzyScore) {
        await _dispatchTrackPlayback(
          bestPlaylist.tracks.first,
          bestPlaylist.tracks,
        );
        return;
      }

      // Score Albums
      final albumQuery = extraAlbum.isNotEmpty
          ? extraAlbum
          : (albumRegexMatch?.group(1)?.trim() ?? strippedQuery);
      _BrowsableAlbumEntry? bestAlbum;
      double bestAlbumScore = 0.0;
      if (albumQuery.isNotEmpty) {
        for (final alb in albums) {
          double score = FuzzyMatcher.calculateScore(
            query: albumQuery,
            title: alb.title,
            subtitle: alb.artist,
          );
          if (extraArtist.isNotEmpty) {
            score += FuzzyMatcher.similarity(extraArtist, alb.artist) * 40.0;
          }
          if (score > bestAlbumScore) {
            bestAlbumScore = score;
            bestAlbum = alb;
          }
        }
      }

      if (wantsAlbum && bestAlbum != null && bestAlbumScore >= _minFuzzyScore) {
        await _dispatchTrackPlayback(
          bestAlbum.tracks.first,
          bestAlbum.tracks,
        );
        return;
      }

      // Score Artistes
      final artistQuery =
          extraArtist.isNotEmpty ? extraArtist : strippedQuery;
      List<Track> bestArtistTracks = const [];
      double bestArtistScore = 0.0;
      if (artistQuery.isNotEmpty && tracks.isNotEmpty) {
        final byArtist = <String, List<Track>>{};
        for (final track in tracks) {
          final artistName = track.artist.trim();
          if (artistName.isNotEmpty) {
            byArtist.putIfAbsent(artistName, () => <Track>[]).add(track);
          }
        }
        byArtist.forEach((artistName, artistTracks) {
          final score = FuzzyMatcher.calculateScore(
            query: artistQuery,
            title: artistName,
          );
          if (score > bestArtistScore) {
            bestArtistScore = score;
            bestArtistTracks = artistTracks;
          }
        });
      }

      if (wantsArtist &&
          bestArtistTracks.isNotEmpty &&
          bestArtistScore >= _minFuzzyScore) {
        await _dispatchTrackPlayback(
          bestArtistTracks.first,
          bestArtistTracks,
        );
        return;
      }

      // Score Pistes individuelles
      final trackQuery = extraTitle.isNotEmpty ? extraTitle : strippedQuery;
      Track? bestTrack;
      double bestTrackScore = 0.0;
      if (trackQuery.isNotEmpty) {
        for (final track in tracks) {
          double score = FuzzyMatcher.calculateScore(
            query: trackQuery,
            title: track.title,
            subtitle: '${track.artist} ${track.album}',
          );
          if (extraTitle.isNotEmpty && extraArtist.isNotEmpty) {
            score += FuzzyMatcher.similarity(extraArtist, track.artist) * 50.0;
          }
          if (score > bestTrackScore) {
            bestTrackScore = score;
            bestTrack = track;
          }
        }
      }

      // Arbitrage global pour une requête vocale libre (sans focus imposé)
      if (!wantsPlaylist && !wantsAlbum && !wantsArtist) {
        if (bestPlaylist != null &&
            bestPlaylistScore >= 140.0 &&
            bestPlaylistScore >= bestTrackScore) {
          await _dispatchTrackPlayback(
            bestPlaylist.tracks.first,
            bestPlaylist.tracks,
          );
          return;
        }

        if (bestAlbum != null &&
            bestAlbumScore >= 145.0 &&
            bestAlbumScore > bestTrackScore) {
          await _dispatchTrackPlayback(
            bestAlbum.tracks.first,
            bestAlbum.tracks,
          );
          return;
        }

        if (bestArtistTracks.length > 1 &&
            bestArtistScore >= 150.0 &&
            bestArtistScore > bestTrackScore) {
          await _dispatchTrackPlayback(
            bestArtistTracks.first,
            bestArtistTracks,
          );
          return;
        }
      }

      if (bestTrack != null && bestTrackScore >= _minFuzzyScore) {
        // Construit une file d'attente cohérente (morceaux du même artiste ou bibliothèque)
        final sameArtist = tracks
            .where((t) =>
                t.artist.trim().toLowerCase() ==
                bestTrack!.artist.trim().toLowerCase())
            .toList();
        final contextQueue = sameArtist.length > 1 ? sameArtist : tracks;
        await _dispatchTrackPlayback(bestTrack, contextQueue);
        return;
      }

      // Fallback recherche en ligne si rien ne correspond localement
      final fallbackQuery = <String>[
        if (extraTitle.isNotEmpty) extraTitle,
        if (extraArtist.isNotEmpty) extraArtist,
        if (extraAlbum.isNotEmpty) extraAlbum,
        if (extraPlaylist.isNotEmpty) extraPlaylist,
      ].join(' ').trim();
      final effectiveOnlineQuery =
          fallbackQuery.isNotEmpty ? fallbackQuery : strippedQuery;

      if (onOnlineSearchFallback != null && effectiveOnlineQuery.isNotEmpty) {
        final onlineTracks = await onOnlineSearchFallback!(effectiveOnlineQuery);
        if (onlineTracks.isNotEmpty) {
          _rememberTransientTracks(onlineTracks);
          await _dispatchTrackPlayback(onlineTracks.first, onlineTracks);
          return;
        }
      }

      clearTransitionState();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioHandler] playFromSearch error: $e');
      }
      clearTransitionState();
    }
  }

  // ==== PLAYBACK COMMANDS FROM CAR/LOCK SCREEN ====

  @override
  Future<void> play() async {
    if (onPlay != null) {
      await onPlay!();
    } else {
      await _player.play();
    }
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    if (onPause != null) {
      await onPause!();
    } else {
      await _player.pause();
    }
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    _isTransitioningTrack = false;
    _hasActiveSession = false;
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  @override
  Future<void> skipToNext() async {
    _isTransitioningTrack = true;
    _broadcastState();
    if (onSkipToNext != null) {
      await onSkipToNext!();
    } else {
      customEvent.add(const <String, dynamic>{'action': 'skipToNext'});
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _isTransitioningTrack = true;
    _broadcastState();
    if (onSkipToPrevious != null) {
      await onSkipToPrevious!();
    } else {
      customEvent.add(const <String, dynamic>{'action': 'skipToPrevious'});
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final currentQueue = queue.valueOrNull ?? const <MediaItem>[];
    if (index < 0 || (currentQueue.isNotEmpty && index >= currentQueue.length)) {
      return;
    }
    _isTransitioningTrack = true;
    _currentQueueIndex = index;
    _broadcastState();
    if (onSkipToQueueItem != null) {
      await onSkipToQueueItem!(index);
    } else {
      customEvent.add(<String, dynamic>{
        'action': 'skipToQueueItem',
        'index': index,
      });
    }
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final selection = await _resolvePlayableSelection(mediaId);
    if (selection != null) {
      await _dispatchTrackPlayback(selection.track, selection.queue);
      return;
    }

    // Fallback rétrocompatible si l'ID n'est pas encore en base mais connu du provider
    customEvent.add(<String, dynamic>{
      'action': 'playMediaId',
      'mediaId': mediaId,
      'extras': ?extras,
    });
  }

  // ==== SYNC STATE WITH AUDIO SERVICE ====

  void _broadcastState([PlaybackEvent? event]) {
    final playing = _player.playing || _isTransitioningTrack;
    final rawProcessingState = _player.processingState;

    // IMPORTANT : Tant qu'une session média est active (_hasActiveSession),
    // on ne diffuse JAMAIS `AudioProcessingState.idle` lors d'un stop() interne
    // entre deux morceaux, sinon `audio_service` appelle `stopService()` qui
    // détruit la MediaSession Android (`stopSelf()`) et vide `MPNowPlayingInfoCenter` sur iOS.
    final AudioProcessingState mappedState;
    if (_isTransitioningTrack) {
      mappedState = AudioProcessingState.loading;
    } else if (rawProcessingState == ProcessingState.idle && _hasActiveSession) {
      mappedState = AudioProcessingState.ready;
    } else {
      mappedState = const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[rawProcessingState]!;
    }

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.skipToQueueItem,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.playFromMediaId,
        MediaAction.playFromSearch,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: mappedState,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentQueueIndex ??
          event?.currentIndex ??
          playbackState.value.queueIndex,
    ));
  }
}
