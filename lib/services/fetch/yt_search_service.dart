import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/search_engine_response.dart';
import '../../models/track.dart';
import '../../services/fuzzy_matcher.dart';
import '../database_service.dart';
import '../network/network_exception.dart';
import '../network/network_guard.dart';
import 'yt_music_innertube_service.dart';
import 'yt_utils.dart';

/// Specialized service for YouTube searches, catalog indexing, and album tracklist resolution
class YtSearchService {
  final YoutubeExplode _client;
  final YtMusicInnertubeService _innertubeService;

  // Search results Cache (Clean Query -> List<Track>)
  final Map<String, List<Track>> _searchCache = {};
  final Map<String, DateTime> _searchCacheTime = {};
  final Map<String, Future<List<Track>>> _searchInFlight = {};
  static const Duration _searchCacheTtl = Duration(minutes: 5);
  static const int _searchCacheMax = 60;

  // LRU Album Cache (Artist_Album or VideoId -> Album data)
  final Map<String, ({String? albumName, List<Track> tracks})> _albumCache = {};
  final Map<String, DateTime> _albumCacheTime = {};
  static const Duration _albumCacheTtl = Duration(minutes: 15);
  static const int _albumCacheMax = 80;

  YtSearchService({
    YoutubeExplode? client,
    YtMusicInnertubeService? innertubeService,
  })  : _client = client ?? YoutubeExplode(),
        _innertubeService = innertubeService ?? YtMusicInnertubeService(client: client);

  void clearCache() {
    _searchCache.clear();
    _searchCacheTime.clear();
    _searchInFlight.clear();
    _albumCache.clear();
    _albumCacheTime.clear();
  }

  void _cacheAlbumResult(String albumCacheKey, String trackId, ({String? albumName, List<Track> tracks}) res) {
    if (_albumCache.length >= _albumCacheMax) {
      final oldestKey = _albumCache.keys.first;
      _albumCache.remove(oldestKey);
      _albumCacheTime.remove(oldestKey);
    }
    final now = DateTime.now();
    _albumCache[albumCacheKey] = res;
    _albumCacheTime[albumCacheKey] = now;
    _albumCache[trackId] = res;
    _albumCacheTime[trackId] = now;
  }

  /// Search online tracks from YouTube with TTL cache and in-flight request dedup
  Future<List<Track>> searchOnlineTracks(String query, {int limit = 3}) async {
    final rawQuery = query;
    if (rawQuery.isEmpty) return [];

    final cacheKey = 'youtube:tracks:$rawQuery';

    // Serve from cache if not expired
    final cached = _searchCache[cacheKey];
    final cachedAt = _searchCacheTime[cacheKey];
    if (cached != null && cachedAt != null && DateTime.now().difference(cachedAt) < _searchCacheTtl) {
      return cached.length > limit ? cached.take(limit).toList() : cached;
    }

    // Deduplicate concurrent identical requests
    final inFlight = _searchInFlight[cacheKey];
    if (inFlight != null) {
      return await inFlight;
    }

    final future = _searchOnlineTracksUncached(rawQuery, limit: limit);
    _searchInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _searchInFlight.remove(cacheKey);
    }
  }

  Future<List<Video>> _fetchVideos(String query) async {
    try {
      return await _client.search
          .search(query, filter: TypeFilters.video)
          .timeout(const Duration(seconds: 5))
          .then((v) => v.toList());
    } on TimeoutException {
      throw const NetworkTimeoutException();
    } on SocketException catch (e) {
      throw NetworkUnavailableException(e.message);
    } on http.ClientException catch (e) {
      throw NetworkUnavailableException(e.message);
    }
  }

  Future<List<Track>> _searchOnlineTracksUncached(String rawQuery, {int limit = 3}) async {
    final cacheKey = 'youtube:tracks:$rawQuery';
    final persisted = await DatabaseService.instance.readSearchCache(cacheKey);
    if (persisted != null) {
      final decoded = jsonDecode(persisted) as List<dynamic>;
      return decoded
          .map((item) => Track.fromJson(Map<String, dynamic>.from(item as Map)))
          .take(limit)
          .toList();
    }
    try {
      // Network failures surface as typed errors (so the UI can distinguish
      // "no results" from "service unavailable"); empty results remain valid.
      final videoResults = await NetworkGuard.retryWithBackoff(
        operation: () => _fetchVideos(rawQuery),
        maxAttempts: 2,
      );

      final List<Track> tracks = [];
      for (final video in videoResults.take(limit)) {
        final cleaned = YtUtils.parseCleanTitleAndArtist(video.title, video.author);
        tracks.add(Track(
          id: video.id.value,
          title: cleaned['title'] ?? video.title,
          artist: cleaned['artist'] ?? video.author,
          artistId: video.channelId.value,
          album: 'Streaming Web',
          duration: video.duration?.inSeconds ?? 0,
          coverUrl: YtUtils.getBestThumbnail(video),
          audioUrl: 'yt://${video.id.value}',
          genre: 'Streaming Hi-Fi',
          ambientColor: YtUtils.pickAmbientColor(video.id.value),
          source: 'youtube',
        ));
      }

      if (tracks.isNotEmpty) {
        if (_searchCache.length >= _searchCacheMax) {
          // Evict oldest entries by insertion order
          final oldestKey = _searchCache.keys.first;
          _searchCache.remove(oldestKey);
          _searchCacheTime.remove(oldestKey);
        }
        _searchCache[cacheKey] = tracks;
        _searchCacheTime[cacheKey] = DateTime.now();
        unawaited(DatabaseService.instance.writeSearchCache(
          cacheKey: cacheKey,
          cacheType: 'youtube_tracks',
          queryText: rawQuery,
          payload: jsonEncode(tracks.map((track) => track.toJson()).toList()),
          ttl: _searchCacheTtl,
        ));
        return tracks;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[YtSearch] Error searching tracks: $e');
      rethrow;
    }

    return [];
  }

  /// Search YouTube Playlists directly by keyword query
  Future<List<Album>> searchPlaylists(String query, {int limit = 25}) async {
    final rawQuery = query;
    if (rawQuery.isEmpty) return [];
    final cacheKey = 'youtube:playlists:$rawQuery';
    final persisted = await DatabaseService.instance.readSearchCache(cacheKey);
    if (persisted != null) {
      final decoded = jsonDecode(persisted) as List<dynamic>;
      return decoded
          .map((item) => Album.fromJson(Map<String, dynamic>.from(item as Map)))
          .take(limit)
          .toList();
    }

    try {
      final searchResults = await NetworkGuard.retryWithBackoff<List<SearchResult>>(
        operation: () async {
          try {
            return await _client.search
                .searchContent(rawQuery, filter: TypeFilters.playlist)
                .timeout(const Duration(seconds: 5))
                .then((v) => v.toList());
          } on TimeoutException {
            throw const NetworkTimeoutException();
          } on SocketException catch (e) {
            throw NetworkUnavailableException(e.message);
          } on http.ClientException catch (e) {
            throw NetworkUnavailableException(e.message);
          }
        },
        maxAttempts: 2,
      );

      final List<Album> playlists = [];
      for (final item in searchResults) {
        if (item is SearchPlaylist) {
          String cover = '';
          if (item.thumbnails.isNotEmpty) {
            cover = item.thumbnails.last.url.toString();
          }

          playlists.add(Album(
            id: item.id.value,
            title: item.title,
            artist: '',
            coverUrl: cover,
            releaseYear: DateTime.now().year,
            tracksCount: item.videoCount,
            genre: 'YouTube Playlist',
            ambientColor: YtUtils.pickAmbientColor(item.id.value),
          ));

          if (playlists.length >= limit) break;
        }
      }

      unawaited(DatabaseService.instance.writeSearchCache(
        cacheKey: cacheKey,
        cacheType: 'youtube_playlists',
        queryText: rawQuery,
        payload: jsonEncode(playlists.map((playlist) => playlist.toJson()).toList()),
        ttl: _searchCacheTtl,
      ));
      return playlists;
    } catch (e) {
      if (kDebugMode) debugPrint('[YtSearch] Error searching playlists: $e');
      rethrow;
    }
  }

  /// Rank tracks by fuzzy relevance against the query (title + artist weighted).
  static List<Track> rankTracks(List<Track> tracks, String query, {int take = 0}) {
    if (tracks.isEmpty || query.trim().isEmpty) return List.from(tracks);
    final cleanQ = query.trim();

    final List<({Track track, double score})> scored = tracks.map((t) {
      final titleScore = FuzzyMatcher.calculateScore(query: cleanQ, title: t.title);
      // Boost when the query artist closely matches the track artist
      final artistScore = FuzzyMatcher.calculateScore(
        query: cleanQ,
        title: t.artist,
        subtitle: t.album,
      );
      final score = (titleScore * 0.85) + (artistScore * 0.15);
      return (track: t, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    final ranked = scored.map((e) => e.track).toList();
    return take > 0 ? ranked.take(take).toList() : ranked;
  }

  static String _extractVideoIdFromRenderer(Map<String, dynamic> renderer) {
    // 1. Direct title run watchEndpoint (Exact track link)
    final flexCols = renderer['flexColumns'] as List<dynamic>?;
    if (flexCols != null && flexCols.isNotEmpty) {
      final runs = flexCols[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
      if (runs != null && runs.isNotEmpty) {
        final flexId = runs[0]?['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
        if (flexId != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(flexId)) {
          return flexId;
        }
      }
    }

    // 2. Direct playlistItemData videoId
    final itemDataId = renderer['playlistItemData']?['videoId'] as String?;
    if (itemDataId != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(itemDataId)) {
      return itemDataId;
    }

    // 3. Double tap command watchEndpoint
    final doubleTapId = renderer['doubleTapCommand']?['watchEndpoint']?['videoId'] as String?;
    if (doubleTapId != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(doubleTapId)) {
      return doubleTapId;
    }

    // 4. Play button overlay
    final playNavId = renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
    if (playNavId != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(playNavId)) {
      return playNavId;
    }

    // 5. Menu items navigation (queue target only - never Radio)
    final menuItems = renderer['menu']?['menuRenderer']?['items'] as List<dynamic>?;
    if (menuItems != null) {
      for (final it in menuItems) {
        final queueNav = it?['menuServiceItemRenderer']?['serviceEndpoint']?['queueAddEndpoint']?['queueTarget']?['videoId'] as String?;
        if (queueNav != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(queueNav)) {
          return queueNav;
        }
      }
    }

    // 6. Deep search in overlay and play button only
    final overlayId = YtUtils.findDeepKey(renderer['overlay'], 'videoId') as String?;
    if (overlayId != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(overlayId)) {
      return overlayId;
    }

    // Note: Do NOT fall back to menuNavigationItemRenderer (Radio lead) or row navigationEndpoint.
    return '';
  }

  /// Search official YouTube Music tracks via InnerTube WEB_REMIX API
  Future<List<Track>> searchInnerTubeMusicTracks(String rawQuery, {int limit = 1}) async {
    final cacheKey = 'youtube:innertube_tracks:$rawQuery';
    final persisted = await DatabaseService.instance.readSearchCache(cacheKey);
    if (persisted != null) {
      try {
        final list = (jsonDecode(persisted) as List)
            .map((j) => Track.fromJson(j as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) return list.take(limit).toList();
      } catch (_) {}
    }

    try {
      final res = await http.post(
        Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Content-Type': 'application/json',
          'Origin': 'https://music.youtube.com',
        },
        body: jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20240318.01.00',
              'hl': 'en',
              'gl': 'FR',
            }
          },
          'query': rawQuery,
          'params': 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D', // Filter for Songs on YTM
        }),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final List<Track> tracks = [];
        void extractSongs(dynamic obj) {
          if (obj is Map<String, dynamic>) {
            if (obj.containsKey('musicResponsiveListItemRenderer')) {
              final renderer = obj['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
              final flexColumns = renderer['flexColumns'] as List<dynamic>? ?? [];
              String title = '';
              String artist = '';
              String album = 'Streaming Web';
              if (flexColumns.isNotEmpty) {
                final runs = flexColumns[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                if (runs != null && runs.isNotEmpty) {
                  title = runs[0]['text'] ?? '';
                }
              }
              String artistId = '';
              String albumBrowseId = '';
              if (flexColumns.length > 1) {
                final runs = flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                if (runs != null && runs.isNotEmpty) {
                  artist = runs[0]['text'] ?? '';
                  for (final r in runs) {
                    final nav = r['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
                    if (nav != null) {
                      if (nav.startsWith('UC') && artistId.isEmpty) {
                        artistId = nav;
                      } else if ((nav.startsWith('MPREb_') || nav.startsWith('OLAK5uy_') || nav.startsWith('VL') || nav.startsWith('PL')) && albumBrowseId.isEmpty) {
                        albumBrowseId = nav;
                        album = r['text'] ?? album;
                      }
                    }
                  }
                  if (album == 'Single Web' && runs.length > 2) {
                    album = runs[2]['text'] ?? 'Streaming Web';
                  }
                }
              }
              if (flexColumns.length > 2) {
                final runs = flexColumns[2]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                if (runs != null && runs.isNotEmpty) {
                  for (final r in runs) {
                    final nav = r['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
                    if (nav != null && (nav.startsWith('MPREb_') || nav.startsWith('OLAK5uy_') || nav.startsWith('VL') || nav.startsWith('PL')) && albumBrowseId.isEmpty) {
                      albumBrowseId = nav;
                      album = r['text'] ?? album;
                      break;
                    }
                  }
                  if (album == 'Single Web') {
                    album = runs[0]['text'] ?? album;
                  }
                }
              }

              final durationSeconds = YtUtils.extractDurationFromRenderer(renderer);
              final vId = _extractVideoIdFromRenderer(renderer);

              final thumbs = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List<dynamic>? ?? [];
              String cover = thumbs.isNotEmpty ? thumbs.last['url'] as String? ?? '' : '';
              if (cover.contains('=')) {
                cover = cover.split('=')[0] + '=w600-h600-l90-rj';
              }

              final isExplicitTrack = YtUtils.extractIsExplicitFromRenderer(renderer);

              if (title.isNotEmpty && vId.isNotEmpty && !tracks.any((t) => t.id == vId)) {
                final cleaned = YtUtils.parseCleanTitleAndArtist(title, artist);
                tracks.add(Track(
                  id: vId,
                  title: cleaned['title']!,
                  artist: cleaned['artist']!,
                  artistId: artistId,
                  album: album,
                  albumId: albumBrowseId,
                  duration: durationSeconds > 0 ? durationSeconds : 180,
                  coverUrl: cover.isNotEmpty ? cover : 'https://i.ytimg.com/vi/$vId/hqdefault.jpg',
                  audioUrl: 'yt://$vId',
                  genre: 'Streaming Hi-Fi',
                  ambientColor: YtUtils.pickAmbientColor(vId),
                  isExplicit: isExplicitTrack,
                  source: 'music',
                ));
              }
              return;
            }
            for (final v in obj.values) {
              extractSongs(v);
            }
          } else if (obj is List<dynamic>) {
            for (final item in obj) {
              extractSongs(item);
            }
          }
        }

        extractSongs(data);
        if (tracks.isNotEmpty) {
          unawaited(DatabaseService.instance.writeSearchCache(
            cacheKey: cacheKey,
            cacheType: 'youtube_innertube_tracks',
            queryText: rawQuery,
            payload: jsonEncode(tracks.map((t) => t.toJson()).toList()),
            ttl: _searchCacheTtl,
          ));
          return tracks.take(limit).toList();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[InnerTubeSearch] Error: $e');
    }
    return [];
  }

  /// Complete unified search returning artists, albums, and tracks:
  /// Up to 3 tracks = InnerTube YouTube Music (source: 'music')
  /// Up to 5 next tracks = YouTube Video standard (source: 'youtube')
  /// Total max = strictly 8 tracks!
  Future<SearchEngineResponse> searchCatalog(String query) async {
    final rawQuery = query.trim();
    if (rawQuery.isEmpty) return SearchEngineResponse.empty();

    // 1 & 2: Fetch simultaneously in parallel via Future.wait
    // On ajoute un catchError pour empêcher qu'un crash de youtube_explode_dart ne tue la synchro
    final results = await Future.wait([
      searchInnerTubeMusicTracks(rawQuery, limit: 3).catchError((e) => <Track>[]),
      searchOnlineTracks(rawQuery, limit: 5).catchError((e) => <Track>[]),
    ]);

    final musicTracks = results[0];
    final ytTracks = results[1];

    final List<Track> combinedTracks = [];
    final Set<String> seenIds = {};

    for (final musicTrack in musicTracks) {
      if (!seenIds.contains(musicTrack.id)) {
        seenIds.add(musicTrack.id);
        combinedTracks.add(musicTrack.copyWith(source: 'music'));
      }
    }

    for (final ytTrack in ytTracks) {
      if (!seenIds.contains(ytTrack.id)) {
        seenIds.add(ytTrack.id);
        combinedTracks.add(ytTrack.copyWith(source: 'youtube'));
      }
      if (combinedTracks.length >= 8) break;
    }

    final Set<String> seenArtists = {};
    final List<Artist> artists = [];

    for (final track in combinedTracks) {
      final name = track.artist.trim();
      if (name.isNotEmpty && !seenArtists.contains(name.toLowerCase())) {
        seenArtists.add(name.toLowerCase());
        String cachedAvatar = '';
        try {
          final cached = await DatabaseService.instance.findArtistByName(name);
          if (cached != null && cached.avatarUrl.isNotEmpty) {
            cachedAvatar = cached.avatarUrl;
          }
        } catch (_) {}

        artists.add(Artist(
          id: track.artistId,
          name: name,
          avatarUrl: cachedAvatar,
          bannerUrl: '',
        ));
      }
    }

    // Persist artist avatar immediately if missing
    if (artists.isNotEmpty && artists.first.avatarUrl.isEmpty) {
      final firstArtist = artists.first;
      unawaited(() async {
        try {
          final details = await _innertubeService.getArtistChannelDetails(
            firstArtist.name,
            artistId: firstArtist.id,
          );
          if (details != null && details.logoUrl.isNotEmpty) {
            await DatabaseService.instance.saveArtistIndex(
              firstArtist.name,
              artistId: firstArtist.id,
              avatarUrl: details.logoUrl,
            );
          }
        } catch (_) {}
      }());
    }

    Object? bestMatch;
    if (combinedTracks.isNotEmpty) {
      bestMatch = combinedTracks.first;
    }
    if (bestMatch == null && artists.isNotEmpty) {
      bestMatch = artists.first;
    }

    return SearchEngineResponse(
      bestMatch: bestMatch,
      artists: artists,
      albums: const [],
      playlists: const [],
      tracks: combinedTracks,
    );
  }

  /// Fetch official album metadata and complete tracklist
  Future<({String? albumName, List<Track> tracks})> fetchAlbumDetailsAndTracks(Track track) async {
    final albumCacheKey = '${track.artist.toLowerCase()}_${(track.album.isNotEmpty ? track.album : track.title).toLowerCase()}';

    // Fresh cache hit by track id or album key
    if (_albumCache.containsKey(track.id) &&
        _albumCache[track.id]!.tracks.isNotEmpty &&
        DateTime.now().difference(_albumCacheTime[track.id] ?? DateTime(0)) < _albumCacheTtl) {
      return _albumCache[track.id]!;
    }
    if (_albumCache.containsKey(albumCacheKey) &&
        _albumCache[albumCacheKey]!.tracks.isNotEmpty &&
        DateTime.now().difference(_albumCacheTime[albumCacheKey] ?? DateTime(0)) < _albumCacheTtl) {
      return _albumCache[albumCacheKey]!;
    }

    try {
      final rawId = track.albumId.isNotEmpty ? track.albumId : track.id;
      final albumNameStr = track.album.isNotEmpty ? track.album : track.title;
      final isMprebAlbum = rawId.startsWith('MPREb_');
      final isStandardPlaylist = (rawId.startsWith('PL') && !rawId.startsWith('MPREb_'));
      final cleanPlId = rawId.startsWith('VL') ? rawId.substring(2) : rawId;

      String resolvedBrowseId = '';

      // === LE FAMEUX TEST DU POIDS (DATA-DRIVEN) ===
      // Au lieu de faire aveuglément confiance à l'ID retourné par la recherche,
      // on aspire la discographie officielle et on prend l'édition la plus remplie.
      if (track.artist.isNotEmpty && track.album.isNotEmpty && track.album != "Single" && track.album != "Single Web" && track.album != "Streaming Web") {
        try {
          final discography = await _innertubeService.getArtistReleasesAndPlaylists(track.artist, artistId: track.artistId);
          final matchingAlbums = discography.releases.where((a) {
            final t1 = a.title.toLowerCase();
            final t2 = track.album.toLowerCase();
            return t1 == t2 || t1.contains(t2) || t2.contains(t1);
          }).toList();

          if (matchingAlbums.isNotEmpty) {
            // Tri décroissant : L'album avec le plus de pistes (Deluxe/Extended) passe en N°1
            matchingAlbums.sort((a, b) => b.tracksCount.compareTo(a.tracksCount));
            resolvedBrowseId = matchingAlbums.first.id;
          }
        } catch (_) {}
      }

      // Fallback si la discographie n'a rien donné
      if (resolvedBrowseId.isEmpty) {
        if (isMprebAlbum || rawId.startsWith('OLAK5uy_') || rawId.startsWith('VL') || rawId.startsWith('PL')) {
          resolvedBrowseId = isMprebAlbum || rawId.startsWith('VL') ? rawId : 'VL$cleanPlId';
        } else if (track.album.isNotEmpty && track.album != "Single" && track.album != "Single Web" && track.album != "Master Hi-Fi • 320k eq") {
        // Resolve official album browseId via YouTube Music InnerTube Albums search
        try {
          final query = '${track.artist} ${track.album}'.trim();
          final ytmSearch = await http.post(
            Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
              'Content-Type': 'application/json',
              'Origin': 'https://music.youtube.com',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB_REMIX',
                  'clientVersion': '1.20240318.01.00',
                  'hl': 'en',
                  'gl': 'FR',
                }
              },
              'query': query,
              'params': 'EgWKAQIYAWoKEAkQBRAKEAMQBA%3D%3D', // Albums
            }),
          ).timeout(const Duration(seconds: 6));

          if (ytmSearch.statusCode == 200) {
            final data = jsonDecode(ytmSearch.body) as Map<String, dynamic>;
            final targetLower = track.album.toLowerCase().trim();
            void findBrowseId(dynamic obj) {
              if (obj is Map<String, dynamic>) {
                if (obj.containsKey('musicTwoRowItemRenderer')) {
                  final renderer = obj['musicTwoRowItemRenderer'];
                  final nav = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
                  final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
                  final titleText = (titleRuns != null && titleRuns.isNotEmpty ? titleRuns[0]['text'] as String? ?? '' : '').toLowerCase().trim();
                  if (nav != null && (nav.startsWith('MPREb_') || nav.startsWith('OLAK5uy_') || nav.startsWith('VL') || nav.startsWith('PL'))) {
                    if (resolvedBrowseId.isEmpty || titleText == targetLower || titleText.contains(targetLower) || targetLower.contains(titleText)) {
                      resolvedBrowseId = nav;
                    }
                  }
                }
                for (final v in obj.values) {
                  findBrowseId(v);
                }
              } else if (obj is List<dynamic>) {
                for (final item in obj) {
                  findBrowseId(item);
                }
              }
            }
            findBrowseId(data);
          }
        } catch (_) {}
      }
      } // <-- Ajout de l'accolade fermante pour `if (resolvedBrowseId.isEmpty) {`

      final isLikelyPlaylistOrAlbum = resolvedBrowseId.isNotEmpty ||
          rawId.startsWith('OLAK5uy_') ||
          rawId.startsWith('PL') ||
          rawId.startsWith('VL') ||
          rawId.startsWith('MPREb_') ||
          rawId.startsWith('RD') ||
          rawId.length > 15 ||
          track.genre == 'Playlist' ||
          track.genre == 'Album' ||
          track.genre == 'Playlist Track';

      if (isLikelyPlaylistOrAlbum) {
        final List<Track> directTracks = [];

        if (isStandardPlaylist && resolvedBrowseId.isEmpty) {
          try {
            final videos = await _client.playlists
                .getVideos(cleanPlId)
                .take(60)
                .toList()
                .timeout(const Duration(seconds: 8));

            for (final v in videos) {
              final cleaned = YtUtils.parseCleanTitleAndArtist(v.title, v.author);
              directTracks.add(Track(
                id: v.id.value,
                title: cleaned['title']!,
                artist: cleaned['artist']!,
                album: albumNameStr,
                duration: v.duration?.inSeconds ?? 200,
                coverUrl: YtUtils.getBestThumbnail(v),
                audioUrl: 'yt://${v.id.value}',
                genre: 'Playlist Track',
                ambientColor: YtUtils.pickAmbientColor(v.id.value),
              ));
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[PlaylistTracks] getVideos fallback: $e');
          }
        }

        if (directTracks.isEmpty) {
          try {
            final String browseId = resolvedBrowseId.isNotEmpty
                ? resolvedBrowseId
                : (isMprebAlbum || rawId.startsWith('VL') ? rawId : 'VL$cleanPlId');

            final res = await http.post(
              Uri.parse('https://music.youtube.com/youtubei/v1/browse?prettyPrint=false'),
              headers: {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
                'Content-Type': 'application/json',
                'Origin': 'https://music.youtube.com',
              },
              body: jsonEncode({
                'context': {
                  'client': {
                    'clientName': 'WEB_REMIX',
                    'clientVersion': '1.20240318.01.00',
                    'hl': 'en',
                    'gl': 'FR',
                  }
                },
                'browseId': browseId,
              }),
            ).timeout(const Duration(seconds: 6));

            if (res.statusCode == 200) {
              final data = jsonDecode(res.body) as Map<String, dynamic>;
              final contentsNode = data['contents'];
              final List<({String title, String artist, int duration, bool isExplicit, String vId})> rawItems = [];

              void extractItems(dynamic obj) {
                if (obj is Map<String, dynamic>) {
                  if (obj.containsKey('musicResponsiveListItemRenderer')) {
                    final renderer = obj['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
                    final flexColumns = renderer['flexColumns'] as List<dynamic>? ?? [];
                    String title = '';
                    String artist = track.artist;
                    if (flexColumns.isNotEmpty) {
                      final runs = flexColumns[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                      if (runs != null && runs.isNotEmpty) {
                        title = runs[0]['text'] ?? '';
                      }
                    }
                    if (flexColumns.length > 1) {
                      final runs = flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                      if (runs != null && runs.isNotEmpty) {
                        artist = runs[0]['text'] ?? track.artist;
                      }
                    }

                    final durationSeconds = YtUtils.extractDurationFromRenderer(renderer);
                    final vId = _extractVideoIdFromRenderer(renderer);
                    final isExplicitTrack = YtUtils.extractIsExplicitFromRenderer(renderer);

                    if (title.isNotEmpty) {
                      rawItems.add((
                        title: title,
                        artist: artist,
                        duration: durationSeconds > 0 ? durationSeconds : 180,
                        isExplicit: isExplicitTrack,
                        vId: vId,
                      ));
                    }
                    return;
                  }
                  for (final v in obj.values) {
                    extractItems(v);
                  }
                } else if (obj is List<dynamic>) {
                  for (final item in obj) {
                    extractItems(item);
                  }
                }
              }

              if (contentsNode != null) {
                extractItems(contentsNode);
              }

              // Count occurrences to detect ambiguous / shared video IDs (e.g. lead single attached to multiple tracks)
              final idCounts = <String, int>{};
              for (final it in rawItems) {
                if (it.vId.isNotEmpty) {
                  idCounts[it.vId] = (idCounts[it.vId] ?? 0) + 1;
                }
              }

              // Process 100% of album tracks with safety search when ID is missing or shared
              for (int idx = 0; idx < rawItems.length; idx++) {
                final item = rawItems[idx];
                String finalVid = item.vId;
                int finalDuration = item.duration;
                final isAmbiguousId = finalVid.isEmpty || (idCounts[finalVid] ?? 0) > 1;

                if (isAmbiguousId) {
                  try {
                    final query = '${item.artist.isNotEmpty ? item.artist : track.artist} ${item.title}'.trim();
                    final searchResults = await searchInnerTubeMusicTracks(query, limit: 5);

                    if (searchResults.isNotEmpty) {
                      final targetTitle = item.title.toLowerCase().trim();
                      Track? matched;

                      // 1. Match by title and matching explicit status
                      for (final s in searchResults) {
                        if (s.title.toLowerCase().contains(targetTitle) && s.isExplicit == item.isExplicit) {
                          matched = s;
                          break;
                        }
                      }

                      // 2. Fallback: Match by title
                      if (matched == null) {
                        for (final s in searchResults) {
                          if (s.title.toLowerCase().contains(targetTitle)) {
                            matched = s;
                            break;
                          }
                        }
                      }

                      final chosen = matched ?? searchResults.first;
                      finalVid = chosen.id;
                      if (finalDuration == 180 && chosen.duration > 0) {
                        finalDuration = chosen.duration;
                      }
                    }
                  } catch (_) {}
                }

                // Fallback ID if still empty: generate a unique track ID so no track is ever skipped
                if (finalVid.isEmpty) {
                  finalVid = 'album_track_${rawId}_${idx + 1}';
                }

                final bool isPlaylistParent = rawId.startsWith('VL') || rawId.startsWith('PL') || track.coverUrl.contains('sddefault.jpg') || track.genre == 'Playlist';
                final String trackCover = (!isPlaylistParent && track.coverUrl.isNotEmpty)
                    ? track.coverUrl
                    : (finalVid.isNotEmpty && !finalVid.startsWith('album_track_')
                        ? 'https://i.ytimg.com/vi/$finalVid/hqdefault.jpg'
                        : track.coverUrl);

                final cleaned = YtUtils.parseCleanTitleAndArtist(item.title, item.artist);
                directTracks.add(Track(
                  id: finalVid,
                  title: cleaned['title']!,
                  artist: cleaned['artist']!,
                  album: albumNameStr,
                  duration: finalDuration,
                  coverUrl: trackCover,
                  audioUrl: 'yt://$finalVid',
                  genre: 'Sortie Officielle',
                  ambientColor: YtUtils.pickAmbientColor(finalVid),
                  isExplicit: item.isExplicit,
                  source: 'music',
                ));
              }
            }
          } catch (_) {}
        }

        if (directTracks.isNotEmpty) {
          final res = (albumName: albumNameStr, tracks: directTracks);
          _cacheAlbumResult(albumCacheKey, track.id, res);
          return res;
        }

        return (albumName: albumNameStr, tracks: <Track>[]);
      }

      final targetAlbumQuery = (track.album != "Single Web" && track.album != "Master Hi-Fi • 320k eq" && track.album != "Single")
          ? '${track.artist} ${track.album}'
          : '${track.artist} Album';

      final searchResults = await _client.search
          .searchContent(targetAlbumQuery, filter: TypeFilters.playlist)
          .timeout(const Duration(seconds: 8))
          .then((v) => v.toList())
          .catchError((_) => <SearchResult>[]);

      SearchPlaylist? targetPlaylist;
      for (final item in searchResults) {
        if (item is SearchPlaylist) {
          if (item.videoCount >= 3 && item.videoCount <= 38) {
            targetPlaylist = item;
            break;
          }
        }
      }

      if (targetPlaylist != null) {
        final playlistVideos = await _client.playlists
            .getVideos(targetPlaylist.id)
            .take(24)
            .toList()
            .timeout(const Duration(seconds: 10))
            .catchError((_) => <Video>[]);

        final List<Track> albumTracks = [];
        for (final video in playlistVideos) {
          final cleaned = YtUtils.parseCleanTitleAndArtist(video.title, video.author);
          albumTracks.add(Track(
            id: video.id.value,
            title: cleaned['title']!,
            artist: cleaned['artist']!,
            album: targetPlaylist.title.trim(),
            duration: video.duration?.inSeconds ?? 210,
            coverUrl: YtUtils.getBestThumbnail(video),
            audioUrl: 'yt://${video.id.value}',
            genre: 'Sortie Officielle',
            ambientColor: YtUtils.pickAmbientColor(video.id.value),
          ));
        }

        final res = (albumName: targetPlaylist.title.trim(), tracks: albumTracks);
        _cacheAlbumResult(albumCacheKey, track.id, res);
        return res;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[YtSearch] Error fetching album details: $e');
      if (e is NetworkException) rethrow;
    }

    return (albumName: track.album.isNotEmpty ? track.album : track.title, tracks: <Track>[]);
  }

  /// Match a track within an artist's official discography or playlists
  Future<({Track? matchedTrack, Album? matchedAlbum, Track? matchedPlaylistTrack, Album? matchedPlaylist, List<Album> allReleases, List<Album> allPlaylists})> findMatchingReleaseTrack(
    Track firstTrack, {
    String cleanQuery = '',
    String artistId = '',
  }) async {
    try {
      final artistName = firstTrack.artist.trim();
      final data = await _innertubeService.getArtistReleasesAndPlaylists(artistName, artistId: artistId, limit: 30);

      // Priority 0: If the track directly belongs to an official album, use it directly!
      if (firstTrack.album.isNotEmpty &&
          firstTrack.album != 'Single' &&
          firstTrack.album != 'Single Web' &&
          firstTrack.album != 'Master Hi-Fi • 320k eq') {
        final existingInReleases = data.releases.where((r) =>
            (firstTrack.albumId.isNotEmpty && r.id == firstTrack.albumId) ||
            r.title.toLowerCase() == firstTrack.album.toLowerCase()
        ).firstOrNull;

        final directAlbum = existingInReleases ?? Album(
          id: firstTrack.albumId.isNotEmpty ? firstTrack.albumId : 'album_${firstTrack.id}',
          title: firstTrack.album,
          artist: firstTrack.artist,
          artistId: firstTrack.artistId,
          coverUrl: firstTrack.coverUrl,
          releaseYear: firstTrack.releaseYear,
          tracksCount: 10,
          genre: 'Album',
          ambientColor: firstTrack.ambientColor,
        );
        return (
          matchedTrack: firstTrack,
          matchedAlbum: directAlbum,
          matchedPlaylistTrack: null,
          matchedPlaylist: null,
          allReleases: data.releases,
          allPlaylists: data.playlists,
        );
      }

      // Clean searched title (strip "Artist - ", "(Audio)", "(Official Video)", etc.)
      String cleanTrackTitle = firstTrack.title;
      if (cleanTrackTitle.toLowerCase().startsWith('${artistName.toLowerCase()} - ')) {
        cleanTrackTitle = cleanTrackTitle.substring(artistName.length + 3);
      }
      cleanTrackTitle = cleanTrackTitle.replaceAll(
        RegExp(r'\s*\((audio|official\s+video|official\s+audio|lyrics|official\s+music\s+video)\)', caseSensitive: false),
        '',
      ).trim();

      // Extract meaningful query tokens (length >= 2, excluding artist name)
      final meaningfulTokens = <String>{};
      final cleanTokens = (cleanQuery.isNotEmpty ? cleanQuery : cleanTrackTitle)
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .where((w) => w.length >= 2 && w != artistName.toLowerCase())
          .toList();
      meaningfulTokens.addAll(cleanTokens);

      final sortedReleases = List<Album>.from(data.releases);
      sortedReleases.sort((a, b) {
        int scoreA = 0;
        int scoreB = 0;
        final titleA = a.title.toLowerCase();
        final titleB = b.title.toLowerCase();

        // 1. Boost if album title contains meaningful query/track tokens (e.g. "legendary", "werk")
        for (final token in meaningfulTokens) {
          if (titleA.contains(token)) scoreA += 40;
          if (titleB.contains(token)) scoreB += 40;
        }

        // 2. Penalize generic compilations/years
        if (RegExp(r'^\d{4}\s').hasMatch(titleA) || titleA.contains('albums')) scoreA -= 50;
        if (RegExp(r'^\d{4}\s').hasMatch(titleB) || titleB.contains('albums')) scoreB -= 50;

        // 3. Penalize collaborative / mixtapes
        if (titleA.startsWith('\$') || titleA.contains('&')) scoreA -= 20;
        if (titleB.startsWith('\$') || titleB.contains('&')) scoreB -= 20;

        // 4. Prefer official solo artist album
        if (titleA.contains(artistName.toLowerCase())) scoreA += 10;
        if (titleB.contains(artistName.toLowerCase())) scoreB += 10;

        return scoreB.compareTo(scoreA);
      });

      double highestScore = 0.0;
      Album? bestAlbum;
      Track? bestMatchedTrack;

      // Check releases in parallel chunks
      const chunkSize = 5;
      for (int i = 0; i < sortedReleases.length; i += chunkSize) {
        final chunk = sortedReleases.sublist(i, min(i + chunkSize, sortedReleases.length));
        final detailsList = await Future.wait(
          chunk.map((rel) => fetchAlbumDetailsAndTracks(Track(
            id: rel.id,
            title: rel.title,
            artist: artistName,
            album: rel.title,
            coverUrl: rel.coverUrl,
            audioUrl: 'yt://${rel.id}',
            duration: 180,
            genre: 'Sortie Officielle',
            ambientColor: rel.ambientColor,
          ))),
        );

        for (int j = 0; j < chunk.length; j++) {
          final rel = chunk[j];
          final details = detailsList[j];

          for (final t in details.tracks) {
            final trackScore = FuzzyMatcher.calculateScore(
              query: cleanTrackTitle,
              title: t.title,
              subtitle: t.artist,
              isYoutubeTitle: true,
            );

            if (trackScore < 70.0) continue;

            double combinedScore = trackScore;
            final relTitleLower = rel.title.toLowerCase();

            // Penalize generic year compilations or generic lists
            if (RegExp(r'^\d{4}\s').hasMatch(relTitleLower) || relTitleLower.endsWith(' albums') || relTitleLower.contains('albums')) {
              combinedScore -= 40;
            }
            // Penalize joint / collaborative albums ("$TARFACE & ...")
            if (relTitleLower.startsWith('\$') || relTitleLower.contains('&')) {
              combinedScore -= 20;
            }
            for (final token in meaningfulTokens) {
              if (relTitleLower.contains(token)) combinedScore += 20;
            }

            if (combinedScore > highestScore) {
              highestScore = combinedScore;
              bestAlbum = rel;
              bestMatchedTrack = t;
            }
          }
        }

        // If high confidence match (>= 120), exit early
        if (highestScore >= 120.0) break;
      }

      if (bestAlbum != null) {
        return (
          matchedTrack: bestMatchedTrack,
          matchedAlbum: bestAlbum,
          matchedPlaylistTrack: null,
          matchedPlaylist: null,
          allReleases: sortedReleases,
          allPlaylists: <Album>[],
        );
      }

      // Search in playlists
      for (final pl in data.playlists) {
        final details = await fetchAlbumDetailsAndTracks(Track(
          id: pl.id,
          title: pl.title,
          artist: artistName,
          album: pl.title,
          coverUrl: pl.coverUrl,
          audioUrl: 'yt://${pl.id}',
          duration: 180,
          genre: 'Playlist',
          ambientColor: pl.ambientColor,
        ));

        final matched = details.tracks.where((t) {
          return _trackTitleMatches(firstTrack, t);
        }).firstOrNull;

        if (matched != null) {
          return (
            matchedTrack: null,
            matchedAlbum: null,
            matchedPlaylistTrack: matched,
            matchedPlaylist: pl,
            allReleases: data.releases,
            allPlaylists: data.playlists,
          );
        }
      }

      return (
        matchedTrack: null,
        matchedAlbum: null,
        matchedPlaylistTrack: null,
        matchedPlaylist: null,
        allReleases: data.releases,
        allPlaylists: data.playlists,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[YtSearch] Error finding matching release: $e');
      if (e is NetworkException) rethrow;
    }

    return (
      matchedTrack: null,
      matchedAlbum: null,
      matchedPlaylistTrack: null,
      matchedPlaylist: null,
      allReleases: <Album>[],
      allPlaylists: <Album>[],
    );
  }

  /// Fuzzy title comparison between the searched track and a discography track.
  /// Accent-insensitive, tolerates variants (Remaster, Radio Edit, Live, ...)
  /// via token similarity, and requires a minimum confidence to avoid false hits.
  static bool _trackTitleMatches(Track searched, Track candidate) {
    final score = FuzzyMatcher.calculateScore(
      query: searched.title,
      title: candidate.title,
      subtitle: candidate.artist,
      isYoutubeTitle: true,
    );
    return score >= 55.0;
  }
}
